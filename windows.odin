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
	font:            ^ttf.Font,
	text_engine:     ^ttf.TextEngine,
	pixel_density:   f32,
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
	w, h: i32
	assert(sdl3.GetWindowSize(window.handle, &w, &h))
	// A reference source, not a drawable or a parent.
	window.viewport = register_element(app, Element{space = window, size = {at(f32(w)), at(f32(h))}})
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
	window.handle = sdl3.CreateWindow(config.title, config.size[0], config.size[1], config.flags | {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window.handle == nil {
		return false
	}
	if !sdl3.SetWindowMinimumSize(window.handle, max(i32(1), config.minimum_size[0]), max(i32(1), config.minimum_size[1])) {
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
	window.font = ttf.OpenFont("/System/Library/Fonts/SFNS.ttf", FONT_SIZE * window.pixel_density)
	if window.font == nil {
		window.font = ttf.OpenFont("/System/Library/Fonts/Supplemental/Arial.ttf", FONT_SIZE * window.pixel_density)
	}
	if window.font == nil {
		return false
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
	position: [2]i32
	if !sdl3.GetWindowSize(window.handle, &config.size[0], &config.size[1]) ||
		!sdl3.GetWindowMinimumSize(window.handle, &config.minimum_size[0], &config.minimum_size[1]) ||
		!sdl3.GetWindowPosition(window.handle, &position[0], &position[1]) {
		return false
	}
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
	// Cached text belongs to the old renderer, including text in inactive scenes.
	for scene in window.scenes {
		for id in scene.members {
			release_text(get_element(app, id))
		}
	}
	previous := window^
	window^ = replacement
	present_window(window)
	if .HIDDEN not_in sdl3.GetWindowFlags(previous.handle) && !show_window(window) {
		for scene in window.scenes {
			for id in scene.members {
				release_text(get_element(app, id))
			}
		}
		window^ = previous
		release_window_resources(&replacement)
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
		deactivate(scene)
		for len(scene.members) > 0 {
			remove(app, scene.members[len(scene.members) - 1])
		}
	}
	window.effect = {}
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

window_position :: proc(window: ^Window) -> [2]f32 {
	x, y: i32
	assert(sdl3.GetWindowPosition(window.handle, &x, &y))
	return {f32(x), f32(y)}
}

pointer_position :: proc(window: ^Window) -> [2]f32 {
	mouse: [2]f32
	_ = sdl3.GetGlobalMouseState(&mouse[0], &mouse[1])
	return mouse - window_position(window)
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
	if window.font != nil {
		ttf.CloseFont(window.font)
	}
	if window.renderer != nil {
		sdl3.DestroyRenderer(window.renderer)
	}
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
	}
	window.text_engine = nil
	window.font = nil
	window.renderer = nil
	window.handle = nil
}

// Creation-only flag changes are performed by Fluid before the next draw.
set_window_flags :: proc(window: ^Window, flags: sdl3.WindowFlags) {
	assert(window.handle != nil)
	window.requested_flags = flags
	window.pending_flags = true
}
