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

@(private="file")
move_directional_focus :: proc(ui: ^UI, window: ^Window, key: Key) -> bool {
	axis: int
	sign: f32 = 1
	#partial switch key {
	case .Left: sign = -1
	case .Right:
	case .Up: axis, sign = 1, -1
	case .Down: axis = 1
	case: return false
	}
	across := 1 - axis
	current := focused_in(ui, window)
	viewport := bounds(ui, window.viewport)
	origin := Pins{}
	if current != NO_ELEMENT {
		origin = intersect_pins(bounds(ui, current), viewport)
	}
	origin_lo := [2]f32{origin.left, origin.top}
	origin_hi := [2]f32{origin.right, origin.bottom}
	center := (origin_lo + origin_hi) / 2
	best := NO_ELEMENT
	best_score: f32
	for id in ui.order {
		element := get_element(ui, id)
		if id == current || element.window != window || !can_focus(element) {
			continue
		}
		r := intersect_pins(element.pins, viewport)
		if width(r) == 0 || height(r) == 0 {
			continue
		}
		lo := [2]f32{r.left, r.top}
		hi := [2]f32{r.right, r.bottom}
		delta := (lo + hi) / 2 - center
		forward, lateral := delta[axis] * sign, abs(delta[across])
		if current != NO_ELEMENT && forward <= 0 {
			continue
		}
		score := lo.y * width(viewport) + lo.x
		if current != NO_ELEMENT {
			gap := max(0, lo[across] - origin_hi[across], origin_lo[across] - hi[across])
			score = forward + lateral * 0.25 + gap * 2
		}
		if best == NO_ELEMENT || score < best_score {
			best, best_score = id, score
		}
	}
	if best != NO_ELEMENT {
		focus(ui, best)
	}
	return true
}

@(private="file")
intersect_pins :: proc(a, b: Pins) -> Pins {
	return {max(a.left, b.left), max(a.top, b.top), min(a.right, b.right), min(a.bottom, b.bottom)}
}

@(private="package")
handle_key :: proc(ui: ^UI, window: ^Window, event: Keyboard_Event) -> bool {
	if event.down {
		#partial switch event.key {
		case .Tab, .Left, .Right, .Up, .Down, .Home, .End, .Page_Up, .Page_Down, .Space, .Enter, .Keypad_Enter, .Escape:
			ui.keyboard_focus = true
		}
	}
	if event.down && event.key == Key.Tab {
		focus_next(ui, window, event.modifiers & {.Shift} != {})
		return true
	}
	id := focused_in(ui, window)
	if id != NO_ELEMENT && send_element_event(ui, id, event) {
		return true
	}
	activate := event.key == Key.Space || event.key == Key.Enter || event.key == Key.Keypad_Enter
	if id != NO_ELEMENT && activate {
		if event.down && !event.repeat && is_active(ui, id) && accepts_press(get_element(ui, id)) {
			call_press(ui, id)
		}
		return true
	}
	fallback := window.key_fallback
	if fallback.handle != nil && fallback.handle(fallback.state, window, event) {
		return true
	}
	return window.directional_focus && event.down && event.modifiers == {} &&
		move_directional_focus(ui, window, event.key)
}
