package elements

import "core:math"
import fluid ".."

@(private="package")
control_input :: proc(data: rawptr, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Element_Event) -> bool {
	control := cast(^Control)data
	switch value in event {
	case fluid.Pointer_Event:
		switch value.kind {
		case .Down: control_press(control, ui, id, value)
		case .Move: control_move(control, ui, id, value)
		case .Up, .Cancel: control_release(control, ui, id, value)
		}
	case fluid.Focus_Event:
		control_focus(control, ui, id, value)
	case fluid.Keyboard_Event:
		return control_key(control, ui, id, value)
	case fluid.Text_Editing_Event:
		if editor := editor_for(control); editor != nil {
			update_preedit(editor, value)
		}
	case fluid.Text_Input_Event:
		if editor := editor_for(control); editor != nil {
			clear_preedit(editor)
			insert_text(ui, id, string(value.text), .Typing)
		}
	case fluid.Wheel_Event:
		scroll_text_area(get_element(ui, id), f32(value))
	case fluid.Precise_Scroll_Event:
		return false
	case fluid.Focused_Frame:
		if guard, ok := &control.state.(Guard_Control); ok && guard.holding && guard.progress < 1 {
			now := u64(value)
			set_guard_progress(ui, id, guard, guard.base + f64(now - min(now, guard.started_at)) / GUARD_HOLD_NS)
		}
	}
	return true
}

@(private="file")
control_focus :: proc(control: ^Control, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Focus_Event) {
	if !event.focused {
		if guard, ok := &control.state.(Guard_Control); ok && guard.holding {
			stop_guard(ui, id, guard, fluid.monotonic_ns(), false)
		}
		if editor := editor_for(control); editor != nil {
			clear_preedit(editor)
			fluid.set_text_input(fluid.element_window(ui, id), false)
			finish_number_edit(ui, id, event.commit)
		}
		return
	}
	if editor := editor_for(control); editor != nil {
		editor.history.last_group = .Separate
		editor.column = nil
		editor.manual_scroll = false
		editor.caret = len(fluid.element_view(ui, id).label)
		editor.anchor = editor.caret
		fluid.set_text_input(fluid.element_window(ui, id), true)
	}
}

@(private="file")
control_key :: proc(control: ^Control, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Keyboard_Event) -> bool {
	if editor := editor_for(control); editor != nil && event.down {
		if event.key != fluid.Key.Escape || is_number_edit(control) || editor.preedit != "" {
			edit_key(ui, id, event)
		} else {
			fluid.blur(ui)
		}
		return true
	}
	if event.down && event.key == fluid.Key.Escape {
		return false
	}
	activate := event.key == fluid.Key.Space || event.key == fluid.Key.Enter || event.key == fluid.Key.Keypad_Enter
	direction := control_key_direction(event.key)
	switch &state in control.state {
	case Toggle_Control:
		if activate && event.down && !event.repeat {
			emit_change(ui, id, !state.checked)
		}
	case Guard_Control:
		if activate && !event.repeat {
			if event.down {
				start_guard(&state, event.timestamp, event.key)
			} else if state.holding && state.key == event.key {
				stop_guard(ui, id, &state, event.timestamp, true)
			}
		}
	case Choice_Control:
		if event.down && direction != 0 {
			propose_choice(ui, id, &state, state.selected + direction)
		}
	case Number_Control:
		if event.down && direction != 0 {
			propose_number(ui, id, &state, state.value + f64(direction) * state.options.step)
		} else if activate && event.down && !event.repeat {
			begin_number_edit(ui, id, &state)
		}
	case Button_Control, Text_Control:
	}
	return true
}

@(private="file")
control_key_direction :: proc(key: fluid.Key) -> int {
	#partial switch key {
	case fluid.Key.Right, fluid.Key.Up: return 1
	case fluid.Key.Left, fluid.Key.Down: return -1
	}
	return 0
}

@(private="file")
control_press :: proc(control: ^Control, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Pointer_Event) {
	point := event.point
	switch &state in control.state {
	case Toggle_Control:
		emit_change(ui, id, !state.checked)
	case Guard_Control:
		start_guard(&state, event.timestamp, .Unknown)
	case Choice_Control:
		r := fluid.bounds(ui, id)
		count := choice_slot_count(&state)
		hit := clamp(int((point[0] - r.left) / fluid.width(r) * f32(count)), 0, count - 1)
		if state.neighbors && hit == 1 {
			state.start_x = point[0]
			state.start = state.selected
			state.preview = state.selected
			fluid.capture_pointer(ui, id)
			fluid.set_cursor(ui, id, .Move)
		} else {
			propose_choice(ui, id, &state, choice_index_at_slot(&state, hit, state.selected))
		}
	case Number_Control:
		if !state.editing && event.clicks == 1 {
			state.start_x = point[0]
			state.start_value = state.value
		} else if !state.editing {
			begin_number_edit(ui, id, &state)
			return
		} else {
			place_caret(ui, id, point, false, max(event.clicks, 1))
		}
		fluid.capture_pointer(ui, id)
	case Text_Control:
		place_caret(ui, id, point, event.modifiers & {.Shift} != {}, max(event.clicks, 1))
		fluid.capture_pointer(ui, id)
	case Button_Control:
	}
}

@(private="file")
control_move :: proc(control: ^Control, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Pointer_Event) {
	if guard, ok := &control.state.(Guard_Control); ok && guard.holding && guard.key == .Unknown && !event.inside {
		stop_guard(ui, id, guard, event.timestamp, false)
	}
	if !fluid.pointer_captured(ui, id) {
		return
	}
	switch &state in control.state {
	case Choice_Control:
		distance := (state.start_x - event.point[0]) * fluid.UI_UNIT_POINTS
		show_choice(&state, clamp(state.start + int(math.round(distance / 28)), 0, len(state.items) - 1))
	case Number_Control:
		if state.editing {
			place_caret(ui, id, event.point, true)
		} else {
			distance := f64(event.point[0] - state.start_x) * f64(fluid.UI_UNIT_POINTS)
			propose_number(ui, id, &state, state.start_value + f64(int(distance / 4)) * state.options.step)
		}
	case Text_Control:
		place_caret(ui, id, event.point, true)
	case Button_Control, Toggle_Control, Guard_Control:
	}
}

@(private="file")
control_release :: proc(control: ^Control, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Pointer_Event) {
	released := event.kind == .Up
	switch &state in control.state {
	case Choice_Control:
		fluid.set_cursor(ui, id, .Default)
		if released {
			propose_choice(ui, id, &state, state.preview)
			if !fluid.valid(ui, id) {
				return
			}
		}
		show_choice(&state, state.selected)
	case Guard_Control:
		if state.holding && state.key == .Unknown {
			stop_guard(ui, id, &state, event.timestamp, released && event.inside)
		}
	case Button_Control, Toggle_Control, Number_Control, Text_Control:
	}
}

@(private="file")
propose_choice :: proc(ui: ^fluid.UI, id: fluid.Element_ID, choice: ^Choice_Control, index: int) {
	next := clamp(index, 0, len(choice.items) - 1)
	if next != choice.selected {
		emit_change(ui, id, next)
	}
}

GUARD_HOLD_NS :: 750_000_000
GUARD_CLICK_NS :: 180_000_000
GUARD_RESET_NS :: 500_000_000

@(private="file")
start_guard :: proc(guard: ^Guard_Control, now: u64, key: fluid.Key) {
	if guard.holding {
		return
	}
	if guard.reset_at != 0 && now >= guard.reset_at {
		guard.progress = 0
	}
	guard.reset_at = 0
	guard.base = guard.progress
	guard.started_at = now
	guard.key = key
	guard.holding = true
}

@(private="file")
stop_guard :: proc(ui: ^fluid.UI, id: fluid.Element_ID, guard: ^Guard_Control, now: u64, released: bool) {
	guard.holding = false
	guard.reset_at = now + GUARD_RESET_NS
	if !released || guard.progress >= 1 {
		return
	}
	elapsed := now - min(now, guard.started_at)
	if elapsed <= GUARD_CLICK_NS {
		// A tap advances the next notch based on progress before the press.
		set_guard_progress(ui, id, guard, (math.floor(guard.base * 3 + 1e-9) + 1) / 3)
	} else {
		set_guard_progress(ui, id, guard, guard.base + f64(elapsed) / GUARD_HOLD_NS)
	}
}

@(private="file")
set_guard_progress :: proc(ui: ^fluid.UI, id: fluid.Element_ID, guard: ^Guard_Control, progress: f64) {
	guard.progress = min(1, progress)
	if guard.progress >= 1 {
		fluid.invoke_press(ui, id)
	}
}
