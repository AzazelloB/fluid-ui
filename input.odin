package fluid

import "vendor:sdl3"

Drag :: struct {
	element:           int,
	offset:            [2]f32,
	started, released: int, // Current-frame notifications, including a quick down/up.
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
			hit := hit_test(app, window, event.button.x, event.button.y)
			app.hovered = hit
			app.pressed = -1
			if hit >= 0 && get_element(app, Element_ID(hit)).kind == .Button {
				app.pressed = hit
				append(&app.events, Element_ID(hit))
			}
			if hit >= 0 && get_element(app, Element_ID(hit)).draggable {
				id := Element_ID(hit)
				r := bounds(app, id)
				if get_element(app, id).drag_mode == .Independent {
					// An independently movable element leaves its dock's references.
					set_layout(app, id, {at(r.x), at(r.y)}, {at(r.w), at(r.h)})
				}
				app.drag.element = hit
				app.drag.started = hit
				app.drag.offset = {event.button.x - r.x, event.button.y - r.y}
				bring_to_front(app, id)
				_ = sdl3.CaptureMouse(true)
			}
		case .MOUSE_MOTION:
			window := find_window(app, event.motion.windowID)
			if window != nil {
				app.hovered = hit_test(app, window, event.motion.x, event.motion.y)
			}
		case .MOUSE_BUTTON_UP:
			if event.button.button == sdl3.BUTTON_LEFT {
				window := find_window(app, event.button.windowID)
				if window != nil && app.drag.element >= 0 {
					move_drag(app, window_position(window) + [2]f32{event.button.x, event.button.y})
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
				get_element(app, window.viewport)^.size = {at(f32(event.window.data1)), at(f32(event.window.data2))}
			}
		case .WINDOW_MOUSE_LEAVE:
			app.hovered = -1
		case .WINDOW_FOCUS_LOST:
			app.pressed = -1
			app.hovered = -1
			// Cross-window drags continue until global button state reports release.
		}
	}
	if app.drag.element >= 0 {
		mouse: [2]f32
		buttons := sdl3.GetGlobalMouseState(&mouse[0], &mouse[1])
		move_drag(app, mouse)
		if .LEFT not_in buttons {
			end_drag(app)
		}
	}
}

@(private="package")
move_drag :: proc(app: ^UI, global_mouse: [2]f32) {
	element := get_element(app, Element_ID(app.drag.element))
	mouse := global_mouse - window_position(element.owner.window)
	for axis in 0..<2 {
		source, _ := resolve(app, &element.position[axis])
		source.offset += mouse[axis] - app.drag.offset[axis] - read(app, &element.position[axis], space = coordinate_window(element))
	}
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
	app.drag.offset = pointer_position(element_window(app, id)) - [2]f32{r.x, r.y}
}

// A press is reported on mouse-down, independent of where release occurs.
pressed :: proc(app: ^UI, id: Element_ID) -> bool {
	if !is_active(app, id) {
		return false
	}
	for event in app.events {
		if event == id {
			return true
		}
	}
	return false
}
