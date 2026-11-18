package elements

import fluid ".."

import "core:strings"

@(private="package")
move_caret_line :: proc(element: Control_View, editor: ^Editor, key: fluid.Key, document: bool) -> int {
	field, is_text := element.control.state.(Text_Control)
	if document || !is_text || !field.multiline {
		return key == fluid.Key.Home || key == fluid.Key.Up || key == fluid.Key.Page_Up ? 0 : len(element.label)
	}
	view := editor_view(element, editor)
	if view.text == nil {
		return 0
	}
	caret := view.caret
	line: fluid.Text_Span
	_ = fluid.text_line(view.text, caret.line_index, &line)
	#partial switch key {
	case fluid.Key.Home: return int(line.offset)
	case fluid.Key.End: return line_end_offset(element.label, line)
	case fluid.Key.Up, fluid.Key.Down, fluid.Key.Page_Up, fluid.Key.Page_Down:
		page := key == fluid.Key.Page_Up || key == fluid.Key.Page_Down
		step := page ? max(1, view.clip.h / max(1, caret.rect.h)) : 1
		target := caret.line_index + (key == fluid.Key.Up || key == fluid.Key.Page_Up ? -step : step)
		if target < 0 {
			return 0
		}
		if !fluid.text_line(view.text, target, &line) || line.line_index != target {
			return len(element.label)
		}
		if editor.column == nil {
			editor.column = caret.rect.x
		}
		offset, _ := fluid.text_hit(view.text, editor.column.?, line.rect.y + line.rect.h / 2)
		return clamp(int(offset), int(line.offset), line_end_offset(element.label, line))
	}
	return editor.caret
}

@(private="package")
place_caret :: proc(ui: ^fluid.UI, id: fluid.Element_ID, point: [2]f32, extend: bool, clicks: u8 = 0) {
	element := get_element(ui, id)
	editor := editor_for(element.control)
	value := element.label
	editor.history.last_group = .Separate
	editor.column = nil
	if clicks > 0 {
		if editor.preedit != "" {
			fluid.clear_composition(element.window)
			clear_preedit(editor)
		}
		editor.selection_clicks = extend ? 1 : clicks
	}
	view := editor_view(element, editor)
	editor.manual_scroll = false
	if view.text == nil {
		editor.anchor, editor.caret = 0, 0
		editor.selection_origin = {}
		return
	}

	scale := fluid.pixel_scale(element.window)
	x, y := i32(point[0] * scale) - view.x, i32(point[1] * scale) - view.y
	if editor.selection_clicks < 2 {
		offset, _ := fluid.text_hit(view.text, x, y)
		editor.caret = text_boundary(value, int(offset))
		if !extend {
			editor.anchor = editor.caret
		}
		return
	}

	under: fluid.Text_Span
	if _, hit := fluid.text_hit(view.text, x, y, &under); !hit {
		return
	}
	range := text_selection_range(value, int(under.offset), editor.selection_clicks)
	if clicks > 0 {
		editor.selection_origin = range
	}
	origin := editor.selection_origin
	if range[0] < origin[0] {
		editor.anchor, editor.caret = origin[1], range[0]
	} else {
		editor.anchor, editor.caret = origin[0], max(origin[1], range[1])
	}
}

@(private="file")
line_end_offset :: proc(value: string, line: fluid.Text_Span) -> int {
	end := clamp(int(line.offset + line.length), 0, len(value))
	if end > int(line.offset) && value[end - 1] == '\n' {
		end -= 1
	}
	return end
}

@(private="file")
Editor_View :: struct {
	text: ^fluid.Text,
	clip: fluid.IRect,
	x, y: i32,
	caret: fluid.Text_Span,
	composing: bool,
	composition, selection: [2]int,
	max_scroll_y: i32,
}

@(private="file")
editor_view :: proc(element: Control_View, editor: ^Editor, compose: bool = false) -> Editor_View {
	window := element.window
	scale := fluid.pixel_scale(window)
	r := element.pins
	padding := f32(0.6)
	left := i32((r.left + padding) * scale)
	right := i32((r.right - padding) * scale)
	top := i32((r.top + 0.375) * scale)
	bottom := i32((r.bottom - 0.375) * scale)
	view := Editor_View{clip = {left, top, max(0, right - left), max(0, bottom - top)}, x = left, y = top}
	multiline := false
	if field, ok := element.control.state.(Text_Control); ok {
		multiline = field.multiline
	}
	font := fluid.text_font(window, element.text_size, element.text_weight)
	font_height, line_height := fluid.text_font_metrics(font.pixels, font.bold)
	view.caret.rect.h = line_height
	if !multiline {
		view.y = i32((r.top + r.bottom) * scale / 2) - font_height / 2
	}
	caret := editor.caret
	if compose && editor.preedit != "" {
		low, high := min(editor.anchor, editor.caret), max(editor.anchor, editor.caret)
		value := strings.concatenate({element.label[:low], editor.preedit, element.label[high:]}, context.temp_allocator)
		view.text = fluid.create_text(font, value)
		if view.text != nil {
			view.composing = true
			view.composition = {low, low + len(editor.preedit)}
			view.selection = {low + editor.preedit_start, low + editor.preedit_end}
			caret = view.selection[1]
		}
	}
	if view.text == nil && element.label == "" {
		editor.scroll_x = 0
		editor.scroll_y = 0
		return view
	}
	if view.text == nil {
		view.text = fluid.element_text(element.view)
		assert(view.text != nil)
	}
	fluid.set_wrap_width(view.text, multiline ? max(1, view.clip.w) : 0)
	_ = fluid.text_span(view.text, i32(caret), &view.caret)
	if multiline {
		text_height := fluid.text_dimensions(view.text)[1]
		bottom := view.caret.rect.y + view.caret.rect.h
		view.max_scroll_y = max(0, max(text_height, bottom) - view.clip.h)
		if !editor.manual_scroll {
			editor.scroll_y = clamp(editor.scroll_y, max(0, bottom - view.clip.h), view.caret.rect.y)
		}
		editor.scroll_y = clamp(editor.scroll_y, 0, view.max_scroll_y)
		view.y -= editor.scroll_y
	} else {
		text_width := fluid.text_dimensions(view.text)[0]
		if element.text_align == .Center && text_width < view.clip.w {
			view.x += (view.clip.w - text_width) / 2
		}
		editor.scroll_x = clamp(editor.scroll_x, max(0, view.caret.rect.x - view.clip.w + 1), view.caret.rect.x)
		view.x -= editor.scroll_x
	}
	return view
}

@(private="package")
draw_editor :: proc(element: Control_View, editor: ^Editor, style: Field_Text_Style) {
	window := element.window
	focused := element.focused
	view := editor_view(element, editor, focused)
	defer {
		if view.composing {
			fluid.release_cached_text(&view.text)
		}
	}
	renderer := window.renderer
	previous_clip := fluid.render_clip(renderer, view.clip)
	defer fluid.restore_render_clip(renderer, previous_clip)
	if text := view.text; text != nil {
		selection := [2]int{min(editor.anchor, editor.caret), max(editor.anchor, editor.caret)}
		if view.composing {
			selection = view.selection
		}
		if focused {
			draw_editor_range(renderer, view, selection, style.selection, false)
			if view.composing {
				draw_editor_range(renderer, view, view.composition, style.caret, true)
			}
		}
		fluid.paint_text(renderer, text, element.text_color, f32(view.x), f32(view.y))
	} else if field, ok := element.control.state.(Text_Control); ok && field.placeholder != "" {
		text := fluid.element_text(element.view, field.placeholder)
		if text != nil {
			fluid.paint_text(renderer, text, style.placeholder, f32(view.x), f32(view.y))
		}
	}
	y := view.y + view.caret.rect.y
	if focused && y + view.caret.rect.h > view.clip.y && y < view.clip.y + view.clip.h {
		x := min(view.x + view.caret.rect.x, view.clip.x + view.clip.w - 1)
		fluid.render_fill_rect(renderer, {f32(x), f32(y), 1, f32(view.caret.rect.h)}, style.caret)
		scale := fluid.pixel_scale(window) / fluid.window_scale(window)
		area := fluid.IRect{i32(f32(x) / scale), i32(f32(y) / scale), 1, i32(f32(view.caret.rect.h) / scale)}
		fluid.set_text_input_area(window, area)
	}
}

@(private="file")
draw_editor_range :: proc(renderer: ^fluid.Renderer, view: Editor_View, range: [2]int, color: fluid.Color, underline: bool) {
	if range[0] == range[1] {
		return
	}
	for part in fluid.text_range(view.text, i32(range[0]), i32(range[1] - range[0])) {
		pixels := fluid.FRect{f32(view.x + part.x), f32(view.y + part.y), f32(max(1, part.w)), f32(part.h)}
		if underline {
			pixels.y += max(0, pixels.h - 2)
			pixels.h = 2
		}
		fluid.render_fill_rect(renderer, pixels, color)
	}
}

@(private="package")
scroll_text_area :: proc(element: Control_View, steps: f32) {
	if element.control == nil {
		return
	}
	field, ok := &element.control.state.(Text_Control)
	if !ok || !field.multiline {
		return
	}
	editor := &field.editor
	view := editor_view(element, editor)
	if view.max_scroll_y == 0 {
		return
	}
	window := element.window
	line := fluid.text_line_height(window, element.text_size, element.text_weight) * fluid.pixel_scale(window)
	editor.scroll_y = clamp(editor.scroll_y - i32(steps * line * 3), 0, view.max_scroll_y)
	editor.manual_scroll = true
}
