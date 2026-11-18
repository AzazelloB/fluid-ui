package elements

import fluid ".."

import "core:strings"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

@(private="package")
move_caret_line :: proc(element: Control_View, editor: ^Editor, key: sdl3.Keycode, document: bool) -> int {
	field, is_text := element.control.state.(Text_Control)
	if document || !is_text || !field.multiline {
		return key == sdl3.K_HOME || key == sdl3.K_UP || key == sdl3.K_PAGEUP ? 0 : len(element.label)
	}
	view := editor_view(element, editor)
	if view.text == nil {
		return 0
	}
	caret := view.caret
	line: ttf.SubString
	_ = ttf.GetTextSubStringForLine(view.text, caret.line_index, &line)
	switch key {
	case sdl3.K_HOME: return int(line.offset)
	case sdl3.K_END: return line_end_offset(element.label, line)
	case sdl3.K_UP, sdl3.K_DOWN, sdl3.K_PAGEUP, sdl3.K_PAGEDOWN:
		page := key == sdl3.K_PAGEUP || key == sdl3.K_PAGEDOWN
		step := page ? max(1, view.clip.h / max(1, caret.rect.h)) : 1
		target := caret.line_index + (key == sdl3.K_UP || key == sdl3.K_PAGEUP ? -step : step)
		if target < 0 {
			return 0
		}
		if !ttf.GetTextSubStringForLine(view.text, target, &line) || line.line_index != target {
			return len(element.label)
		}
		if editor.column == nil {
			editor.column = caret.rect.x
		}
		offset := caret_at(view.text, element.label, editor.column.?, line.rect.y + line.rect.h / 2)
		return clamp(offset, int(line.offset), line_end_offset(element.label, line))
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
			_ = sdl3.ClearComposition(element.window.handle)
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
		editor.caret = text_boundary(value, caret_at(view.text, value, x, y))
		if !extend {
			editor.anchor = editor.caret
		}
		return
	}

	under: ttf.SubString
	if !ttf.GetTextSubStringForPoint(view.text, x, y, &under) {
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
caret_at :: proc(text: ^ttf.Text, value: string, x, y: i32) -> int {
	under: ttf.SubString
	if !ttf.GetTextSubStringForPoint(text, x, y, &under) {
		return 0
	}
	offset := int(under.offset + (x > under.rect.x + under.rect.w / 2 ? under.length : 0))
	line: ttf.SubString
	if ttf.GetTextSubStringForLine(text, under.line_index, &line) {
		return min(offset, line_end_offset(value, line))
	}
	return offset
}

@(private="file")
line_end_offset :: proc(value: string, line: ttf.SubString) -> int {
	end := clamp(int(line.offset + line.length), 0, len(value))
	if end > int(line.offset) && value[end - 1] == '\n' {
		end -= 1
	}
	return end
}

@(private="file")
Editor_View :: struct {
	text: ^ttf.Text,
	clip: sdl3.Rect,
	x, y: i32,
	caret: ttf.SubString,
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
	line_height := ttf.GetFontLineSkip(font)
	view.caret.rect.h = line_height
	if !multiline {
		view.y = i32((r.top + r.bottom) * scale / 2) - ttf.GetFontHeight(font) / 2
	}
	caret := editor.caret
	if compose && editor.preedit != "" {
		low, high := min(editor.anchor, editor.caret), max(editor.anchor, editor.caret)
		value := strings.concatenate({element.label[:low], editor.preedit, element.label[high:]}, context.temp_allocator)
		view.text = ttf.CreateText(window.text_engine, font, raw_data(value), len(value))
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
	_ = ttf.GetTextSubString(view.text, i32(caret), &view.caret)
	if multiline {
		text_height: i32
		_ = ttf.GetTextSize(view.text, nil, &text_height)
		bottom := view.caret.rect.y + view.caret.rect.h
		view.max_scroll_y = max(0, max(text_height, bottom) - view.clip.h)
		if !editor.manual_scroll {
			editor.scroll_y = clamp(editor.scroll_y, max(0, bottom - view.clip.h), view.caret.rect.y)
		}
		editor.scroll_y = clamp(editor.scroll_y, 0, view.max_scroll_y)
		view.y -= editor.scroll_y
	} else {
		text_width: i32
		_ = ttf.GetTextSize(view.text, &text_width, nil)
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
			ttf.DestroyText(view.text)
		}
	}
	renderer := window.renderer
	_ = sdl3.SetRenderClipRect(renderer, &view.clip)
	defer sdl3.SetRenderClipRect(renderer, nil)
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
		fluid.paint_text(text, element.text_color, f32(view.x), f32(view.y))
	} else if field, ok := element.control.state.(Text_Control); ok && field.placeholder != "" {
		text := fluid.element_text(element.view, field.placeholder)
		if text != nil {
			fluid.paint_text(text, style.placeholder, f32(view.x), f32(view.y))
		}
	}
	y := view.y + view.caret.rect.y
	if focused && y + view.caret.rect.h > view.clip.y && y < view.clip.y + view.clip.h {
		x := min(view.x + view.caret.rect.x, view.clip.x + view.clip.w - 1)
		_ = sdl3.SetRenderDrawColor(renderer, style.caret.r, style.caret.g, style.caret.b, style.caret.a)
		_ = sdl3.RenderLine(renderer, f32(x), f32(y), f32(x), f32(y + view.caret.rect.h - 1))
		scale := fluid.pixel_scale(window) / fluid.window_scale(window)
		area := sdl3.Rect{i32(f32(x) / scale), i32(f32(y) / scale), 1, i32(f32(view.caret.rect.h) / scale)}
		_ = sdl3.SetTextInputArea(window.handle, &area, 0)
	}
}

@(private="file")
draw_editor_range :: proc(renderer: ^sdl3.Renderer, view: Editor_View, range: [2]int, color: fluid.Color, underline: bool) {
	if range[0] == range[1] {
		return
	}
	count: i32
	parts := ttf.GetTextSubStringsForRange(view.text, i32(range[0]), i32(range[1] - range[0]), &count)
	if parts == nil {
		return
	}
	defer sdl3.free(parts)
	_ = sdl3.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	for i in 0..<count {
		part := parts[i].rect
		pixels := sdl3.FRect{f32(view.x + part.x), f32(view.y + part.y), f32(max(1, part.w)), f32(part.h)}
		if underline {
			pixels.y += max(0, pixels.h - 2)
			pixels.h = 2
		}
		_ = sdl3.RenderFillRect(renderer, &pixels)
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
