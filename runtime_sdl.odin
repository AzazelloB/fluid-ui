package fluid

import "core:fmt"
import virtual "core:mem/virtual"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Keep the initialized UI at a stable address until destroy(ui).
// The UI owns all registry storage and native resources for this session.
UI :: struct {
	running:                           bool,
	window:                            ^Window, // Primary application window.
	windows:                           [dynamic]^Window,
	free_windows:                      [dynamic]^Window,
	free_elements:                     [dynamic]int,
	hovered:                           int,
	pressed:                           int,
	drag:                              Drag,
	elements:                          [dynamic]Element, // Stable registry indices; never reordered.
	active:                            [dynamic]Element_ID, // Draw order and processing membership.
	groups:                            [dynamic][dynamic]Element_ID,
	events:                            [dynamic]Element_ID, // Mouse-down presses in the current frame.
	storage:                           virtual.Arena,
	previous:                          u64,
	sdl_ready, ttf_ready, arena_ready: bool,
}

Config :: struct {
	title:        cstring,
	size:         [2]i32,
	minimum_size: [2]i32,
	flags:        sdl3.WindowFlags,
}

init :: proc(app: ^UI, config: Config) -> bool {
	app^ = UI{
		running = true,
		hovered = -1,
		pressed = -1,
		drag = {element = -1, started = -1, released = -1},
	}
	success := false
	defer {
		if !success {
			destroy(app)
		}
	}
	if err := virtual.arena_init_growing(&app.storage); err != nil {
		fmt.eprintln("Cannot initialize UI storage:", err)
		return false
	}
	app.arena_ready = true
	context.allocator = virtual.arena_allocator(&app.storage)
	app.elements = make([dynamic]Element, 0, 64)
	app.active = make([dynamic]Element_ID, 0, 64)
	app.groups = make([dynamic][dynamic]Element_ID)
	app.events = make([dynamic]Element_ID)
	app.windows = make([dynamic]^Window)
	app.free_windows = make([dynamic]^Window)
	app.free_elements = make([dynamic]int)
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("SDL initialization failed:", sdl3.GetError())
		return false
	}
	app.sdl_ready = true
	if !ttf.Init() {
		fmt.eprintln(sdl3.GetError())
		return false
	}
	app.ttf_ready = true
	app.window = create_window(app, config)
	if app.window == nil {
		return false
	}
	app.previous = sdl3.GetTicksNS()
	success = true
	return true
}

destroy :: proc(app: ^UI) {
	for len(app.windows) > 0 {
		close_window(app.windows[len(app.windows) - 1])
	}
	if app.ttf_ready {
		ttf.Quit()
	}
	if app.sdl_ready {
		sdl3.Quit()
	}
	if app.arena_ready {
		virtual.arena_destroy(&app.storage)
	}
	app^ = {}
}

begin_frame :: proc(app: ^UI) -> f64 {
	// Process window events before starting work on any window's drawable.
	for window in app.windows {
		sync_text_density(window)
	}
	clear(&app.events)
	app.drag.started = -1
	app.drag.released = -1
	now := sdl3.GetTicksNS()
	dt := f64(now - app.previous) / 1_000_000_000
	app.previous = now
	return dt
}
