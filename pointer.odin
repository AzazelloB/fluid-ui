package fluid

import "vendor:sdl3"

// Capture sends subsequent motion and release to this element even outside
// its bounds. On release or cancellation the engine drops capture first.
capture_pointer :: proc(ui: ^UI, id: Element_ID) {
	if is_active(ui, id) && ui.pressed == id {
		ui.captured = id
		_ = sdl3.CaptureMouse(true)
	}
}

pointer_captured :: proc(ui: ^UI, id: Element_ID) -> bool {
	return ui.captured == id
}

@(private="package")
pointer_target :: proc(ui: ^UI) -> Element_ID {
	return ui.captured != NO_ELEMENT ? ui.captured : ui.pressed
}

@(private="file")
release_capture :: proc(ui: ^UI, id: Element_ID) {
	if ui.captured == id {
		ui.captured = NO_ELEMENT
		_ = sdl3.CaptureMouse(false)
	}
}

@(private="package")
cancel_pointer :: proc(ui: ^UI, id: Element_ID) {
	release_capture(ui, id)
	send_element_event(ui, id, Pointer_Event{kind = .Cancel, timestamp = sdl3.GetTicksNS()})
}

@(private="package")
detach_input :: proc(ui: ^UI, id: Element_ID) {
	if ui.focused == id {
		change_focus(ui, NO_ELEMENT, false)
	}
	if pointer_target(ui) == id {
		if ui.pressed == id {
			ui.pressed = NO_ELEMENT
		}
		cancel_pointer(ui, id)
	}
}

@(private="package")
deliver_pointer :: proc(ui: ^UI, window: ^Window, point: [2]f32, timestamp: u64, up: bool) {
	id := pointer_target(ui)
	if id == NO_ELEMENT || get_element(ui, id).behavior.input == nil {
		return
	}
	owner := element_window(ui, id)
	event := Pointer_Event{
		kind = .Move, point = point, timestamp = timestamp,
		inside = owner == window && hit_test(ui, window, point) == id,
	}
	if owner != window {
		event.point += window_position(window) - window_position(owner)
	}
	if !up || pointer_captured(ui, id) {
		send_element_event(ui, id, event)
	}
	if up && is_active(ui, id) && pointer_target(ui) == id {
		release_capture(ui, id)
		event.kind = .Up
		send_element_event(ui, id, event)
	}
}
