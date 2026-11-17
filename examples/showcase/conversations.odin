package main

import fluid "../.."

Conversations :: struct {
	scene: ^fluid.Scene,
	navigation, sidebar, heading, area, empty_hint: fluid.Element_ID,
	send_button: fluid.Element_ID,
	items: [dynamic]fluid.Element_ID,
	sent: int,
}

create_conversations :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.conversations
	page.navigation = app.sidebar
	page.scene = fluid.create_scene(ui.window)
	append(&entry.scenes, page.scene)
	page.items = make([dynamic]fluid.Element_ID, 0, 16)
	sidebar, heading, area := conversations_layout(page, ui)
	page.sidebar = demo_surface(page.scene, sidebar)
	page.heading = demo_text(page.scene, heading, "Conversations", .Heading)
	page.empty_hint = demo_text(page.scene, empty_hint_pins(heading), "No conversations", .Body, MUTED)
	page.area = demo_surface(page.scene, area, {21, 30, 41, 255}, radius = 1.25)
	create_send_button(page, ui)
	fluid.on_update(ui, page.sidebar, page, update_conversations)
}

send_button_pins :: proc(area: fluid.Pins) -> fluid.Pins {
	return {left = area.left + 1.5, top = area.bottom - 5, right = area.right - 1.5, bottom = area.bottom - 1.5}
}

conversation_pins :: proc(sidebar, heading: fluid.Pins, index: int) -> fluid.Pins {
	top := heading.bottom + 1 + f32(index) * 3.375
	return {left = sidebar.left + 1, top = top, right = sidebar.right - 1, bottom = top + 2.75}
}

conversations_layout :: proc(page: ^Conversations, ui: ^fluid.UI) -> (sidebar, heading, area: fluid.Pins) {
	viewport := fluid.bounds(ui, ui.window.viewport)
	navigation := fluid.bounds(ui, page.navigation)
	sidebar = {left = viewport.right - 18.75, top = 1.5, right = viewport.right - 2.25, bottom = viewport.bottom - 1.5}
	heading = {left = sidebar.left + 1.25, top = sidebar.top + 1.25, right = sidebar.right - 1.25, bottom = sidebar.top + 3}
	area = {left = navigation.right + 2.25, top = sidebar.top, right = sidebar.left - 1.25, bottom = sidebar.bottom}
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
	fluid.set_target(ui, page.send_button, send_button_pins(area))
	for item, index in page.items {
		fluid.set_target(ui, item, conversation_pins(sidebar, heading, index))
	}
}

create_send_button :: proc(page: ^Conversations, ui: ^fluid.UI) {
	area := fluid.bounds(ui, page.area)
	id := fluid.button(page.scene, {
		left = area.left + 1.5, top = area.bottom + 0.5, right = area.right - 1.5, bottom = area.bottom + 4,
	}, "New conversation")
	fluid.set_color(ui, id, {50, 103, 90, 255})
	fluid.set_style(ui, id, {radius = 0.75, border = {91, 152, 132, 255}, border_width = 0.0625, shadow = 0.625})
	page.send_button = id
	fluid.animate_to(ui, id, send_button_pins(area), {duration = 0.14, sample = smooth_damp, progress = damp_progress})
	fluid.on_press(ui, id, page, send_message)
}

send_message :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	if len(page.items) == 6 {
		fluid.remove(ui, page.items[5])
		pop(&page.items)
	}
	inject_at(&page.items, 0, id)
	sidebar := fluid.bounds(ui, page.sidebar)
	heading := fluid.bounds(ui, page.heading)
	for item, index in page.items[1:] {
		fluid.animate_to(ui, item, conversation_pins(sidebar, heading, index + 1),
			{duration = 0.4, sample = smooth_damp, progress = damp_progress})
	}
	page.sent += 1
	subjects := [6]string{"Design", "Weekend plans", "Photos", "Project notes", "Lunch", "Reading list"}
	fluid.set_label(ui, id, subjects[(page.sent - 1) % len(subjects)])
	if len(page.items) == 1 { fluid.remove(ui, page.empty_hint) }
	fluid.set_color(ui, id, {35, 44, 57, 255})
	fluid.on_press(ui, id, page, select_conversation)
	select_conversation(page, ui, id)
	fluid.animate_to(ui, id, conversation_pins(sidebar, heading, 0),
		{duration = 0.9, sample = arc, progress = damp_progress})
	create_send_button(page, ui)
}

select_conversation :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	for item in page.items { fluid.set_selected(ui, item, item == id) }
}
