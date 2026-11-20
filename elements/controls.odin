package elements

import fluid ".."

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

// Callers apply proposed values with the corresponding setter. A string in a
// change event is borrowed for the duration of the callback.
Control_Value :: union {bool, int, f64, string}
Control_Change :: struct {
	id: fluid.Element_ID,
	value: Control_Value,
}

@(private="package")
Control :: struct {
	change: fluid.Element_Callback(Control_Change),
	motion: Button_Motion,
	state: Control_State,
}

@(private="package")
Control_State :: union {Button_Control, Toggle_Control, Choice_Control, Number_Control, Text_Control, Guard_Control}

@(private="package")
Button_Control :: struct {
	variant: Button_Variant,
	selected: bool,
}

@(private="package")
Toggle_Control :: struct {checked: bool}

@(private="package")
Choice_Control :: struct {
	items: []Choice_Item,
	neighbors: bool,
	selected, preview, start: int,
	start_x: f32,
	slide_started: u64,
	slide_direction: f32,
}

@(private="package")
Choice_Item :: struct {
	label: string,
	text: ^fluid.Text,
	motion: Button_Motion,
	hover_tint: Tween,
}

@(private="package")
choice_slot_count :: proc(choice: ^Choice_Control) -> int {
	return choice.neighbors ? 3 : len(choice.items)
}

@(private="package")
choice_index_at_slot :: proc(choice: ^Choice_Control, slot, current: int) -> int {
	return choice.neighbors ? current + slot - 1 : slot
}

Number_Options :: struct {
	minimum, maximum: Maybe(f64),
	step: f64,
	prefix, suffix: string,
}

@(private="package")
Number_Control :: struct {
	value, start_value: f64,
	start_x: f32,
	options: Number_Options,
	editor: Editor,
	editing: bool,
	edit_width: f32,
}

@(private="package")
Text_Control :: struct {
	placeholder: string,
	multiline: bool,
	editor: Editor,
}

@(private="package")
Guard_Control :: struct {
	progress, base: f64,
	started_at, reset_at: u64,
	key: fluid.Key,
	holding: bool,
	fill: Tween,
}

@(private="package")
Control_View :: struct {
	using view: fluid.Element_View,
	control: ^Control,
}

@(private="package")
get_control :: proc(ui: ^fluid.UI, id: fluid.Element_ID) -> ^Control {
	behavior := fluid.element_behavior(ui, id)
	return behavior.destroy == destroy_control ? cast(^Control)behavior.state : nil
}

@(private="package")
get_element :: proc(ui: ^fluid.UI, id: fluid.Element_ID) -> Control_View {
	return {fluid.element_view(ui, id), get_control(ui, id)}
}

@(private="package")
create_control :: proc(window: ^fluid.Window, pins: fluid.Pins, label: string, state: Control_State, cursor: fluid.Cursor = .Default) -> fluid.Element_ID {
	control := new(Control, os.heap_allocator())
	control.state = state
	definition := button_definition(pins, label)
	definition.cursor = cursor
	input := control_input
	if _, plain_button := state.(Button_Control); plain_button {
		input = nil
	}
	definition.behavior = {
		state = control,
		input = input,
		release_graphics = release_control_graphics,
		destroy = destroy_control,
	}
	definition.draw = draw_control
	return fluid.create_element(window, definition)
}

on_change :: proc(ui: ^fluid.UI, id: fluid.Element_ID, owner: ^$Owner,
	run: proc(owner: ^Owner, ui: ^fluid.UI, change: Control_Change),
) {
	control := get_control(ui, id)
	assert(control != nil)
	fluid.bind_element(&control.change, owner, run)
}

@(private="package")
emit_change :: proc(ui: ^fluid.UI, id: fluid.Element_ID, value: Control_Value) {
	callback := get_control(ui, id).change
	if callback.call != nil {
		callback.call(callback.data, ui, {id, value})
	}
}

toggle :: proc(window: ^fluid.Window, pins: fluid.Pins, label: string, value: bool) -> fluid.Element_ID {
	return create_control(window, pins, label, Toggle_Control{checked = value})
}

set_toggle :: proc(ui: ^fluid.UI, id: fluid.Element_ID, checked: bool) {
	state := &get_control(ui, id).state.(Toggle_Control)
	state.checked = checked
}

dangerous_button :: proc(window: ^fluid.Window, pins: fluid.Pins, label: string) -> fluid.Element_ID {
	return create_control(window, pins, label, Guard_Control{})
}

options :: proc(window: ^fluid.Window, pins: fluid.Pins, labels: []string, selected: int) -> fluid.Element_ID {
	return choice_control(window, pins, labels, selected, false)
}

select :: proc(window: ^fluid.Window, pins: fluid.Pins, labels: []string, selected: int) -> fluid.Element_ID {
	return choice_control(window, pins, labels, selected, true)
}

@(private="file")
choice_control :: proc(window: ^fluid.Window, pins: fluid.Pins, labels: []string, selected: int, neighbors: bool) -> fluid.Element_ID {
	assert(selected >= 0 && selected < len(labels))
	allocator := os.heap_allocator()
	items := make([]Choice_Item, len(labels), allocator)
	for label, i in labels {
		items[i].label = strings.clone(label, allocator)
	}
	return create_control(window, pins, "", Choice_Control{items = items, neighbors = neighbors, selected = selected, preview = selected})
}

set_choice :: proc(ui: ^fluid.UI, id: fluid.Element_ID, selected: int) {
	choice := &get_element(ui, id).control.state.(Choice_Control)
	assert(selected >= 0 && selected < len(choice.items))
	choice.selected = selected
	if !fluid.pointer_captured(ui, id) {
		show_choice(choice, selected)
	}
}

@(private="package")
show_choice :: proc(choice: ^Choice_Control, index: int) {
	if choice.neighbors && index != choice.preview {
		choice.slide_direction = index > choice.preview ? 1 : -1
		choice.slide_started = fluid.monotonic_ns()
	}
	choice.preview = index
}

number_input :: proc(window: ^fluid.Window, pins: fluid.Pins, value: f64, options: Number_Options = {}) -> fluid.Element_ID {
	if low, bounded := options.minimum.?; bounded {
		assert(!math.is_nan(low) && !math.is_inf(low))
	}
	if high, bounded := options.maximum.?; bounded {
		assert(!math.is_nan(high) && !math.is_inf(high))
		if low, lower_bounded := options.minimum.?; lower_bounded {
			assert(low <= high)
		}
	}
	settings := options
	settings.prefix = strings.clone(options.prefix, os.heap_allocator())
	settings.suffix = strings.clone(options.suffix, os.heap_allocator())
	if settings.step <= 0 || math.is_nan(settings.step) || math.is_inf(settings.step) {
		settings.step = 1
	}
	id := create_control(window, pins, "", Number_Control{options = settings}, .Resize_Horizontal)
	set_number(window.ui, id, value)
	return id
}

set_number :: proc(ui: ^fluid.UI, id: fluid.Element_ID, value: f64) {
	assert(!math.is_nan(value) && !math.is_inf(value))
	number := &get_element(ui, id).control.state.(Number_Control)
	number.value = normalize_number(number, value)
	if !number.editing {
		show_number_value(ui, id, number)
	}
}

@(private="package")
show_number_value :: proc(ui: ^fluid.UI, id: fluid.Element_ID, number: ^Number_Control) {
	fluid.set_label(ui, id, fmt.tprintf("%s%v%s", number.options.prefix, number.value, number.options.suffix))
}

@(private="package")
normalize_number :: proc(number: ^Number_Control, value: f64) -> f64 {
	result := value
	// Suppress floating-point noise from step increments.
	if abs(result) < 1e15 {
		result = math.round(result * 1e10) / 1e10
	}
	if low, bounded := number.options.minimum.?; bounded {
		result = max(low, result)
	}
	if high, bounded := number.options.maximum.?; bounded {
		result = min(high, result)
	}
	return result
}

@(private="package")
propose_number :: proc(ui: ^fluid.UI, id: fluid.Element_ID, number: ^Number_Control, value: f64) {
	if math.is_nan(value) || math.is_inf(value) {
		return
	}
	next := normalize_number(number, value)
	if next != number.value {
		emit_change(ui, id, next)
	}
}

text_input :: proc(window: ^fluid.Window, pins: fluid.Pins, value: string, placeholder: string = "") -> fluid.Element_ID {
	return text_control(window, pins, value, placeholder, false)
}

text_area :: proc(window: ^fluid.Window, pins: fluid.Pins, value: string, placeholder: string = "") -> fluid.Element_ID {
	return text_control(window, pins, value, placeholder, true)
}

@(private="file")
text_control :: proc(window: ^fluid.Window, pins: fluid.Pins, value, placeholder: string, multiline: bool) -> fluid.Element_ID {
	id := create_control(window, pins, "", Text_Control{
		placeholder = strings.clone(placeholder, os.heap_allocator()),
		multiline = multiline,
	}, .Text)
	fluid.set_style(window.ui, id, {
		radius = 0.375, border = {64, 77, 94, 255}, border_width = 0.0625,
		hover_border = {98, 112, 129, 255},
	})
	fluid.set_text_style(window.ui, id, align = .Left)
	set_text_value(window.ui, id, value)
	return id
}

set_text_value :: proc(ui: ^fluid.UI, id: fluid.Element_ID, value: string) {
	element := get_element(ui, id)
	text := &element.control.state.(Text_Control)
	next := field_text(value, text.multiline)
	if next != element.label {
		proposed, user_edit := text.editor.history.proposed.?
		if !user_edit || proposed != next {
			reset_history(&text.editor.history)
		}
		text.editor.column = nil
		for &offset in text.editor.selection_origin {
			offset = text_boundary(next, offset)
		}
		fluid.set_label(ui, id, next)
	}
	text.editor.anchor = text_boundary(element.label, text.editor.anchor)
	text.editor.caret = text_boundary(element.label, text.editor.caret)
}

@(private="file")
release_control_graphics :: proc(data: rawptr) {
	control := cast(^Control)data
	if choice, ok := &control.state.(Choice_Control); ok {
		for &item in choice.items {
			fluid.release_cached_text(&item.text)
		}
	}
}

@(private="package")
destroy_control :: proc(data: rawptr) {
	control := cast(^Control)data
	allocator := os.heap_allocator()
	switch &state in control.state {
	case Choice_Control:
		for item in state.items {
			delete(item.label, allocator)
		}
		delete(state.items, allocator)
	case Text_Control:
		destroy_editor(&state.editor)
		delete(state.placeholder, allocator)
	case Number_Control:
		destroy_editor(&state.editor)
		delete(state.options.prefix, allocator)
		delete(state.options.suffix, allocator)
	case Button_Control, Toggle_Control, Guard_Control:
	}
	fluid.clear_element_callback(&control.change)
	free(control, allocator)
}
