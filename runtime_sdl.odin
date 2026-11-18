package fluid

import "core:fmt"
import "core:mem"
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
	hovered:                           Element_ID,
	pressed:                           Element_ID,
	focused, captured:                 Element_ID,
	drag:                              Drag,
	cursors:                           SDL_Cursors,
	elements:                          [dynamic]Element, // Stable registry indices; never reordered.
	active:                            [dynamic]Element_ID, // Draw order and processing membership.
	events:                            [dynamic]Element_ID, // Mouse-down presses in the current frame.
	storage:                           virtual.Arena,
	previous:                          u64,
	frame:                             u64,
	sdl_ready, ttf_ready, arena_ready: bool,
}

Config :: struct {
	title:        cstring,
	size:         [2]f32,
	minimum_size: [2]f32,
	flags:        sdl3.WindowFlags,
	background:   Maybe(Color),
}

init :: proc(app: ^UI, config: Config) -> bool {
	app^ = UI{
		running = true,
		hovered = NO_ELEMENT,
		pressed = NO_ELEMENT,
		focused = NO_ELEMENT,
		captured = NO_ELEMENT,
		drag = {element = NO_ELEMENT, started = NO_ELEMENT, released = NO_ELEMENT},
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
	app.events = make([dynamic]Element_ID)
	app.windows = make([dynamic]^Window)
	app.free_windows = make([dynamic]^Window)
	app.free_elements = make([dynamic]int)
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("SDL initialization failed:", sdl3.GetError())
		return false
	}
	app.sdl_ready = true
	app.cursors = create_cursors()
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
		destroy_cursors(app.cursors)
		sdl3.Quit()
	}
	if app.arena_ready {
		virtual.arena_destroy(&app.storage)
	}
	app^ = {}
}

@(private="package")
begin_frame :: proc(app: ^UI) -> f64 {
	app.frame += 1
	// Process window events before starting work on any window's drawable.
	for window in app.windows {
		sync_text_density(window)
	}
	clear(&app.events)
	app.drag.started = NO_ELEMENT
	app.drag.released = NO_ELEMENT
	now := sdl3.GetTicksNS()
	dt := f64(now - app.previous) / 1_000_000_000
	app.previous = now
	return dt
}

// Owns storage, SDL, frame timing, dispatch, drawing, and cleanup. Application
// code creates elements and registers behavior; it never pumps the event loop.
run :: proc(config: Config, owner: ^$Owner, create: proc(owner: ^Owner, ui: ^UI)) {
	assert(owner != nil && create != nil)
	storage: virtual.Arena
	if err := virtual.arena_init_growing(&storage); err != nil {
		fmt.eprintln("Cannot initialize application storage:", err)
		return
	}
	defer virtual.arena_destroy(&storage)
	context.allocator = virtual.arena_allocator(&storage)
	ui: UI
	if !init(&ui, config) {
		return
	}
	defer destroy(&ui)
	create(owner, &ui)
	for ui.running {
		dt := begin_frame(&ui)
		defer mem.free_all(context.temp_allocator)
		requests(&ui)
		if !ui.running {
			break
		}
		advance_window_effects(&ui, dt)
		if !ui.running {
			break
		}
		advance_animations(&ui, dt)
		// Behavior sees hover before its own layout changes.
		refresh_hover(&ui)
		dispatch_behavior(&ui, dt)
		if !ui.running {
			break
		}
		// Behavior gets the first chance to transfer elements out of closing windows.
		for i := 0; i < len(ui.windows); {
			window := ui.windows[i]
			if window.close_requested {
				close_window(window)
				continue
			}
			i += 1
		}
		for window in ui.windows {
			if flags, pending := window.requested_flags.?; pending {
				window.requested_flags = nil
				if !replace_window(window, flags) {
					fmt.eprintln("Cannot replace window:", sdl3.GetError())
					ui.running = false
					break
				}
			}
		}
		if !ui.running {
			break
		}
		// Cursor and drawing share the hit against the final frame layout.
		refresh_hover(&ui)
		update_cursor(&ui)
		for window in ui.windows {
			if .HIDDEN not_in sdl3.GetWindowFlags(window.handle) {
				present_window(window)
			}
		}
	}
}
