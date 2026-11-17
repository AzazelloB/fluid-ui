package fluid

import "core:fmt"
import virtual "core:mem/virtual"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Window and Scene pointers expire on close. Transfer elements before closing
// their window to preserve their IDs; remaining IDs are invalidated on close.
Window :: struct {
	ui:              ^UI,
	using native:    Window_Resources,
	viewport:        Element_ID,
	scenes:          [dynamic]^Scene,
	close_requested: bool,
	effect:          Window_Effect,
	requested_flags: Maybe(sdl3.WindowFlags),
	storage:         virtual.Arena,
}

// These resources can be replaced while the logical window stays in place.
@(private="package")
Window_Resources :: struct {
	handle:        ^sdl3.Window,
	renderer:      ^sdl3.Renderer,
	fonts:         [Text_Weight][Text_Size]^ttf.Font,
	text_engine:   ^ttf.TextEngine,
	pixel_density: f32,
}

create_window :: proc(app: ^UI, config: Config) -> ^Window {
	context.allocator = virtual.arena_allocator(&app.storage)
	window: ^Window
	if len(app.free_windows) > 0 {
		window = pop(&app.free_windows)
	} else {
		window = new(Window)
	}
	window^ = Window{ui = app}
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
	sync_viewport(window)
	append(&app.windows, window)
	return window
}

@(private="package")
create_window_resources :: proc(window: ^Window_Resources, config: Config) -> bool {
	success := false
	defer {
		if !success {
			fmt.eprintln("Cannot create window:", sdl3.GetError())
			release_window_resources(window)
		}
	}
	window.handle = sdl3.CreateWindow(config.title, i32(config.size[0] * UI_UNIT_POINTS), i32(config.size[1] * UI_UNIT_POINTS), config.flags | {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window.handle == nil {
		return false
	}
	if !sdl3.SetWindowMinimumSize(window.handle, max(i32(1), i32(config.minimum_size[0] * UI_UNIT_POINTS)), max(i32(1), i32(config.minimum_size[1] * UI_UNIT_POINTS))) {
		return false
	}
	window.renderer = sdl3.CreateRenderer(window.handle, nil)
	if window.renderer == nil {
		return false
	}
	// Each renderer presents to its own drawable and must synchronize it.
	if !sdl3.SetRenderVSync(window.renderer, 1) {
		return false
	}
	window.pixel_density = max(f32(1), sdl3.GetWindowPixelDensity(window.handle))
	if !create_text_resources(window) {
		return false
	}
	success = true
	return true
}

// Change creation-only SDL flags without changing the Fluid window, scenes,
// or viewport ID. Call between frames; renderer-specific text is rebuilt.
@(private="package")
replace_window :: proc(window: ^Window, flags: sdl3.WindowFlags) -> bool {
	config := Config{title = sdl3.GetWindowTitle(window.handle), flags = flags | {.HIDDEN}}
	position, size, minimum: [2]i32
	if !sdl3.GetWindowSize(window.handle, &size[0], &size[1]) ||
		!sdl3.GetWindowMinimumSize(window.handle, &minimum[0], &minimum[1]) ||
		!sdl3.GetWindowPosition(window.handle, &position[0], &position[1]) {
		return false
	}
	config.size = {f32(size[0]) / UI_UNIT_POINTS, f32(size[1]) / UI_UNIT_POINTS}
	config.minimum_size = {f32(minimum[0]) / UI_UNIT_POINTS, f32(minimum[1]) / UI_UNIT_POINTS}

	replacement: Window_Resources
	if !create_window_resources(&replacement, config) {
		return false
	}
	if !sdl3.SetWindowPosition(replacement.handle, position[0], position[1]) {
		release_window_resources(&replacement)
		return false
	}
	release_window_text(window)
	previous := window.native
	window.native = replacement
	sync_text_density(window)
	if .HIDDEN in sdl3.GetWindowFlags(previous.handle) {
		present_window(window)
	} else if !show_window(window) {
		release_window_text(window)
		release_window_resources(&window.native)
		window.native = previous
		return false
	}
	// Present again after showing: some backends skip hidden-window presentation.
	if .HIDDEN not_in sdl3.GetWindowFlags(window.handle) {
		present_window(window)
	}
	app := window.ui
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
	return mouse / UI_UNIT_POINTS - window_position(window)
}

show_window :: proc(window: ^Window) -> bool {
	// Prime hidden content before making the window visible.
	present_window(window)
	return sdl3.ShowWindow(window.handle)
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

// Renderer coordinates are physical pixels, including on high-density displays.
pixel_scale :: proc(window: ^Window) -> f32 {
	return window.pixel_density * UI_UNIT_POINTS
}

// Native placement and size requests share the same UI units as layout/input.
set_window_position :: proc(window: ^Window, position: [2]f32) -> bool {
	return sdl3.SetWindowPosition(window.handle, i32(position[0] * UI_UNIT_POINTS), i32(position[1] * UI_UNIT_POINTS))
}

set_window_size :: proc(window: ^Window, size: [2]f32) -> bool {
	if !sdl3.SetWindowSize(window.handle, i32(size[0] * UI_UNIT_POINTS), i32(size[1] * UI_UNIT_POINTS)) { return false }
	sync_viewport(window)
	return true
}

@(private="package")
sync_viewport :: proc(window: ^Window) {
	w, h: i32
	assert(sdl3.GetWindowSize(window.handle, &w, &h))
	get_element(window.ui, window.viewport).pins = Pins{right = f32(w) / UI_UNIT_POINTS, bottom = f32(h) / UI_UNIT_POINTS}
}
