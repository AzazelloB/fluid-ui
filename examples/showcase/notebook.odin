package main

import "core:math"
import "core:os"
import "core:strings"
import fluid "../.."
import "../../elements"

NOTEBOOK_WIDTH :: f32(17.5)
NOTEBOOK_RADIUS :: f32(0.75)
NOTEBOOK_FLOAT_SIZE :: [2]f32{NOTEBOOK_WIDTH, 29}
Dock_Side :: enum {Right, Left}

Notebook_Part :: enum {
	Surface, Handle, Grip, Title, List, List_Input, Editor_Title, Editor, Feedback, New, Reading,
}

Note :: struct {
	text: string,
	sample: int,
}

Station_Journal :: struct {
	entries: [dynamic]Note,
	draft, edit_text: string,
	edit: Maybe(int),
}

Notebook :: struct {
	parts: [Notebook_Part]fluid.Element_ID,
	list: Note_List,
	owner: ^Showcase,
	hints: [Dock_Side]fluid.Element_ID,
	hint_progress: [Dock_Side]f32,
	save, arriving_text: fluid.Element_ID,
	arriving: bool,
	journals: [Site]Station_Journal,
	site: Site,
	window: ^fluid.Window,
	side: Dock_Side,
	area: fluid.Pins,
	grab, last_pointer, tear_point, tear_direction: [2]f32,
	dock_ready: bool,
	moved, detach_failed: bool,
}

create_notebook :: proc(app: ^Showcase, ui: ^fluid.UI) {
	n := &app.notebook
	n.owner = app
	window := ui.window
	allocator := os.heap_allocator()
	seeds := [Site][2]string{
		.North = {"Tagged three shoots on the north path.", "Leaf litter still damp."},
		.Creek = {"Water reached the lower trail marker overnight.", "Raised the light sensor above the ferns."},
		.Ridge = {"New shoots on the upper slope.", "Soil dry by 09:00. Check again tomorrow."},
	}
	for &journal, site in n.journals {
		journal.entries = make([dynamic]Note, 0, 8, allocator)
		for entry, index in seeds[site] {
			sample := app.telemetry.sample - (11 - index * 8 + int(site)) * SAMPLES_PER_DAY + index * 1370
			append(&journal.entries, Note{strings.clone(entry, allocator), sample})
		}
	}
	for side in Dock_Side {
		n.hints[side] = fluid.create_element(window, {draw = draw_dock_preview, color = {110, 175, 132, 0}})
		fluid.set_pointer_behavior(ui, n.hints[side], .Pass)
		fluid.set_hidden(ui, n.hints[side])
	}
	p := &n.parts
	p[.Surface] = field_panel(window, radius = NOTEBOOK_RADIUS)
	fluid.set_pointer_behavior(ui, p[.Surface], .Block)
	p[.Handle] = fluid.create_element(window, {draggable = true, behavior = {state = n, input = notebook_drag_input}})
	p[.Grip] = field_text(window, "⋮⋮", 0.95, LIME, .Bold)
	p[.Title] = field_text(window, "Notebook", 1.1, INK, .Bold)
	p[.List] = create_notebook_list(n, ui)
	p[.List_Input] = fluid.create_element(window, {
		focusable = true, behavior = {state = n, input = note_list_input},
	})
	p[.Editor_Title] = field_text(window, "", TEXT_BODY, INK, .Bold)
	p[.Editor] = field_control(window, elements.text_area(window, {}, "", ""), TEXT_BODY)
	fluid.set_color(ui, p[.Editor], INSET)
	p[.Feedback] = field_text(window, "", TEXT_SMALL, HONEY)
	p[.New] = field_button(window, "+", .Secondary)
	fluid.set_text_style(ui, p[.New], 1.5, INK, .Center)
	p[.Reading] = field_button(window, "Show on chart", .Secondary)
	fluid.on_press(ui, p[.Reading], n, inspect_entry_reading)
	n.arriving_text = field_text(window, "")
	fluid.set_text_wrap(ui, n.arriving_text)
	n.save = field_button(window, "")
	style_save(n, ui)

	elements.on_change(ui, p[.Editor], n, edit_entry)
	fluid.on_press(ui, p[.New], n, new_note)
}

destroy_notebook :: proc(n: ^Notebook) {
	allocator := os.heap_allocator()
	for journal in n.journals {
		for entry in journal.entries {
			delete(entry.text, allocator)
		}
		delete(journal.entries)
		delete(journal.draft, allocator)
		delete(journal.edit_text, allocator)
	}
}

refresh_notebook :: proc(app: ^Showcase, ui: ^fluid.UI) {
	n := &app.notebook
	if n.site != app.site {
		n.site = app.site
		n.arriving = false
		reset_notebook_list(n, ui)
	}
	refresh_journal(n, ui)
}

refresh_journal :: proc(n: ^Notebook, ui: ^fluid.UI) {
	journal := &n.journals[n.site]
	p := &n.parts
	fluid.set_label(ui, p[.Feedback], "")
	editing := journal.edit != nil
	fluid.set_label(ui, p[.Editor_Title], editing ? "Edit saved note" : "Write a note")
	fluid.set_label(ui, n.save, editing ? "Save changes" : "Save note")
	fluid.set_hidden(ui, p[.Reading], !editing)
	elements.set_text_value(ui, p[.Editor], editing ? journal.edit_text : journal.draft)
}

edit_entry :: proc(n: ^Notebook, ui: ^fluid.UI, change: elements.Control_Change) {
	journal := &n.journals[n.site]
	text := journal.edit != nil ? &journal.edit_text : &journal.draft
	allocator := os.heap_allocator()
	next := strings.clone(change.value.(string), allocator)
	delete(text^, allocator)
	text^ = next
	elements.set_text_value(ui, change.id, next)
	fluid.set_label(ui, n.parts[.Feedback], "")
}

new_note :: proc(n: ^Notebook, ui: ^fluid.UI, id: fluid.Element_ID) {
	clear_entry_edit(&n.journals[n.site])
	refresh_journal(n, ui)
	fluid.focus(ui, n.parts[.Editor])
}

inspect_entry_reading :: proc(n: ^Notebook, ui: ^fluid.UI, id: fluid.Element_ID) {
	journal := &n.journals[n.site]
	if index, ok := journal.edit.?; ok {
		n.owner.panels.settings_open = false
		n.owner.panels.card_open = false
		open_reading(&n.owner.telemetry, ui, journal.entries[index].sample)
	}
}

clear_entry_edit :: proc(journal: ^Station_Journal) {
	delete(journal.edit_text, os.heap_allocator())
	journal.edit_text = ""
	journal.edit = nil
}

commit_entry :: proc(n: ^Notebook, ui: ^fluid.UI, id: fluid.Element_ID) {
	journal := &n.journals[n.site]
	index, editing := journal.edit.?
	text := strings.trim_space(editing ? journal.edit_text : journal.draft)
	if text == "" {
		fluid.set_label(ui, n.parts[.Feedback], "Enter a note.")
		fluid.focus(ui, n.parts[.Editor])
		return
	}
	allocator := os.heap_allocator()
	entry := strings.clone(text, allocator)
	if editing {
		delete(journal.entries[index].text, allocator)
		journal.entries[index].text = entry
		release_note_list_graphics(n)
		clear_entry_edit(journal)
		refresh_journal(n, ui)
		fluid.set_label(ui, n.parts[.Feedback], "Changes saved")
		return
	}

	append(&journal.entries, Note{entry, displayed_sample(&n.owner.telemetry)})
	editor := fluid.bounds(ui, n.parts[.Editor])
	panel := fluid.bounds(ui, n.parts[.Surface])
	n.arriving = true
	fluid.set_label(ui, n.arriving_text, note_preview(fluid.element_window(ui, id), entry, NOTEBOOK_WIDTH - 8))
	fluid.bring_to_front(ui, n.arriving_text)
	fluid.set_layout(ui, n.arriving_text, {editor.left + 0.6, editor.top + 0.5, editor.right - 0.5, editor.top + 2.2})
	fluid.animate_to(ui, n.arriving_text, note_arrival_target(n, panel), damped_animation(0.46))
	delete(journal.draft, allocator)
	journal.draft = ""
	reset_notebook_list(n, ui)

	refresh_journal(n, ui)
	fluid.focus(ui, n.parts[.Editor])
}

style_save :: proc(n: ^Notebook, ui: ^fluid.UI) {
	id := n.save
	fluid.set_hidden(ui, id, false)
	fluid.set_pointer_behavior(ui, id, .Auto)
	fluid.set_color(ui, id, {54, 80, 62, 255})
	fluid.set_text_style(ui, id, TEXT_SMALL, INK, .Center, .Bold)
	fluid.set_draw(ui, id, draw_save)
	fluid.on_press(ui, id, n, commit_entry)
}

draw_save :: proc(view: fluid.Element_View) {
	frame := view
	if view.hovered {
		frame.color = {76, 101, 77, 255}
	}
	frame.style.focus_border = INK
	elements.draw_default(frame)
}

notebook_layout :: proc(n: ^Notebook, r: fluid.Pins) -> [Notebook_Part]fluid.Pins {
	x, right := r.left + 0.9, r.right - 0.9
	y, w := r.top, fluid.width(r) - 1.8
	layout: [Notebook_Part]fluid.Pins
	layout[.Surface] = r
	layout[.Handle] = fluid.rect(r.left, y, fluid.width(r), 3.2)
	layout[.Grip] = fluid.rect(x, y + 0.6, 0.85, 2)
	layout[.Title] = fluid.rect(x + 1.1, y + 0.58, w - 1.1, 2)
	count := len(n.journals[n.site].entries)
	list_height := 1.08 + NOTE_ROW_HEIGHT * f32(min(count, 6))
	layout[.List] = fluid.rect(x - 0.5, y + 3.05, w + 1, list_height)
	layout[.List_Input] = note_content_pins(layout[.List])
	cursor := layout[.List].bottom + 0.85
	layout[.Editor_Title] = fluid.rect(x, cursor, w - 5.3, 1.4)
	layout[.New] = fluid.rect(right - 2, y + 0.6, 2, 2)
	layout[.Editor] = {x, cursor + 1.8, right, r.bottom - 5.05}
	layout[.Feedback] = fluid.rect(x, r.bottom - 4.85, w, 1.1)
	layout[.Reading] = fluid.rect(x, r.bottom - 3.24, 7.3, 2.3)
	return layout
}

note_arrival_target :: proc(n: ^Notebook, panel: fluid.Pins) -> fluid.Pins {
	list := note_content_pins(notebook_layout(n, panel)[.List])
	return fluid.rect(list.left + 0.45, list.top + 0.47, fluid.width(list) - NOTE_STAMP_WIDTH, 1.4)
}

save_pins :: proc(panel: fluid.Pins) -> fluid.Pins {
	return fluid.rect(panel.right - 7.5, panel.bottom - 3.24, 6.6, 2.3)
}

notebook_drag_input :: proc(state: rawptr, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Element_Event) -> bool {
	if pointer, ok := event.(fluid.Pointer_Event); ok && pointer.kind == .Down {
		n := cast(^Notebook)state
		r := fluid.bounds(ui, id)
		n.grab = pointer.point - {r.left, r.top}
		owner := fluid.element_window(ui, id)
		n.last_pointer = fluid.window_point(ui.window, fluid.desktop_point(owner, pointer.point))
	}
	return false
}

update_notebook :: proc(app: ^Showcase, ui: ^fluid.UI, area: fluid.Pins, dt: f64) {
	n := &app.notebook
	n.area = area
	p := &n.parts
	handle := p[.Handle]
	dropped := fluid.dropped(ui, handle)
	dragging := fluid.dragging(ui, handle)

	if n.window != nil && n.window.close_requested {
		dock_notebook(n, ui, n.side)
		dragging, dropped = false, false
	}
	if fluid.drag_started(ui, handle) {
		n.moved, n.detach_failed = false, false
		n.dock_ready = n.window != nil
		for id in n.hints {
			fluid.bring_to_front(ui, id)
		}
		raise_notebook(n, ui)
	}
	inside: bool
	side: Dock_Side
	if dragging || dropped {
		// The engine applies the release event to the handle before dispatching
		// updates. Read that layout so a quick drop still uses its final point.
		owner := fluid.element_window(ui, handle)
		r := fluid.bounds(ui, handle)
		grab_point := [2]f32{r.left, r.top} + n.grab
		mouse := fluid.window_point(ui.window, fluid.desktop_point(owner, grab_point))
		position := mouse - n.grab
		size := NOTEBOOK_FLOAT_SIZE
		if n.window != nil {
			floating := fluid.bounds(ui, n.window.viewport)
			size = {fluid.width(floating), fluid.height(floating)}
		}
		preview := fluid.rect(position.x, position.y, size.x, size.y)
		native := fluid.bounds(ui, ui.window.viewport)
		fits := preview.left >= native.left && preview.top >= native.top &&
			preview.right <= native.right && preview.bottom <= native.bottom
		in_workspace := fluid.contains({native.left, area.top, native.right, native.bottom}, mouse)
		side = mouse.x < (area.left + area.right) / 2 ? .Left : .Right
		if n.window != nil && !n.dock_ready {
			offset := mouse - n.tear_point
			inward := offset.x * n.tear_direction.x + offset.y * n.tear_direction.y
			n.dock_ready = !in_workspace || inward < -0.5
		}
		inside = in_workspace && (n.window == nil || n.dock_ready)
		delta := mouse - n.last_pointer
		n.moved = n.moved || abs(delta.x) + abs(delta.y) > 0.025
		if n.moved {
			if n.window == nil {
				fluid.set_layout(ui, p[.Surface], preview)
				if !fits && !n.detach_failed {
					n.detach_failed = !float_notebook(n, ui, position)
					if !n.detach_failed {
						// This gesture can tear off while the cursor is still in the
						// window. Arm docking once the cursor starts coming back.
						n.tear_point = mouse
						n.tear_direction = {
							preview.left < native.left ? -1 : preview.right > native.right ? 1 : 0,
							preview.top < native.top ? -1 : preview.bottom > native.bottom ? 1 : 0,
						}
						n.dock_ready = !in_workspace || side != n.side
						inside = in_workspace && n.dock_ready
					}
				}
			} else if mouse != n.last_pointer {
				window_offset := n.grab * (fluid.window_scale(n.window) / fluid.UI_UNIT_POINTS)
				_ = fluid.set_window_position(n.window, fluid.desktop_point(ui.window, mouse) - window_offset)
			}
		}
		n.last_pointer = mouse
		if dropped && n.moved {
			if inside {
				dock_notebook(n, ui, side)
			} else if n.window == nil {
				dock_notebook(n, ui, n.side)
			}
		}
	}
	for hint_side in Dock_Side {
		id := n.hints[hint_side]
		active := dragging && n.moved && inside && side == hint_side
		progress := &n.hint_progress[hint_side]
		progress^ = clamp(progress^ + f32(dt) * (active ? 3.25 : -7), 0, 1)
		opacity := smoothstep(clamp((progress^ - 0.22) / 0.78, 0, 1))
		fluid.set_hidden(ui, id, opacity == 0)
		fluid.set_color(ui, id, {110, 175, 132, u8(160 * opacity)})
		fluid.set_layout(ui, id, dock_pins(area, hint_side))
	}

	if n.window != nil {
		fluid.set_layout(ui, p[.Surface], fluid.bounds(ui, n.window.viewport))
	} else if !dragging || !n.moved {
		fluid.set_target(ui, p[.Surface], dock_pins(area, n.side))
	}
	panel := fluid.bounds(ui, p[.Surface])
	layout := notebook_layout(n, panel)
	for part in Notebook_Part {
		if part != .Surface {
			fluid.set_layout(ui, p[part], layout[part])
		}
	}
	set_notebook_list_content(n, ui)
	fluid.set_layout(ui, n.save, save_pins(panel))
	if n.arriving {
		target := note_arrival_target(n, panel)
		fluid.set_target(ui, n.arriving_text, target)
		n.arriving = fluid.bounds(ui, n.arriving_text) != target
	}
	if !n.arriving {
		fluid.set_layout(ui, n.arriving_text, {})
	}
}

raise_notebook :: proc(n: ^Notebook, ui: ^fluid.UI) {
	for id in n.parts {
		fluid.bring_to_front(ui, id)
	}
	fluid.bring_to_front(ui, n.save)
}

draw_dock_preview :: proc(view: fluid.Element_View) {
	scale := fluid.pixel_scale(view.window)
	pixels := fluid.pixel_rect(view.pins, scale)
	tint := view.color
	tint.a /= 4
	fluid.rounded_fill(view.window.renderer, pixels, NOTEBOOK_RADIUS * scale, tint)
	fluid.rounded_outline(view.window.renderer, pixels, NOTEBOOK_RADIUS * scale, 0.075 * scale,
		{147, 221, 169, view.color.a})
}

dock_pins :: proc(area: fluid.Pins, side: Dock_Side) -> fluid.Pins {
	x := side == .Left ? area.left : area.right - NOTEBOOK_WIDTH
	return fluid.rect(x, area.top, NOTEBOOK_WIDTH, fluid.height(area))
}

float_notebook :: proc(n: ^Notebook, ui: ^fluid.UI, position: [2]f32) -> bool {
	window := fluid.create_window(ui, {
		title = "Notebook", size = NOTEBOOK_FLOAT_SIZE, minimum_size = NOTEBOOK_FLOAT_SIZE,
		flags = {.Hidden, .Borderless, .Transparent}, background = EDGE, text_color = INK,
	})
	if window != nil {
		if fluid.set_window_position(window, fluid.desktop_point(ui.window, position)) &&
		   fluid.set_window_clip(window, {nil, write_notebook_mask}) && fluid.show_window(window) {
			n.window = window
			transfer_notebook(n, ui, window)
			return true
		}
		fluid.close_window(window)
	}
	fluid.set_label(ui, n.parts[.Feedback], "Could not open the notebook window.")
	return false
}

write_notebook_mask :: proc(_: rawptr, pixels: []u8, size: [2]i32, scale: f32) {
	radius := min(NOTEBOOK_RADIUS * scale, f32(min(size.x, size.y)) / 2)
	for y in 0..<size.y {
		dy := max(0, radius - (f32(min(y, size.y - 1 - y)) + 0.5))
		inset := radius - math.sqrt(max(0, radius * radius - dy * dy))
		margin := i32(math.ceil(inset - 0.5))
		offset := int(y) * int(size.x)
		for &pixel in pixels[offset + int(margin):offset + int(size.x - margin)] {
			pixel = 255
		}
	}
}

dock_notebook :: proc(n: ^Notebook, ui: ^fluid.UI, side: Dock_Side) {
	n.side = side
	if n.window != nil {
		transfer_notebook(n, ui, ui.window)
		fluid.close_window(n.window)
		n.window = nil
	}
	fluid.animate_to(ui, n.parts[.Surface], dock_pins(n.area, side), damped_animation(0.34))
}

transfer_notebook :: proc(n: ^Notebook, ui: ^fluid.UI, window: ^fluid.Window) {
	for id in n.parts {
		fluid.transfer(ui, id, window)
	}
	fluid.transfer(ui, n.save, window)
	fluid.transfer(ui, n.arriving_text, window)
}
