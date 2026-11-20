package fluid

import "base:runtime"
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
	removing:                         [dynamic]Element_ID,
	free_elements:                     [dynamic]int,
	hovered:                           Element_ID,
	pressed:                           Element_ID,
	keyboard_focus: bool,
	focused, captured:                 Element_ID,
	drag:                              Drag,
	vulkan:                            Vulkan,
	elements:                          [dynamic]Element, // Stable registry indices; never reordered.
	appearances:                       map[Element_ID]Element_Appearance,
	motions, paused_motions:           [dynamic]Motion,
	order:                             [dynamic]Element_ID, // Visible elements, back to front.
	hidden:                            [dynamic]Element_ID,
	next_draw_order:                   u64,
	updates, frame_updates:            [dynamic]Element_ID,
	storage:                           virtual.Arena,
	live_frame_storage:                ^virtual.Arena,
	event_context:                     ^runtime.Context,
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
	app.order = make([dynamic]Element_ID, 0, 64)
	app.appearances = make(map[Element_ID]Element_Appearance)
	app.motions = make([dynamic]Motion)
	app.paused_motions = make([dynamic]Motion)
	app.hidden = make([dynamic]Element_ID)
	app.updates = make([dynamic]Element_ID)
	app.frame_updates = make([dynamic]Element_ID)
	app.windows = make([dynamic]^Window)
	app.free_windows = make([dynamic]^Window)
	app.removing = make([dynamic]Element_ID)
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

@(private="file")
begin_frame :: proc(app: ^UI) {
	app.frame += 1
	for window in app.windows {
		sync_window_geometry(window)
	}
	app.drag.started = NO_ELEMENT
	app.drag.released = NO_ELEMENT
}

@(private="package")
poll_frame_event :: proc(app: ^UI, poll_native: bool, deadline: u64) -> (Platform_Event, bool) {
	if !poll_native || app.live_frame_storage == nil {
		return platform_poll_event(app, poll_native, deadline)
	}
	event_context := context
	app.event_context = &event_context
	defer app.event_context = nil
	return platform_poll_event(app, true, deadline)
}

@(private="package")
live_resize_frame :: proc(window: ^Window, interval: u64 = 0) {
	app := window.ui
	event_context := app.event_context
	if event_context == nil || !app.running || !window.open || monotonic_ns() - app.previous < interval {
		return
	}
	// The native pump is suspended. Finish its pending frame using only queued events.
	app.event_context = nil
	defer app.event_context = event_context
	context = event_context^
	// Native callbacks can still enqueue text in the outer frame's temporary storage.
	context.temp_allocator = virtual.arena_allocator(app.live_frame_storage)
	defer virtual.arena_free_all(app.live_frame_storage)
	dispatch_requests(app, false)
	finish_frame(app)
	if app.running {
		begin_frame(app)
	}
}

@(private="file")
finish_frame :: proc(app: ^UI) -> (presented, visible: bool, refresh: u64) {
	if !app.running {
		return
	}
	now := monotonic_ns()
	dt := f64(now - app.previous) / 1_000_000_000
	app.previous = now
	advance_window_effects(app, dt)
	if !app.running {
		return
	}
	advance_animations(app, dt)
	// Behavior sees hover before its own layout changes.
	refresh_hover(app)
	dispatch_updates(app, dt)
	if !app.running {
		return
	}
	// Behavior gets the first chance to transfer elements out of closing windows.
	for i := 0; i < len(app.windows); {
		window := app.windows[i]
		if window.close_requested {
			close_window(window)
			continue
		}
		i += 1
	}
	// Cursor and drawing share the hit against the final frame layout.
	refresh_hover(app)
	update_cursor(app)
	for window in app.windows {
		if platform_window_visible(window) {
			visible = true
			presented = present_window(window) || presented
			if ODIN_OS == .Darwin || window.renderer.present_mode == .MAILBOX {
				refresh = max(refresh, platform_window_refresh_rate(window))
			}
		}
		if window.renderer.failed {
			window.close_requested = true
			if window == app.window {
				app.running = false
			}
		}
	}
	return
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
	live_frame_storage: virtual.Arena
	if err := virtual.arena_init_growing(&live_frame_storage); err != nil {
		fmt.eprintln("Cannot initialize live resize frame storage:", err)
		return
	}
	defer virtual.arena_destroy(&live_frame_storage)
	ui.live_frame_storage = &live_frame_storage
	create(owner, &ui)
	if ui.running && .Hidden not_in config.flags && !show_window(ui.window) {
		fmt.eprintln("Cannot show primary window")
		return
	}
	frame_deadline, previous_refresh: u64
	for ui.running {
		begin_frame(&ui)
		defer mem.free_all(context.temp_allocator)
		dispatch_requests(&ui, true, frame_deadline)
		presented, visible, refresh := finish_frame(&ui)
		if !ui.running {
			break
		}
		if refresh > 0 {
			// Mailbox can replace queued images. On macOS, FIFO can stall inside
			// Metal drawable acquisition on the UI thread. Pace the producer.
			interval := 1_000_000_000 / refresh
			now := monotonic_ns()
			if refresh != previous_refresh || frame_deadline + interval <= now {
				frame_deadline = ui.previous
			}
			frame_deadline += interval
		} else {
			frame_deadline = 0
			if !presented {
				frame_deadline = monotonic_ns() + (visible ? 1_000_000 : 10_000_000)
			}
		}
		when ODIN_OS == .Windows {
			now := monotonic_ns()
			if frame_deadline > now {
				platform_wait_frame(frame_deadline - now)
			}
		}
		previous_refresh = refresh
	}
}
