package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import fluid "../.."
import "../../elements"

NOTE_ROW_HEIGHT :: f32(2.04)
NOTE_STAMP_WIDTH :: f32(5.15)

Note_Row_Text :: struct {
	index: int,
	title, stamp: ^fluid.Text,
}

Note_List :: struct {
	clip: fluid.IRect,
	first, end, pixels_per_row: f64,
	width: i32,
	text: [8]Note_Row_Text,
}

create_notebook_list :: proc(n: ^Notebook, ui: ^fluid.UI) -> fluid.Element_ID {
	id := elements.create_scroll_view(ui.window, {
		color = SURFACE, style = {radius = 0.5, focus_border = LIME},
		track_color = INSET, thumb_color = MUTED, state = n,
		draw = draw_notebook_list, release_graphics = release_note_list_graphics,
	})
	fluid.set_focusable(ui, id, false)
	return id
}

// Mirror the scroll view's content inset. The hit region leaves the scrollbar
// to the scroll view and forwards scrolling from the note rows.
note_content_pins :: proc(pins: fluid.Pins) -> fluid.Pins {
	return {pins.left + 0.8, pins.top + 0.5, pins.right - 1.3, pins.bottom - 0.5}
}

note_list_input :: proc(state: rawptr, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Element_Event) -> bool {
	n := cast(^Notebook)state
	list := &n.list
	#partial switch input in event {
	case fluid.Pointer_Event:
		if input.kind != .Down || list.end <= list.first {
			return false
		}
		y := input.point.y * fluid.pixel_scale(fluid.element_window(ui, id)) - f32(list.clip.y)
		row := list.first + f64(y) / list.pixels_per_row
		if y >= 0 && row < list.end {
			choose_note(n, ui, int(math.floor(row)))
		}
		return true
	case fluid.Keyboard_Event:
		if input.down && (input.key == .Enter || input.key == .Space || input.key == .Keypad_Enter) {
			if list.end > list.first {
				choose_note(n, ui, int(math.floor(list.first)))
			}
			return true
		}
	}
	scroll := n.parts[.List]
	behavior := fluid.element_behavior(ui, scroll)
	return behavior.input(behavior.state, ui, scroll, event)
}

set_notebook_list_content :: proc(n: ^Notebook, ui: ^fluid.UI) {
	count := len(n.journals[n.site].entries)
	elements.set_scroll_content(ui, n.parts[.List], 0, f64(count), f64(NOTE_ROW_HEIGHT))
}

reset_notebook_list :: proc(n: ^Notebook, ui: ^fluid.UI) {
	release_note_list_graphics(n)
	// Install an empty interval first so the next interval starts from row zero.
	elements.set_scroll_content(ui, n.parts[.List], 0, 0)
	set_notebook_list_content(n, ui)
}

choose_note :: proc(n: ^Notebook, ui: ^fluid.UI, row: int) {
	journal := &n.journals[n.site]
	index := len(journal.entries) - 1 - row
	if index < 0 || index >= len(journal.entries) {
		return
	}
	if journal.edit != index {
		clear_entry_edit(journal)
		journal.edit = index
		journal.edit_text = strings.clone(journal.entries[index].text, os.heap_allocator())
	}
	refresh_journal(n, ui)
	fluid.focus(ui, n.parts[.Editor])
}

draw_notebook_list :: proc(state: rawptr, viewport: elements.Scroll_Viewport) {
	n := cast(^Notebook)state
	list := &n.list
	if list.width != viewport.clip.w {
		release_note_list_graphics(n)
		list.width = viewport.clip.w
	}
	list.clip, list.first, list.end, list.pixels_per_row =
		viewport.clip, viewport.first, viewport.end, viewport.pixels_per_unit
	window := viewport.element.window
	scale := fluid.pixel_scale(window)
	pointer := fluid.pointer_position(window)
	hovered := fluid.element_view(viewport.element.ui, n.parts[.List_Input]).hovered
	left := f32(viewport.clip.x) / scale
	width := f32(viewport.clip.w) / scale
	journal := &n.journals[n.site]
	for row in int(math.floor(viewport.first))..<int(math.ceil(viewport.end)) {
		index := len(journal.entries) - 1 - row
		if n.arriving && row == 0 { continue }
		y := (f32(viewport.clip.y) + f32((f64(row) - viewport.first) * viewport.pixels_per_unit)) / scale
		pins := fluid.rect(left, y, width, NOTE_ROW_HEIGHT)
		if journal.edit == index || (hovered && fluid.contains(pins, pointer)) {
			color := journal.edit == index ? FIELD_PALETTE.selected : FIELD_PALETTE.fill
			fluid.rounded_fill(window.renderer, fluid.pixel_rect(pins, scale), 0.32 * scale, color)
		}
		entry := &list.text[row % len(list.text)]
		if entry.title == nil || entry.index != index {
			release_note_row(entry)
			note := journal.entries[index]
			entry.index = index
			title := note_preview(window, note.text, width - NOTE_STAMP_WIDTH - 0.45)
			entry.title = fluid.create_text(fluid.text_font(window, TEXT_BODY, .Regular), title)
			seconds := note.sample % SAMPLES_PER_DAY * 30
			stamp := fmt.tprintf("Day %d  %02d:%02d", note.sample / SAMPLES_PER_DAY + 1, seconds / 3600, seconds / 60 % 60)
			entry.stamp = fluid.create_text(fluid.text_font(window, 0.66, .Regular), stamp)
		}
		fluid.draw_label(window, entry.title, {left + 0.45, y, pins.right - NOTE_STAMP_WIDTH, pins.bottom}, INK, .Left)
		fluid.draw_label(window, entry.stamp, {pins.right - NOTE_STAMP_WIDTH, y, pins.right - 0.35, pins.bottom}, MUTED, .Right)
	}
}

note_preview :: proc(window: ^fluid.Window, note: string, max_width: f32) -> string {
	break_at := strings.index(note, "\n")
	line := break_at >= 0 ? note[:break_at] : note
	font := fluid.text_font(window, TEXT_BODY, .Regular)
	text := fluid.create_text(font, line)
	defer fluid.release_cached_text(&text)
	scale := fluid.pixel_scale(window)
	width := max_width * scale
	dimensions := fluid.text_dimensions(text)
	if f32(dimensions.x) <= width && break_at < 0 {
		return line
	}
	ellipsis_width, _ := fluid.measure_text(window, "…", TEXT_BODY)
	available := width - ellipsis_width * scale
	if f32(dimensions.x) > available {
		cluster: fluid.Text_Span
		caret, hit := fluid.text_hit(text, i32(available), dimensions.y / 2, &cluster)
		line = hit ? line[:min(caret, cluster.offset)] : ""
	}
	return fmt.tprintf("%s…", strings.trim_space(line))
}

release_note_row :: proc(row: ^Note_Row_Text) {
	fluid.release_cached_text(&row.title)
	fluid.release_cached_text(&row.stamp)
}

release_note_list_graphics :: proc(state: rawptr) {
	n := cast(^Notebook)state
	for &row in n.list.text {
		release_note_row(&row)
	}
	n.list.first, n.list.end = 0, 0
}
