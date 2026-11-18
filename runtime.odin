package fluid

import "core:fmt"
import "core:mem"
import virtual "core:mem/virtual"

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
	vulkan:                            Vulkan,
	elements:                          [dynamic]Element, // Stable registry indices; never reordered.
	active:                            [dynamic]Element_ID, // Draw order and processing membership.
	events:                            [dynamic]Element_ID, // Mouse-down presses in the current frame.
	storage:                           virtual.Arena,
	previous:                          u64,
	frame:                             u64,
	platform_ready, arena_ready:       bool,
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
	if !platform_init() {
		fmt.eprintln("Cannot initialize native windowing")
		return false
	}
	app.platform_ready = true
	if !vulkan_init(&app.vulkan) {
		return false
	}
	app.window = create_window(app, config)
	if app.window == nil {
		return false
	}
	app.previous = monotonic_ns()
	success = true
	return true
}

destroy :: proc(app: ^UI) {
	for len(app.windows) > 0 {
		close_window(app.windows[len(app.windows) - 1])
	}
	vulkan_shutdown(&app.vulkan)
	if app.platform_ready {
		platform_shutdown()
	}
	if app.arena_ready {
		virtual.arena_destroy(&app.storage)
	}
	app^ = {}
}

@(private="package")
begin_frame :: proc(app: ^UI) -> f64 {
	app.frame += 1
	for window in app.windows {
		sync_window_geometry(window)
	}
	clear(&app.events)
	app.drag.started = NO_ELEMENT
	app.drag.released = NO_ELEMENT
	now := monotonic_ns()
	dt := f64(now - app.previous) / 1_000_000_000
	app.previous = now
	return dt
}

// Owns storage, platform initialization, frame timing, dispatch, drawing, and cleanup. Application
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
	initial := config
	initial.flags += {.Hidden}
	if !init(&ui, initial) {
		return
	}
	defer destroy(&ui)
	create(owner, &ui)
	if ui.running && .Hidden not_in config.flags && !show_window(ui.window) {
		fmt.eprintln("Cannot show primary window")
		return
	}
	frame_deadline, previous_refresh: u64
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
		// Cursor and drawing share the hit against the final frame layout.
		refresh_hover(&ui)
		update_cursor(&ui)
		presented, visible := false, false
		refresh: u64
		for window in ui.windows {
			if platform_window_visible(window) {
				visible = true
				presented = present_window(window) || presented
				if window.renderer.present_mode == .MAILBOX {
					refresh = max(refresh, platform_window_refresh_rate(window))
				}
			}
			if window.renderer.failed {
				window.close_requested = true
				if window == ui.window {
					ui.running = false
				}
			}
		}
		if !ui.running {
			break
		}
		if refresh > 0 {
			// Mailbox replaces queued images without blocking the producer. Pace to
			// the fastest visible mailbox surface instead of drawing unused frames.
			interval := 1_000_000_000 / refresh
			now := monotonic_ns()
			if refresh != previous_refresh || frame_deadline + interval <= now {
				frame_deadline = ui.previous
			}
			frame_deadline += interval
			if frame_deadline > now {
				platform_wait_frame(frame_deadline - now)
			}
		} else if !presented {
			platform_wait_frame(visible ? 1_000_000 : 10_000_000)
		}
		previous_refresh = refresh
	}
}
