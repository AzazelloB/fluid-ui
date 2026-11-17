package fluid

import "vendor:sdl3"

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
	return element.kind == .Button || element.press.call != nil
}

@(private="package")
hit_test :: proc(app: ^UI, window: ^Window, point: [2]f32) -> Element_ID {
	for i := len(app.active) - 1; i >= 0; i -= 1 {
		id := app.active[i]
		element := get_element(app, id)
		if coordinate_window(element) != window || element.pointer == .Pass {
			continue
		}
		if element.pointer == .Auto && !element.draggable && !accepts_press(element) {
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
	focus := sdl3.GetMouseFocus()
	if focus == nil {
		return
	}
	window := find_window(app, sdl3.GetWindowID(focus))
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
press_at :: proc(app: ^UI, window: ^Window, point: [2]f32) {
	id := hit_test(app, window, point)
	app.pressed = NO_ELEMENT
	if id == NO_ELEMENT {
		return
	}
	element := get_element(app, id)
	if accepts_press(element) {
		app.pressed = id
		append(&app.events, id)
	}
	if element.draggable {
		r := element_bounds(element)
		app.drag.element = id
		app.drag.started = id
		app.drag.offset = point - [2]f32{r.left, r.top}
		bring_to_front(app, id)
		_ = sdl3.CaptureMouse(true)
	}
}

requests :: proc(app: ^UI) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			app.running = false
		case .KEY_DOWN:
			if event.key.key == sdl3.K_ESCAPE {
				app.running = false
			}
		case .MOUSE_BUTTON_DOWN:
			window := find_window(app, event.button.windowID)
			if window == nil || event.button.button != sdl3.BUTTON_LEFT {
				continue
			}
			press_at(app, window, [2]f32{event.button.x, event.button.y} / UI_UNIT_POINTS)
		case .MOUSE_BUTTON_UP:
			if event.button.button == sdl3.BUTTON_LEFT {
				window := find_window(app, event.button.windowID)
				if window != nil && app.drag.element != NO_ELEMENT {
					move_drag(app, window_position(window) + [2]f32{event.button.x, event.button.y} / UI_UNIT_POINTS)
				}
				app.pressed = NO_ELEMENT
				end_drag(app)
			}
		case .WINDOW_CLOSE_REQUESTED:
			window := find_window(app, event.window.windowID)
			if window != nil {
				window.close_requested = true
				if window == app.window {
					app.running = false
				}
			}
		case .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_DISPLAY_SCALE_CHANGED:
			window := find_window(app, event.window.windowID)
			if window != nil {
				sync_text_density(window)
			}
		case .WINDOW_RESIZED:
			window := find_window(app, event.window.windowID)
			if window != nil {
				sync_viewport(window)
			}
		case .WINDOW_FOCUS_LOST:
			app.pressed = NO_ELEMENT
			// Cross-window drags continue until global button state reports release.
		}
	}
	if app.drag.element != NO_ELEMENT {
		mouse: [2]f32
		buttons := sdl3.GetGlobalMouseState(&mouse[0], &mouse[1])
		move_drag(app, mouse / UI_UNIT_POINTS)
		if .LEFT not_in buttons {
			end_drag(app)
		}
	}
}

@(private="package")
move_drag :: proc(app: ^UI, global_mouse: [2]f32) {
	id := app.drag.element
	mouse := global_mouse - window_position(element_window(app, id))
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
	_ = sdl3.CaptureMouse(false)
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
