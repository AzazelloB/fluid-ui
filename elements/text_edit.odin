package elements

import fluid ".."

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

@(private="package")
Editor :: struct {
	anchor, caret: int, // UTF-8 byte offsets at grapheme boundaries.
	history: Editor_History,
	column: Maybe(i32),
	selection_clicks: u8,
	selection_origin: [2]int,
	scroll_x, scroll_y: i32,
	manual_scroll: bool,
	preedit: string,
	preedit_start, preedit_end: int,
}

@(private="package")
editor_for :: proc(control: ^Control) -> ^Editor {
	switch &state in control.state {
	case Text_Control: return &state.editor
	case Number_Control: if state.editing { return &state.editor }
	case Button_Control, Toggle_Control, Guard_Control, Choice_Control:
	}
	return nil
}

@(private="package")
is_number_edit :: proc(control: ^Control) -> bool {
	if number, ok := control.state.(Number_Control); ok {
		return number.editing
	}
	return false
}

@(private="package")
begin_number_edit :: proc(ui: ^fluid.UI, id: fluid.Element_ID, number: ^Number_Control) {
	number.editing = true
	number.edit_width = fluid.width(fluid.bounds(ui, id))
	// While editing, the element text owns the unformatted draft.
	draft := fmt.tprintf("%v", number.value)
	number.editor = {caret = len(draft)}
	fluid.set_label(ui, id, draft)
	fluid.set_cursor(ui, id, .Text)
	fluid.set_text_input(fluid.element_window(ui, id), true)
}

@(private="package")
finish_number_edit :: proc(ui: ^fluid.UI, id: fluid.Element_ID, commit: bool) {
	element := get_element(ui, id)
	if !is_number_edit(element.control) {
		return
	}
	number := &element.control.state.(Number_Control)
	value, parsed := strconv.parse_f64(strings.trim_space(element.label))
	destroy_editor(&number.editor)
	number.editor = {}
	number.editing = false
	fluid.set_cursor(ui, id, .Resize_Horizontal)
	show_number_value(ui, id, number)
	if commit && parsed {
		propose_number(ui, id, number, value)
	}
}

@(private="package")
field_text :: proc(value: string, multiline: bool) -> string {
	if !strings.contains_any(value, "\r\n\x00") {
		return value
	}
	builder := strings.builder_make(context.temp_allocator)
	for i in 0..<len(value) {
		switch value[i] {
		case 0:
		case '\r':
			if i + 1 >= len(value) || value[i + 1] != '\n' {
				strings.write_byte(&builder, multiline ? '\n' : ' ')
			}
		case '\n': strings.write_byte(&builder, multiline ? '\n' : ' ')
		case: strings.write_byte(&builder, value[i])
		}
	}
	return strings.to_string(builder)
}

@(private="package")
text_boundary :: proc(value: string, offset: int) -> int {
	if offset <= 0 || offset >= len(value) {
		return clamp(offset, 0, len(value))
	}
	if value[offset] < 0x80 && value[offset - 1] < 0x80 {
		return offset // Field values use LF line endings.
	}
	index := strings.last_index_byte(value[:offset], '\n') + 1
	iterator := utf8.decode_grapheme_iterator_make(value[index:])
	for grapheme, _ in utf8.decode_grapheme_iterate(&iterator) {
		next := index + len(grapheme)
		if next > offset {
			break
		}
		index = next
	}
	return index
}

@(private="file")
next_boundary :: proc(value: string, offset: int) -> int {
	iterator := utf8.decode_grapheme_iterator_make(value[offset:])
	if grapheme, _, ok := utf8.decode_grapheme_iterate(&iterator); ok {
		return offset + len(grapheme)
	}
	return offset
}

@(private="file")
Text_Run :: enum {Space, Word, Other}

@(private="file")
text_run :: proc(r: rune) -> Text_Run {
	if unicode.is_space(r) {
		return .Space
	}
	// Keep underscores and combining marks with letters and numbers.
	if r == '_' || (unicode.is_graphic(r) && !unicode.is_punct(r) && !unicode.is_symbol(r)) {
		return .Word
	}
	return .Other
}

@(private="file")
skip_text_run :: proc(value: string, offset: int, backwards: bool, space_only: bool = false) -> int {
	index := offset
	run: Maybe(Text_Run)
	limit := backwards ? 0 : len(value)
	for index != limit {
		r: rune
		size: int
		if backwards {
			r, size = utf8.decode_last_rune_in_string(value[:index])
		} else {
			r, size = utf8.decode_rune_in_string(value[index:])
		}
		kind := text_run(r)
		if first, started := run.?; started {
			if kind != first {
				break
			}
		} else {
			if space_only && kind != .Space {
				break
			}
			run = kind
		}
		index += backwards ? -size : size
	}
	return index
}

@(private="file")
horizontal_boundary :: proc(element: Control_View, editor: ^Editor, backwards: bool, modifiers: fluid.Key_Modifiers) -> int {
	value := element.label
	offset := editor.caret
	if modifiers & {.Gui} != {} {
		line_edge := move_caret_line(element, editor, backwards ? fluid.Key.Home : fluid.Key.End, false)
		return text_boundary(value, line_edge)
	}
	by_word := modifiers & {.Ctrl, .Alt} != {}
	if !by_word {
		return backwards ? text_boundary(value, offset - 1) : next_boundary(value, offset)
	}
	if backwards {
		start := skip_text_run(value, skip_text_run(value, offset, true, true), true)
		return text_boundary(value, start)
	}
	target: int
	if modifiers & {.Ctrl} != {} {
		// Control moves forward to the beginning of the next run.
		target = skip_text_run(value, skip_text_run(value, offset, false), false, true)
	} else {
		// Option moves forward to the end of the next run.
		target = skip_text_run(value, skip_text_run(value, offset, false, true), false)
	}
	return text_boundary_after(value, target)
}

@(private="file")
text_boundary_after :: proc(value: string, offset: int) -> int {
	caret := text_boundary(value, offset)
	return caret < offset ? next_boundary(value, caret) : caret
}

@(private="file")
paragraph_boundary :: proc(value: string, offset: int, backwards: bool) -> int {
	if backwards {
		start := strings.last_index_byte(value[:offset], '\n') + 1
		if start == offset && start > 0 {
			return strings.last_index_byte(value[:start - 1], '\n') + 1
		}
		return start
	}
	end := strings.index_byte(value[offset:], '\n')
	return end < 0 ? len(value) : offset + end + 1
}

@(private="package")
text_selection_range :: proc(value: string, byte_offset: int, clicks: u8) -> [2]int {
	offset := clamp(byte_offset, 0, len(value))
	if clicks >= 3 {
		start := strings.last_index_byte(value[:offset], '\n') + 1
		return {start, paragraph_boundary(value, offset, false)}
	}
	if offset == len(value) {
		offset = text_boundary(value, offset - 1)
	}
	// Both scans start inside the same run, even on its first character.
	first := text_boundary(value, offset)
	last := next_boundary(value, first)
	start := skip_text_run(value, last, true)
	end := skip_text_run(value, first, false)
	return {text_boundary(value, min(first, start)), text_boundary_after(value, max(last, end))}
}

@(private="package")
insert_text :: proc(ui: ^fluid.UI, id: fluid.Element_ID, inserted: string, group: Edit_Group = .Separate) {
	element := get_element(ui, id)
	editor := editor_for(element.control)
	low, high := min(editor.anchor, editor.caret), max(editor.anchor, editor.caret)
	replace_text(ui, id, low, high, inserted, group)
}

@(private="file")
replace_text :: proc(ui: ^fluid.UI, id: fluid.Element_ID, low, high: int, inserted: string, group: Edit_Group = .Separate) {
	element := get_element(ui, id)
	field, is_text := element.control.state.(Text_Control)
	inserted := field_text(inserted, is_text && field.multiline)
	result := strings.concatenate({element.label[:low], inserted, element.label[high:]}, context.temp_allocator)
	caret := text_boundary_after(result, low + len(inserted))
	snapshot := Editor_Snapshot{result, caret, caret}
	if result == element.label {
		apply_editor_snapshot(ui, id, snapshot)
	} else {
		record_editor_edit(ui, id, snapshot, group)
	}
}

@(private="package")
apply_editor_snapshot :: proc(ui: ^fluid.UI, id: fluid.Element_ID, snapshot: Editor_Snapshot) -> ^Editor {
	element := get_element(ui, id)
	editor := editor_for(element.control)
	if snapshot.value != element.label {
		if is_number_edit(element.control) {
			fluid.set_label(ui, id, snapshot.value)
		} else {
			editor.history.proposed = snapshot.value
			emit_change(ui, id, snapshot.value)
			if !fluid.valid(ui, id) {
				return nil
			}
			element = get_element(ui, id)
			editor = editor_for(element.control)
			editor.history.proposed = nil
			if element.label != snapshot.value {
				return nil
			}
		}
	}
	editor.anchor = snapshot.anchor
	editor.caret = snapshot.caret
	editor.column = nil
	editor.manual_scroll = false
	return editor
}

@(private="package")
edit_key :: proc(ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Keyboard_Event) {
	element := get_element(ui, id)
	editor := editor_for(element.control)
	if editor.preedit != "" {
		if event.key == fluid.Key.Escape {
			fluid.clear_composition(element.window)
			clear_preedit(editor)
		}
		return
	}
	value := element.label
	low, high := min(editor.anchor, editor.caret), max(editor.anchor, editor.caret)
	extend := event.modifiers & {.Shift} != {}
	shortcut := event.modifiers & {.Ctrl, .Gui} != {}
	if shortcut {
		#partial switch event.key {
		case fluid.Key.Z:
			restore_editor_edit(ui, id, extend)
			return
		case fluid.Key.Y:
			restore_editor_edit(ui, id, true)
			return
		case fluid.Key.A:
			editor.history.last_group = .Separate
			editor.column = nil
			editor.manual_scroll = false
			editor.anchor = 0
			editor.caret = len(value)
			return
		case fluid.Key.C, fluid.Key.X:
			if low != high {
				if fluid.set_clipboard_text(element.window, value[low:high]) && event.key == fluid.Key.X {
					replace_text(ui, id, low, high, "")
				}
			}
			return
		case fluid.Key.V:
			if data := fluid.get_clipboard_text(element.window); data != "" {
				insert_text(ui, id, data)
			}
			return
		case:
		}
	}
	next := editor.caret
	vertical := event.key == fluid.Key.Up || event.key == fluid.Key.Down ||
		event.key == fluid.Key.Page_Up || event.key == fluid.Key.Page_Down
	if !vertical || shortcut {
		editor.column = nil
	}
	#partial switch event.key {
	case fluid.Key.Enter, fluid.Key.Keypad_Enter:
		if is_number_edit(element.control) {
			fluid.set_text_input(element.window, false)
			finish_number_edit(ui, id, true)
		} else if element.control.state.(Text_Control).multiline {
			insert_text(ui, id, "\n")
		} else {
			fluid.blur(ui)
		}
		return
	case fluid.Key.Escape:
		fluid.set_text_input(element.window, false)
		finish_number_edit(ui, id, false)
		return
	case fluid.Key.Backspace, fluid.Key.Delete:
		group := Edit_Group.Separate
		if low == high {
			if event.modifiers & {.Ctrl, .Alt, .Gui} == {} {
				group = event.key == fluid.Key.Backspace ? .Backspace : .Delete
			}
			backwards := event.key == fluid.Key.Backspace
			target := horizontal_boundary(element, editor, backwards, event.modifiers)
			low, high = min(next, target), max(next, target)
		}
		if low != high {
			replace_text(ui, id, low, high, "", group)
		}
		return
	case fluid.Key.Left, fluid.Key.Right:
		backwards := event.key == fluid.Key.Left
		word_or_line := event.modifiers & {.Ctrl, .Alt, .Gui} != {}
		if !word_or_line && !extend && low != high {
			next = backwards ? low : high
		} else {
			next = horizontal_boundary(element, editor, backwards, event.modifiers)
		}
	case fluid.Key.Home, fluid.Key.End:
		next = move_caret_line(element, editor, event.key, shortcut)
	case fluid.Key.Page_Up, fluid.Key.Page_Down:
		next = move_caret_line(element, editor, event.key, false)
	case fluid.Key.Up, fluid.Key.Down:
		backwards := event.key == fluid.Key.Up
		if event.modifiers & {.Gui} != {} {
			next = backwards ? 0 : len(value)
		} else if event.modifiers & {.Ctrl} != {} {
			next = paragraph_boundary(value, next, backwards)
		} else {
			next = move_caret_line(element, editor, event.key, false)
		}
	case:
		return
	}
	editor.history.last_group = .Separate
	editor.manual_scroll = false
	editor.caret = text_boundary(value, next)
	if !extend {
		editor.anchor = editor.caret
	}
}

@(private="package")
update_preedit :: proc(editor: ^Editor, event: fluid.Text_Editing_Event) {
	clear_preedit(editor)
	value := event.text
	if value == "" {
		return
	}
	editor.preedit = strings.clone(value, os.heap_allocator())
	editor.preedit_start = codepoint_offset(value, event.start)
	editor.preedit_end = event.start < 0 ? editor.preedit_start :
		codepoint_offset(value, event.start + max(0, event.length))
	editor.manual_scroll = false
	editor.history.last_group = .Separate
}

@(private="file")
codepoint_offset :: proc(value: string, count: i32) -> int {
	if count < 0 {
		return len(value)
	}
	remaining := count
	for _, offset in value {
		if remaining == 0 {
			return offset
		}
		remaining -= 1
	}
	return len(value)
}

@(private="package")
clear_preedit :: proc(editor: ^Editor) {
	delete(editor.preedit, os.heap_allocator())
	editor.preedit = ""
	editor.preedit_start, editor.preedit_end = 0, 0
}
