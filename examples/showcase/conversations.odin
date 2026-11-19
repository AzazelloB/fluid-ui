package main

import "core:os"
import "core:strings"
import fluid "../.."
import "../../elements"

Conversations :: struct {
	navigation, sidebar, heading, area, empty_hint: fluid.Element_ID,
	subject_label, subject, send_button: fluid.Element_ID,
	items: [6]fluid.Element_ID,
	titles: [6]string,
	draft: string,
	selected: Maybe(int),
	sent: int,
}

create_conversations :: proc(app: ^Showcase, ui: ^fluid.UI) {
	page := &app.conversations
	page.navigation = app.sidebar
	sidebar, heading, area := conversations_layout(page, ui)
	page.sidebar = demo_surface(ui.window, sidebar)
	page.heading = demo_text(ui.window, heading, "Conversations", .Heading)
	page.empty_hint = demo_text(ui.window, empty_hint_pins(heading), "No conversations", .Body, MUTED)
	page.area = demo_surface(ui.window, area, {21, 30, 41, 255}, radius = 1.25)
	page.subject_label = demo_text(ui.window, {}, "Conversation title", .Caption, MUTED)
	page.subject = elements.text_input(ui.window, {}, page.draft, "Optional title")
	fluid.set_draw(ui, page.subject, demo_field_style)
	elements.on_change(ui, page.subject, page, set_conversation_subject)
	layout_composer(page, ui, area)
	for title, index in page.titles[:min(page.sent, len(page.titles))] {
		id := elements.button(ui.window, conversation_pins(sidebar, heading, index), title, .Secondary)
		page.items[index] = id
		style_conversation(page, ui, id, title, sidebar, heading)
		fluid.set_selected(ui, id, page.selected == index)
	}
	if page.sent > 0 {
		fluid.remove(ui, page.empty_hint)
	}
	create_send_button(page, ui)
	fluid.on_update(ui, page.sidebar, page, update_conversations)
}

leave_conversations :: proc(app: ^Showcase, ui: ^fluid.UI) {
	page := &app.conversations
	for id in ([]fluid.Element_ID{page.sidebar, page.heading, page.area, page.empty_hint, page.subject_label, page.subject, page.send_button}) {
		if fluid.valid(ui, id) {
			fluid.remove(ui, id)
		}
	}
	for id in page.items[:min(page.sent, len(page.items))] {
		fluid.remove(ui, id)
	}
}

send_button_pins :: proc(area: fluid.Pins) -> fluid.Pins {
	return {left = area.right - 12.5, top = area.bottom - 4, right = area.right - 1.5, bottom = area.bottom - 1.5}
}

layout_composer :: proc(page: ^Conversations, ui: ^fluid.UI, area: fluid.Pins) {
	send := send_button_pins(area)
	x := area.left + 1.5
	right := send.left - 0.5
	fluid.set_target(ui, page.subject_label, {x, send.top - 1.5, right, send.top})
	fluid.set_target(ui, page.subject, {x, send.top, right, send.bottom})
}

set_conversation_subject :: proc(page: ^Conversations, ui: ^fluid.UI, change: elements.Control_Change) {
	allocator := os.heap_allocator()
	next := strings.clone(change.value.(string), allocator)
	delete(page.draft, allocator)
	page.draft = next
	elements.set_text_value(ui, change.id, next)
}

conversation_pins :: proc(sidebar, heading: fluid.Pins, index: int) -> fluid.Pins {
	top := heading.bottom + 1 + f32(index) * 3.375
	return {left = sidebar.left + 1, top = top, right = sidebar.right - 1, bottom = top + 2.75}
}

conversations_layout :: proc(page: ^Conversations, ui: ^fluid.UI) -> (sidebar, heading, area: fluid.Pins) {
	viewport := showcase_body(ui)
	content := content_pins(ui, page.navigation, viewport)
	sidebar = {left = viewport.right - 18.75, top = content.top, right = content.right, bottom = content.bottom}
	heading = {left = sidebar.left + 1.25, top = sidebar.top + 1.25, right = sidebar.right - 1.25, bottom = sidebar.top + 3}
	area = content
	area.right = sidebar.left - 1.25
	return
}

empty_hint_pins :: proc(heading: fluid.Pins) -> fluid.Pins {
	return {left = heading.left, top = heading.bottom + 1.25, right = heading.right, bottom = heading.bottom + 4}
}

update_conversations :: proc(page: ^Conversations, ui: ^fluid.UI, dt: f64) {
	sidebar, heading, area := conversations_layout(page, ui)
	fluid.set_target(ui, page.sidebar, sidebar)
	fluid.set_target(ui, page.heading, heading)
	fluid.set_target(ui, page.area, area)
	if fluid.valid(ui, page.empty_hint) {
		fluid.set_target(ui, page.empty_hint, empty_hint_pins(heading))
	}
	layout_composer(page, ui, area)
	fluid.set_target(ui, page.send_button, send_button_pins(area))
	for item, index in page.items[:min(page.sent, len(page.items))] {
		fluid.set_target(ui, item, conversation_pins(sidebar, heading, index))
	}
}

create_send_button :: proc(page: ^Conversations, ui: ^fluid.UI) {
	area := fluid.bounds(ui, page.area)
	send := send_button_pins(area)
	id := elements.button(ui.window, fluid.translated(send, {0, 4}), "New conversation")
	fluid.set_color(ui, id, {50, 103, 90, 255})
	fluid.set_style(ui, id, {radius = 0.75, border = {91, 152, 132, 255}, border_width = 0.0625, shadow = 0.625})
	page.send_button = id
	fluid.animate_to(ui, id, send_button_pins(area), damped_animation(0.14))
	fluid.on_press(ui, id, page, send_message)
}

send_message :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	if page.sent >= len(page.items) {
		fluid.remove(ui, page.items[len(page.items) - 1])
		delete(page.titles[len(page.titles) - 1], os.heap_allocator())
	}
	for index := min(page.sent, len(page.items) - 1); index > 0; index -= 1 {
		page.items[index] = page.items[index - 1]
		page.titles[index] = page.titles[index - 1]
	}
	page.items[0] = id
	sidebar := fluid.bounds(ui, page.sidebar)
	heading := fluid.bounds(ui, page.heading)
	page.sent += 1
	for index in 1..<min(page.sent, len(page.items)) {
		fluid.animate_to(ui, page.items[index], conversation_pins(sidebar, heading, index),
			damped_animation(0.4))
	}
	subjects := [6]string{"Design", "Weekend plans", "Photos", "Project notes", "Lunch", "Reading list"}
	if page.draft == "" {
		page.titles[0] = strings.clone(subjects[(page.sent - 1) % len(subjects)], os.heap_allocator())
	} else {
		page.titles[0] = page.draft
		page.draft = ""
	}
	elements.set_text_value(ui, page.subject, "")
	if page.sent == 1 {
		fluid.remove(ui, page.empty_hint)
	}
	fluid.set_label(ui, id, page.titles[0])
	style_conversation(page, ui, id, page.titles[0], sidebar, heading)
	select_conversation(page, ui, id)
	fluid.animate_to(ui, id, conversation_pins(sidebar, heading, 0),
		damped_animation(0.9, arc))
	create_send_button(page, ui)
}

style_conversation :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID, title: string, sidebar, heading: fluid.Pins) {
	title_width, _ := fluid.measure_text(ui.window, title)
	fluid.set_text_wrap(ui, id, title_width > fluid.width(conversation_pins(sidebar, heading, 0)))
	fluid.set_color(ui, id, {35, 44, 57, 255})
	fluid.set_style(ui, id, {radius = 0.75, border = {91, 152, 132, 255}, border_width = 0.0625, shadow = 0.625})
	elements.set_button_variant(ui, id, .Secondary)
	fluid.on_press(ui, id, page, select_conversation)
}

select_conversation :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	for item, index in page.items[:min(page.sent, len(page.items))] {
		if item == id {
			page.selected = index
		}
		fluid.set_selected(ui, item, item == id)
	}
}
