package fluid

import "vendor:sdl3"

Drag :: struct {
	element:           int,
	offset:            [2]f32,
	started, released: int, // Current-frame notifications, including a quick down/up.
}

set_pointer_behavior :: proc(app: ^UI, id: Element_ID, behavior: Pointer_Behavior) {
	get_element(app, id).pointer = behavior
}

@(private="package")
accepts_press :: proc(element: ^Element) -> bool {
	return element.kind == .Button || element.press.call != nil
}

@(private="package")
hit_test :: proc(app: ^UI, window: ^Window, x, y: f32) -> int {
	for i := len(app.active) - 1; i >= 0; i -= 1 {
		id := app.active[i]
		element := get_element(app, id)
		if element.owner.window != window || element.pointer == .Pass {
			continue
		}
		if element.pointer == .Auto && !element.draggable && !accepts_press(element) {
			continue
		}
		r := bounds(app, id)
		if x >= r.left && x < r.right && y >= r.top && y < r.bottom {
			return element.pointer == .Block ? -1 : int(id)
		}
	}
	return -1
}

@(private="package")
refresh_hover :: proc(app: ^UI) {
	app.hovered = -1
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
	if mouse[0] >= 0 && mouse[0] < viewport.right && mouse[1] >= 0 && mouse[1] < viewport.bottom {
		app.hovered = hit_test(app, window, mouse[0], mouse[1])
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
			hit := hit_test(app, window, event.button.x / UI_UNIT_POINTS, event.button.y / UI_UNIT_POINTS)
			app.pressed = -1
			if hit < 0 {
				continue
			}
			element := get_element(app, Element_ID(hit))
			if accepts_press(element) {
				app.pressed = hit
				append(&app.events, Element_ID(hit))
			}
			if element.draggable {
				id := Element_ID(hit)
				r := bounds(app, id)

				app.drag.element = hit
				app.drag.started = hit
				app.drag.offset = {event.button.x / UI_UNIT_POINTS - r.left, event.button.y / UI_UNIT_POINTS - r.top}
				bring_to_front(app, id)
				_ = sdl3.CaptureMouse(true)
			}
		case .MOUSE_BUTTON_UP:
			if event.button.button == sdl3.BUTTON_LEFT {
				window := find_window(app, event.button.windowID)
				if window != nil && app.drag.element >= 0 {
					move_drag(app, window_position(window) + [2]f32{event.button.x, event.button.y} / UI_UNIT_POINTS)
				}
				app.pressed = -1
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
			app.pressed = -1
			// Cross-window drags continue until global button state reports release.
		}
	}
	if app.drag.element >= 0 {
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
	mouse := global_mouse - window_position(element_window(app, Element_ID(app.drag.element)))
	r := bounds(app, Element_ID(app.drag.element))
	set_layout(app, Element_ID(app.drag.element), translated(r, mouse - app.drag.offset - [2]f32{r.left, r.top}))
}

@(private="package")
end_drag :: proc(app: ^UI) {
	if app.drag.element < 0 {
		return
	}
	app.drag.released = app.drag.element
	app.drag.element = -1
	_ = sdl3.CaptureMouse(false)
}

dragging :: proc(app: ^UI, id: Element_ID) -> bool {
	return app.drag.element == int(id)
}

drag_started :: proc(app: ^UI, id: Element_ID) -> bool {
	return app.drag.started == int(id)
}

dropped :: proc(app: ^UI, id: Element_ID) -> bool {
	return app.drag.released == int(id)
}

// Preserve the grab point when application code changes the dragged shape.
rebase_drag :: proc(app: ^UI, id: Element_ID) {
	if !dragging(app, id) && !dropped(app, id) {
		return
	}
	r := bounds(app, id)
	app.drag.offset = pointer_position(element_window(app, id)) - [2]f32{r.left, r.top}
}
