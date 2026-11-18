package fluid

@(private="package")
NO_ELEMENT :: Element_ID(-1)

Drag :: struct {
	element:           Element_ID,
	offset:            [2]f32,
	started, released: Element_ID, // Current-frame notifications, including a quick down/up.
}

set_pointer_behavior :: proc(app: ^UI, id: Element_ID, behavior: Pointer_Behavior) {
	get_element(app, id).pointer = behavior
}

@(private="package")
accepts_press :: proc(element: ^Element) -> bool {
	return element.pressable || element.press.call != nil
}

@(private="package")
hit_test :: proc(app: ^UI, window: ^Window, point: [2]f32) -> Element_ID {
	for i := len(app.active) - 1; i >= 0; i -= 1 {
		id := app.active[i]
		element := get_element(app, id)
		if coordinate_window(element) != window || element.pointer == .Pass {
			continue
		}
		if element.pointer == .Auto && (!window.custom_title_bar || element.window_hit == .Client) &&
		   !element.draggable && !accepts_press(element) && !element.focusable && element.behavior.input == nil {
			continue
		}
		if contains(element_bounds(element), point) {
			return element.pointer == .Block ? NO_ELEMENT : id
		}
	}
	return NO_ELEMENT
}

@(private="package")
refresh_hover :: proc(app: ^UI) {
	app.hovered = NO_ELEMENT
	window := platform_mouse_window(app)
	if window == nil {
		return
	}
	mouse := pointer_position(window)
	viewport := bounds(app, window.viewport)
	if contains(viewport, mouse) {
		app.hovered = hit_test(app, window, mouse)
	}
}

@(private="package")
press_at :: proc(app: ^UI, window: ^Window, event: Platform_Event) {
	point := event.position / window_scale(window)
	id := hit_test(app, window, point)
	focus_id := NO_ELEMENT
	if id != NO_ELEMENT && can_focus(get_element(app, id)) {
		focus_id = id
	}
	change_focus(app, focus_id, true)
	id = hit_test(app, window, point)
	app.pressed = NO_ELEMENT
	if id == NO_ELEMENT {
		return
	}
	element := get_element(app, id)
	if accepts_press(element) || element.behavior.input != nil {
		app.pressed = id
	}
	if send_element_event(app, id, Pointer_Event{
		kind = .Down, point = point, timestamp = event.timestamp, clicks = event.clicks,
		modifiers = event.modifiers, inside = true,
	}) || !is_active(app, id) {
		return
	}
	element = get_element(app, id)
	if accepts_press(element) {
		queue_press(app, id)
	}
	if element.draggable {
		r := element_bounds(element)
		app.drag.element = id
		app.drag.started = id
		app.drag.offset = point - [2]f32{r.left, r.top}
		bring_to_front(app, id)
		platform_capture_mouse(window)
	}
}

requests :: proc(app: ^UI) {
	dispatch_requests(app, true)
}

@(private="package")
dispatch_requests :: proc(app: ^UI, poll_native: bool, deadline: u64 = 0) {
	for app.running {
		event, ok := poll_frame_event(app, poll_native, deadline)
		if !ok || !app.running {
			break
		}
		window := event.window
		if window == nil && event.kind != .Quit {
			continue
		}
		switch event.kind {
		case .Quit:
			app.running = false
		case .Key:
			if !handle_key(app, window, event.key) && event.key.down && event.key.key == .Escape {
				app.running = false
			}
		case .Text_Edit:
			if id := focused_in(app, window); id != NO_ELEMENT {
				send_element_event(app, id, event.edit)
			}
		case .Text_Input:
			if id := focused_in(app, window); id != NO_ELEMENT {
				send_element_event(app, id, event.text)
			}
		case .Wheel:
			point := event.position / window_scale(window)
			if id := hit_test(app, window, point); id != NO_ELEMENT {
				if !event.wheel_direct || !send_element_event(app, id, Precise_Scroll_Event{event.wheel, event.wheel_distance}) {
					send_element_event(app, id, Wheel_Event(event.wheel))
				}
			}
		case .Mouse_Move:
			deliver_pointer(app, window, event.position / window_scale(window), event.timestamp, false)
		case .Mouse_Leave:
			if app.captured == NO_ELEMENT && app.pressed != NO_ELEMENT && element_window(app, app.pressed) == window {
				send_element_event(app, app.pressed, Pointer_Event{kind = .Cancel, timestamp = event.timestamp})
			}
		case .Mouse_Down:
			press_at(app, window, event)
		case .Mouse_Up:
			point := event.position / window_scale(window)
			deliver_pointer(app, window, point, event.timestamp, true)
			if app.drag.element != NO_ELEMENT {
				move_drag(app, desktop_point(window, point))
			}
			app.pressed = NO_ELEMENT
			end_drag(app)
		case .Close:
			window.close_requested = true
			if window == app.window {
				app.running = false
			}
		case .Resize:
			sync_window_geometry(window)
		case .Focus_Lost:
			if id := pointer_target(app); id != NO_ELEMENT && element_window(app, id) == window {
				cancel_pointer(app, id)
				app.pressed = NO_ELEMENT
			}
			if focused_in(app, window) != NO_ELEMENT {
				blur(app)
			}
			// Cross-window drags continue until global button state reports release.
		}
	}
	if !app.running {
		return
	}
	if app.focused != NO_ELEMENT {
		send_element_event(app, app.focused, Focused_Frame(monotonic_ns()))
	}
	if app.drag.element != NO_ELEMENT {
		mouse, left_down := platform_mouse_state()
		move_drag(app, mouse / UI_UNIT_POINTS)
		if !left_down {
			end_drag(app)
		}
	}
}

@(private="package")
move_drag :: proc(app: ^UI, global_mouse: [2]f32) {
	id := app.drag.element
	mouse := window_point(element_window(app, id), global_mouse)
	r := bounds(app, id)
	set_layout(app, id, translated(r, mouse - app.drag.offset - [2]f32{r.left, r.top}))
}

@(private="package")
end_drag :: proc(app: ^UI) {
	if app.drag.element == NO_ELEMENT {
		return
	}
	app.drag.released = app.drag.element
	app.drag.element = NO_ELEMENT
	platform_capture_mouse(nil)
}

dragging :: proc(app: ^UI, id: Element_ID) -> bool {
	return app.drag.element == id
}

drag_started :: proc(app: ^UI, id: Element_ID) -> bool {
	return app.drag.started == id
}

dropped :: proc(app: ^UI, id: Element_ID) -> bool {
	return app.drag.released == id
}

// Preserve the grab point when application code changes the dragged shape.
rebase_drag :: proc(app: ^UI, id: Element_ID) {
	if !dragging(app, id) && !dropped(app, id) {
		return
	}
	r := bounds(app, id)
	app.drag.offset = pointer_position(element_window(app, id)) - [2]f32{r.left, r.top}
}
