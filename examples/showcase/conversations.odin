package main

import fluid "../.."

Conversation :: struct {
	element:  fluid.Element_ID,
	arriving: bool,
}

Conversations :: struct {
	scene:                              ^fluid.Scene,
	sidebar, heading, area, empty_hint: fluid.Element_ID,
	items:                              [dynamic]Conversation,
	sent:                               int,
}

create_conversations :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	navigation := app.sidebar
	page := &app.conversations
	page.scene = fluid.create_scene(ui.window)
	append(&entry.scenes, page.scene)
	page.items = make([dynamic]Conversation, 0, 16)
	left := fluid.relative(navigation, .Right, 36)
	page.sidebar = demo_surface(page.scene,
		{fluid.relative(ui.window.viewport, .Right, -300), fluid.at(24)},
		{fluid.at(264), fluid.relative(ui.window.viewport, .Height, -48)})
	page.heading = demo_text(page.scene,
		{fluid.relative(page.sidebar, .Left, 20), fluid.relative(page.sidebar, .Top, 20)},
		{fluid.relative(page.sidebar, .Width, -40), fluid.at(28)}, "Conversations", .Heading)
	page.empty_hint = demo_text(page.scene,
		{fluid.relative(page.sidebar, .Left, 20), fluid.relative(page.heading, .Bottom, 20)},
		{fluid.relative(page.sidebar, .Width, -40), fluid.at(44)}, "No conversations", .Body, MUTED)
	page.area = demo_surface(page.scene,
		{left, fluid.at(24)},
		{fluid.distance(navigation, .Right, page.sidebar, .Left, -56), fluid.relative(ui.window.viewport, .Height, -48)},
		{21, 30, 41, 255}, radius = 20)
	create_send_button(page, ui)
}

create_send_button :: proc(page: ^Conversations, ui: ^fluid.UI) {
	id := fluid.button(page.scene,
		{fluid.relative(page.area, .Left, 24), fluid.relative(page.area, .Bottom, 8)},
		{fluid.relative(page.area, .Width, -48), fluid.at(56)}, "New conversation",
	)
	fluid.set_color(ui, id, {50, 103, 90, 255})
	fluid.set_style(ui, id, {radius = 12, border = {91, 152, 132, 255}, border_width = 1, shadow = 10})
	fluid.animate_to(ui, id,
		{fluid.relative(page.area, .Left, 24), fluid.relative(page.area, .Bottom, -80)},
		{fluid.relative(page.area, .Width, -48), fluid.at(56)}, {duration = 0.14, sample = smooth_damp, progress = damp_progress},
	)
	fluid.on_press(ui, id, page, send_message)
}

send_message :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	fluid.clear_press(ui, id)
	// Keep the collection within the canvas during repeated demonstrations.
	if len(page.items) == 6 {
		fluid.remove(ui, page.items[5].element)
		pop(&page.items)
	}
	inject_at(&page.items, 0, Conversation{element = id, arriving = true})
	items := page.items[:]
	// Retarget bottom-up to preserve the current starting positions.
	for i := len(items) - 1; i > 0; i -= 1 {
		duration := f64(0.4)
		sample := smooth_damp
		if items[i].arriving {
			sample = arc
			duration = fluid.animation_remaining(ui, items[i].element)
		}
		fluid.retarget(ui, items[i].element,
			{fluid.relative(page.sidebar, .Left, 16), fluid.relative(items[i - 1].element, .Bottom, 10, target = true)},
			{fluid.relative(page.sidebar, .Width, -32), fluid.at(44)}, {duration = duration, sample = sample, progress = damp_progress},
		)
	}
	page.sent += 1
	subjects := [6]string{"Design", "Weekend plans", "Photos", "Project notes", "Lunch", "Reading list"}
	fluid.set_label(ui, id, subjects[(page.sent - 1) % len(subjects)])
	if len(items) == 1 {
		fluid.remove(ui, page.empty_hint)
	}
	fluid.animate_to(ui, id,
		{fluid.relative(page.sidebar, .Left, 16), fluid.relative(page.heading, .Bottom, 16)},
		{fluid.relative(page.sidebar, .Width, -32), fluid.at(44)}, {duration = 0.9, sample = arc, progress = damp_progress},
	)
	fluid.on_complete(ui, id, page, conversation_arrived)
	create_send_button(page, ui)
}

select_conversation :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	for item in page.items {
		fluid.set_selected(ui, item.element, item.element == id)
	}
}

conversation_arrived :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	for &item in page.items {
		if item.element == id {
			item.arriving = false
			break
		}
	}
	fluid.set_color(ui, id, {35, 44, 57, 255})
	fluid.on_press(ui, id, page, select_conversation)
	select_conversation(page, ui, id)
}
