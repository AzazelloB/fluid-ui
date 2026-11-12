package fluid

import "vendor:sdl3"

requests :: proc(app: ^UI) {
	window := app.window
	move_to :: proc(app: ^UI, mouse: [2]f32) {
		element := &app.elements[app.dragged]
		for axis in 0..<2 {
			source, _ := resolve(app, &element.position[axis])
			source.offset += mouse[axis] - app.drag_offset[axis] - read(app, &element.position[axis])
		}
	}

	sync_text_density(app, window)
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
			if event.button.button == sdl3.BUTTON_LEFT {
				hit := hit_test(app, event.button.x, event.button.y)
				app.hovered = hit
				app.pressed = -1
				if hit >= 0 && app.elements[hit].kind == .Button {
					app.pressed = hit
					append(&app.events, Element_ID(hit))
				}
				app.dragged = hit
				if app.dragged >= 0 && (!is_active(app, Element_ID(app.dragged)) || !app.elements[app.dragged].draggable) {
					app.dragged = -1
				}
				if app.dragged >= 0 {
					r := bounds(app, Element_ID(app.dragged))
					app.drag_offset = {event.button.x - r.x, event.button.y - r.y}
				}
			}
		case .MOUSE_MOTION:
			app.hovered = hit_test(app, event.motion.x, event.motion.y)
			if app.dragged >= 0 {
				move_to(app, {event.motion.x, event.motion.y})
			}
		case .MOUSE_BUTTON_UP:
			if event.button.button == sdl3.BUTTON_LEFT {
				app.pressed = -1
				if app.dragged >= 0 {
					move_to(app, {event.button.x, event.button.y})
				}
				app.dragged = -1
			}
		case .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_DISPLAY_SCALE_CHANGED:
			sync_text_density(app, window)
		case .WINDOW_RESIZED:
			// Window dimensions are source values, referenced just like any element.
			app.elements[app.viewport].size = {at(f32(event.window.data1)), at(f32(event.window.data2))}
		case .WINDOW_MOUSE_LEAVE:
			app.hovered = -1
		case .WINDOW_FOCUS_LOST:
			app.dragged = -1
			app.pressed = -1
			app.hovered = -1
		}
	}

	if app.dragged >= 0 {
		// Read the current OS cursor, not just the last queued motion event.
		mouse: [2]f32
		buttons := sdl3.GetGlobalMouseState(&mouse[0], &mouse[1])
		x, y: i32
		if sdl3.GetWindowPosition(window, &x, &y) {
			move_to(app, {mouse[0] - f32(x), mouse[1] - f32(y)})
		}
		if .LEFT not_in buttons {
			app.dragged = -1
		}
	}
}

// A press is reported on mouse-down, independent of where release occurs.
pressed :: proc(app: ^UI, id: Element_ID) -> bool {
	if !is_active(app, id) { return false }
	for event in app.events { if event == id { return true } }
	return false
}
