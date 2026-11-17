package fluid

import "core:fmt"
import virtual "core:mem/virtual"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Window and Scene pointers expire on close. Transfer elements before closing
// their window to preserve their IDs; remaining IDs are invalidated on close.
Window :: struct {
	ui:              ^UI,
	handle:          ^sdl3.Window,
	renderer:        ^sdl3.Renderer,
	fonts:           [Text_Size]^ttf.Font,
	text_engine:     ^ttf.TextEngine,
	pixel_density:   f32,
	font_unit_size:  f32,
	viewport:        Element_ID,
	scenes:          [dynamic]^Scene,
	close_requested: bool,
	effect:          Window_Effect,
	pending_flags:   bool,
	requested_flags: sdl3.WindowFlags,
	storage:         virtual.Arena,
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
	if !create_window_resources(window, config) {
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
create_window_resources :: proc(window: ^Window, config: Config) -> bool {
	success := false
	defer {
		if !success {
			fmt.eprintln("Cannot create window:", sdl3.GetError())
			release_window_resources(window)
		}
	}
	window.handle = sdl3.CreateWindow(config.title, i32(config.size[0] * window.ui.base_font_size), i32(config.size[1] * window.ui.base_font_size), config.flags | {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window.handle == nil {
		return false
	}
	if !sdl3.SetWindowMinimumSize(window.handle, max(i32(1), i32(config.minimum_size[0] * window.ui.base_font_size)), max(i32(1), i32(config.minimum_size[1] * window.ui.base_font_size))) {
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
	window.font_unit_size = window.ui.base_font_size
	for size in Text_Size {
		font := ttf.OpenFont("/System/Library/Fonts/SFNS.ttf", text_size_units(size) * window.ui.base_font_size * window.pixel_density)
		if font == nil {
			font = ttf.OpenFont("/System/Library/Fonts/Supplemental/Arial.ttf", text_size_units(size) * window.ui.base_font_size * window.pixel_density)
		}
		if font == nil {
			return false
		}
		window.fonts[size] = font
	}
	window.text_engine = ttf.CreateRendererTextEngine(window.renderer)
	if window.text_engine == nil {
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
	config.size = {f32(size[0]) / window.ui.base_font_size, f32(size[1]) / window.ui.base_font_size}
	config.minimum_size = {f32(minimum[0]) / window.ui.base_font_size, f32(minimum[1]) / window.ui.base_font_size}

	replacement := Window{
		ui = window.ui,
		viewport = window.viewport,
		scenes = window.scenes,
		close_requested = window.close_requested,
		storage = window.storage,
		effect = window.effect,
	}
	if !create_window_resources(&replacement, config) {
		return false
	}
	if !sdl3.SetWindowPosition(replacement.handle, position[0], position[1]) {
		release_window_resources(&replacement)
		return false
	}
	sync_text_density(&replacement)

	app := window.ui
	release_window_text(window)
	previous := window^
	window^ = replacement
	if .HIDDEN in sdl3.GetWindowFlags(previous.handle) {
		present_window(window)
	} else if !show_window(window) {
		release_window_text(window)
		release_window_resources(&replacement)
		window^ = previous
		return false
	}
	// Present again after showing: some backends skip hidden-window presentation.
	if .HIDDEN not_in sdl3.GetWindowFlags(window.handle) {
		present_window(window)
	}
	if app.drag.element >= 0 && get_element(app, Element_ID(app.drag.element)).owner.window == window {
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
	window.pending_flags = false
	remove(app, window.viewport)
	virtual.arena_destroy(&window.storage)
	release_window_resources(window)
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

@(private="package")
release_window_text :: proc(window: ^Window) {
	for scene in window.scenes {
		for id in scene.members {
			release_text(get_element(window.ui, id))
		}
	}
}

window_position :: proc(window: ^Window) -> [2]f32 {
	x, y: i32
	assert(sdl3.GetWindowPosition(window.handle, &x, &y))
	return {f32(x) / window.ui.base_font_size, f32(y) / window.ui.base_font_size}
}

pointer_position :: proc(window: ^Window) -> [2]f32 {
	mouse: [2]f32
	_ = sdl3.GetGlobalMouseState(&mouse[0], &mouse[1])
	return mouse / window.ui.base_font_size - window_position(window)
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
release_window_resources :: proc(window: ^Window) {
	if window.text_engine != nil {
		ttf.DestroyRendererTextEngine(window.text_engine)
	}
	for font in window.fonts {
		if font != nil {
			ttf.CloseFont(font)
		}
	}
	if window.renderer != nil {
		sdl3.DestroyRenderer(window.renderer)
	}
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
	}
	window.text_engine = nil
	window.fonts = {}
	window.renderer = nil
	window.handle = nil
}

// Creation-only flag changes are performed by Fluid before the next draw.
set_window_flags :: proc(window: ^Window, flags: sdl3.WindowFlags) {
	assert(window.handle != nil)
	window.requested_flags = flags
	window.pending_flags = true
}

// Native placement and size requests share the same UI units as layout/input.
set_window_position :: proc(window: ^Window, position: [2]f32) -> bool {
	return sdl3.SetWindowPosition(window.handle, i32(position[0] * window.ui.base_font_size), i32(position[1] * window.ui.base_font_size))
}

set_window_size :: proc(window: ^Window, size: [2]f32) -> bool {
	if !sdl3.SetWindowSize(window.handle, i32(size[0] * window.ui.base_font_size), i32(size[1] * window.ui.base_font_size)) { return false }
	sync_viewport(window)
	return true
}

// The physical window stays put. More or fewer UI units fit inside it, and all
// reactive layouts/content measurements immediately use the new base font size.
set_base_font_size :: proc(ui: ^UI, logical_points: f32) {
	assert(logical_points > 0)
	ui.base_font_size = logical_points
	for window in ui.windows {
		sync_text_density(window)
		sync_viewport(window)
	}
}

@(private="package")
sync_viewport :: proc(window: ^Window) {
	w, h: i32
	assert(sdl3.GetWindowSize(window.handle, &w, &h))
	get_element(window.ui, window.viewport).pins = Pins{right = f32(w) / window.ui.base_font_size, bottom = f32(h) / window.ui.base_font_size}
}
