package fluid

set_focusable :: proc(ui: ^UI, id: Element_ID, focusable: bool = true) {
	get_element(ui, id).focusable = focusable
}

has_focus :: proc(ui: ^UI, id: Element_ID) -> bool {
	return ui.focused == id
}

@(private="package")
can_focus :: proc(element: ^Element) -> bool {
	return element.pointer == .Auto && (element.pressable || element.focusable)
}

focus :: proc(ui: ^UI, id: Element_ID) {
	if is_active(ui, id) && can_focus(get_element(ui, id)) {
		change_focus(ui, id, true)
	}
}

blur :: proc(ui: ^UI) {
	change_focus(ui, NO_ELEMENT, true)
}

@(private="package")
change_focus :: proc(ui: ^UI, id: Element_ID, commit: bool) {
	previous := ui.focused
	if previous == id {
		return
	}
	ui.focused = NO_ELEMENT
	if previous != NO_ELEMENT {
		send_element_event(ui, previous, Focus_Event{commit = commit})
	}
	if ui.focused != NO_ELEMENT || !is_active(ui, id) {
		return
	}
	ui.focused = id
	send_element_event(ui, id, Focus_Event{focused = true})
}

@(private="package")
focus_next :: proc(ui: ^UI, window: ^Window, backwards: bool) {
	count := len(ui.order)
	if count == 0 {
		return
	}
	index := backwards ? 0 : count - 1
	for id, i in ui.order {
		if id == ui.focused {
			index = i
			break
		}
	}
	step := backwards ? -1 : 1
	for _ in 0..<count {
		index = (index + step + count) % count
		id := ui.order[index]
		element := get_element(ui, id)
		r := element.pins
		if element.window == window && can_focus(element) && width(r) > 0 && height(r) > 0 {
			change_focus(ui, id, true)
			return
		}
	}
	blur(ui)
}

@(private="package")
focused_in :: proc(ui: ^UI, window: ^Window) -> Element_ID {
	id := ui.focused
	return id != NO_ELEMENT && element_window(ui, id) == window ? id : NO_ELEMENT
}

@(private="package")
handle_key :: proc(ui: ^UI, window: ^Window, event: Keyboard_Event) -> bool {
	if event.down {
		#partial switch event.key {
		case .Tab, .Left, .Right, .Up, .Down, .Home, .End, .Page_Up, .Page_Down, .Space, .Enter, .Keypad_Enter:
			ui.keyboard_focus = true
		}
	}
	if event.down && event.key == Key.Tab {
		focus_next(ui, window, event.modifiers & {.Shift} != {})
		return true
	}
	id := focused_in(ui, window)
	if id == NO_ELEMENT {
		return false
	}
	if send_element_event(ui, id, event) {
		return true
	}
	activate := event.key == Key.Space || event.key == Key.Enter || event.key == Key.Keypad_Enter
	if activate && event.down && !event.repeat && is_active(ui, id) && accepts_press(get_element(ui, id)) {
		call_press(ui, id)
	}
	return activate
}
