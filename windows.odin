package fluid

import "core:fmt"
import "core:math"
import virtual "core:mem/virtual"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Window and Scene pointers expire on close. Transfer elements before closing
// their window to preserve their IDs; remaining IDs are invalidated on close.
Window :: struct {
	ui:              ^UI,
	using native:    Window_Resources,
	viewport:        Element_ID,
	background:      Color,
	scenes:          [dynamic]^Scene,
	close_requested: bool,
	effect:          Window_Effect,
	requested_flags: Maybe(sdl3.WindowFlags),
	storage:         virtual.Arena,
}

// These resources can be replaced while the logical window stays in place.
@(private="package")
Window_Resources :: struct {
	handle:           ^sdl3.Window,
	renderer:         ^sdl3.Renderer,
	fonts:            [Text_Weight][Text_Size]^ttf.Font,
	text_engine:      ^ttf.TextEngine,
	display_scale:    f32,
	coordinate_scale: f32,
	minimum_size:     [2]f32,
}

create_window :: proc(app: ^UI, config: Config) -> ^Window {
	context.allocator = virtual.arena_allocator(&app.storage)
	window: ^Window
	if len(app.free_windows) > 0 {
		window = pop(&app.free_windows)
	} else {
		window = new(Window)
	}
	window^ = Window{ui = app, background = {17, 23, 32, 255}}
	if background, specified := config.background.?; specified {
		window.background = background
	}
	if err := virtual.arena_init_growing(&window.storage); err != nil {
		append(&app.free_windows, window)
		return nil
	}
	window.scenes = make([dynamic]^Scene, virtual.arena_allocator(&window.storage))
	if !create_window_resources(&window.native, config) {
		virtual.arena_destroy(&window.storage)
		append(&app.free_windows, window)
		return nil
	}
	window.viewport = register_element(app, Element{space = window})
	sync_window_scale(window)
	sync_viewport(window)
	append(&app.windows, window)
	return window
}

@(private="package")
create_window_resources :: proc(window: ^Window_Resources, config: Config, placement: Maybe(sdl3.Rect) = nil) -> bool {
	success := false
	defer {
		if !success {
			fmt.eprintln("Cannot create window:", sdl3.GetError())
			release_window_resources(window)
		}
	}
	initial_size := native_window_size(config.size, 1)
	if rect, placed := placement.?; placed {
		initial_size = {rect.w, rect.h}
	}
	window.handle = sdl3.CreateWindow(config.title, initial_size[0], initial_size[1], config.flags | {.RESIZABLE, .HIGH_PIXEL_DENSITY, .HIDDEN})
	if window.handle == nil {
		return false
	}
	if rect, placed := placement.?; placed && !sdl3.SetWindowPosition(window.handle, rect.x, rect.y) {
		return false
	}
	window.display_scale, window.coordinate_scale = window_scales(window.handle)
	window.minimum_size = config.minimum_size
	if !apply_window_minimum_size(window) {
		return false
	}
	if placement == nil {
		size := native_window_size(config.size, window.coordinate_scale)
		if size != initial_size {
			display := sdl3.GetDisplayForWindow(window.handle)
			center := sdl3.WINDOWPOS_CENTERED_DISPLAY(i32(display))
			if !sdl3.SetWindowSize(window.handle, size[0], size[1]) ||
				!sdl3.SetWindowPosition(window.handle, center, center) {
				return false
			}
		}
	}
	window.renderer = sdl3.CreateRenderer(window.handle, nil)
	if window.renderer == nil {
		return false
	}
	// Each renderer presents to its own drawable and must synchronize it.
	if !sdl3.SetRenderVSync(window.renderer, 1) {
		return false
	}
	if !create_text_resources(window) || (.HIDDEN not_in config.flags && !sdl3.ShowWindow(window.handle)) {
		return false
	}
	success = true
	return true
}

// Change creation-only SDL flags without changing the Fluid window, scenes,
// or viewport ID. Call between frames; renderer-specific text is rebuilt.
@(private="package")
replace_window :: proc(window: ^Window, flags: sdl3.WindowFlags) -> bool {
	config := Config{
		title = sdl3.GetWindowTitle(window.handle),
		flags = flags | {.HIDDEN},
		minimum_size = window.minimum_size,
	}
	placement: sdl3.Rect
	if !sdl3.GetWindowSize(window.handle, &placement.w, &placement.h) ||
		!sdl3.GetWindowPosition(window.handle, &placement.x, &placement.y) {
		return false
	}

	replacement: Window_Resources
	if !create_window_resources(&replacement, config, placement) {
		return false
	}
	app := window.ui
	if id := app.focused; id != NO_ELEMENT && element_window(app, id) == window {
		detach_input(app, id)
	}
	if id := app.captured; id != NO_ELEMENT && element_window(app, id) == window {
		cancel_pointer(app, id)
	}
	release_window_text(window)
	previous := window.native
	window.native = replacement
	sync_window_scale(window)
	sync_viewport(window)
	if .HIDDEN in sdl3.GetWindowFlags(previous.handle) {
		present_window(window)
	} else if !show_window(window) {
		release_window_text(window)
		release_window_resources(&window.native)
		window.native = previous
		sync_viewport(window)
		return false
	}
	// Present again after showing: some backends skip hidden-window presentation.
	if .HIDDEN not_in sdl3.GetWindowFlags(window.handle) {
		present_window(window)
	}
	if app.drag.element != NO_ELEMENT && element_window(app, app.drag.element) == window {
		end_drag(app)
	}
	release_window_resources(&previous)
	return true
}

// Scenes are deactivated and native text is released before its renderer.
// Transfer any elements you want to keep using before closing their window.
close_window :: proc(window: ^Window) {
	if window.handle == nil {
		return
	}
	app := window.ui
	for scene in window.scenes {
		for len(scene.members) > 0 {
			remove(app, scene.members[len(scene.members) - 1])
		}
	}
	cancel_window_effect(window)
	window.requested_flags = nil
	remove(app, window.viewport)
	virtual.arena_destroy(&window.storage)
	release_window_resources(&window.native)
	for value, i in app.windows {
		if value == window {
			ordered_remove(&app.windows, i)
			break
		}
	}
	if window == app.window {
		app.running = false
	}
	append(&app.free_windows, window)
}

window_position :: proc(window: ^Window) -> [2]f32 {
	x, y: i32
	assert(sdl3.GetWindowPosition(window.handle, &x, &y))
	return {f32(x) / UI_UNIT_POINTS, f32(y) / UI_UNIT_POINTS}
}

pointer_position :: proc(window: ^Window) -> [2]f32 {
	mouse: [2]f32
	_ = sdl3.GetGlobalMouseState(&mouse[0], &mouse[1])
	return window_point(window, mouse / UI_UNIT_POINTS)
}

show_window :: proc(window: ^Window) -> bool {
	// Prime hidden content before making the window visible.
	present_window(window)
	if !sdl3.ShowWindow(window.handle) {
		return false
	}
	sync_window_scale(window)
	return true
}

@(private="package")
find_window :: proc(app: ^UI, id: sdl3.WindowID) -> ^Window {
	for window in app.windows {
		if sdl3.GetWindowID(window.handle) == id {
			return window
		}
	}
	return nil
}

@(private="package")
release_window_resources :: proc(window: ^Window_Resources) {
	release_text_resources(window)
	if window.renderer != nil {
		sdl3.DestroyRenderer(window.renderer)
	}
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
	}
	window^ = {}
}

// Creation-only flag changes are performed by Fluid before the next draw.
set_window_flags :: proc(window: ^Window, flags: sdl3.WindowFlags) {
	assert(window.handle != nil)
	window.requested_flags = flags
}

// Physical renderer pixels per UI unit.
pixel_scale :: proc(window: ^Window) -> f32 {
	return window.display_scale * UI_UNIT_POINTS
}

// Native SDL window coordinates per UI unit.
window_scale :: proc(window: ^Window) -> f32 {
	return window.coordinate_scale * UI_UNIT_POINTS
}

// Convert between window-local UI units and shared desktop coordinates.
desktop_point :: proc(window: ^Window, point: [2]f32) -> [2]f32 {
	return window_position(window) + point * window.coordinate_scale
}

window_point :: proc(window: ^Window, point: [2]f32) -> [2]f32 {
	return (point - window_position(window)) / window.coordinate_scale
}

set_window_position :: proc(window: ^Window, position: [2]f32) -> bool {
	if !sdl3.SetWindowPosition(window.handle, i32(position[0] * UI_UNIT_POINTS), i32(position[1] * UI_UNIT_POINTS)) {
		return false
	}
	sync_window_scale(window)
	return true
}

set_window_size :: proc(window: ^Window, size: [2]f32) -> bool {
	native_size := native_window_size(size, window.coordinate_scale)
	if !sdl3.SetWindowSize(window.handle, native_size[0], native_size[1]) {
		return false
	}
	sync_window_scale(window)
	sync_viewport(window)
	return true
}

@(private="file")
native_window_size :: proc(size: [2]f32, coordinate_scale: f32) -> [2]i32 {
	scale := coordinate_scale * UI_UNIT_POINTS
	return {i32(math.round(size[0] * scale)), i32(math.round(size[1] * scale))}
}

@(private="file")
window_scales :: proc(handle: ^sdl3.Window) -> (display_scale, coordinate_scale: f32) {
	density := sdl3.GetWindowPixelDensity(handle)
	if density <= 0 {
		density = 1
	}
	display_scale = sdl3.GetWindowDisplayScale(handle)
	if display_scale <= 0 {
		display_scale = density
	}
	return display_scale, display_scale / density
}

@(private="file")
apply_window_minimum_size :: proc(window: ^Window_Resources) -> bool {
	size := native_window_size(window.minimum_size, window.coordinate_scale)
	return sdl3.SetWindowMinimumSize(window.handle, max(i32(1), size[0]), max(i32(1), size[1]))
}

@(private="package")
sync_window_scale :: proc(window: ^Window) {
	display_scale, coordinate_scale := window_scales(window.handle)
	if display_scale != window.display_scale {
		window.display_scale = display_scale
		resize_fonts(window)
	}
	if coordinate_scale != window.coordinate_scale {
		window.coordinate_scale = coordinate_scale
		if !apply_window_minimum_size(&window.native) {
			fmt.eprintln("Cannot update window minimum size:", sdl3.GetError())
		}
		sync_viewport(window)
	}
}

@(private="package")
sync_viewport :: proc(window: ^Window) {
	w, h: i32
	assert(sdl3.GetWindowSize(window.handle, &w, &h))
	scale := window_scale(window)
	get_element(window.ui, window.viewport).pins = Pins{right = f32(w) / scale, bottom = f32(h) / scale}
}
