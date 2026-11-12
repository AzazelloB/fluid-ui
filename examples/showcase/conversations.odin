package main

import "core:fmt"
import fluid "../.."

Conversation :: struct {
	element:  fluid.Element_ID,
	arriving: bool,
}

Conversations :: struct {
	scene: ^fluid.Scene,
	sidebar, heading, area, empty_hint: fluid.Element_ID,
	items: [dynamic]Conversation,
	send_button: fluid.Element_ID,
}

create_conversations :: proc(page: ^Conversations, ui: ^fluid.UI, navigation: fluid.Element_ID) {
	page.scene = fluid.create_scene(ui)
	page.items = make([dynamic]Conversation, 0, 16)
	page.sidebar = fluid.panel(page.scene,
		{fluid.relative(ui.viewport, .Right, -260), fluid.at(0)},
		{fluid.at(260), fluid.relative(ui.viewport, .Height)}, {32, 35, 43, 255},
	)
	page.heading = fluid.label(page.scene,
		{fluid.relative(page.sidebar, .Left, 16), fluid.relative(page.sidebar, .Top, 20)},
		{fluid.relative(page.sidebar, .Width, -32), fluid.at(28)}, "Conversations",
	)
	page.empty_hint = fluid.label(page.scene,
		{fluid.relative(page.sidebar, .Left, 16), fluid.relative(page.heading, .Bottom, 16)},
		{fluid.relative(page.sidebar, .Width, -32), fluid.at(44)}, "Nothing here yet",
	)
	page.area = fluid.panel(page.scene,
		{fluid.relative(navigation, .Right), fluid.at(0)},
		{fluid.distance(navigation, .Right, page.sidebar, .Left), fluid.relative(ui.viewport, .Height)},
		{24, 26, 32, 255},
	)
	_ = fluid.label(page.scene,
		{fluid.relative(page.area, .Left, 24), fluid.relative(page.area, .Top, 40)},
		{fluid.relative(page.area, .Width, -48), fluid.at(32)}, "Message to conversation",
	)
	_ = fluid.label(page.scene,
		{fluid.relative(page.area, .Left, 24), fluid.relative(page.area, .Top, 78)},
		{fluid.relative(page.area, .Width, -48), fluid.at(28)}, "Press the button below",
	)
	create_send_button(page, ui)
}

create_send_button :: proc(page: ^Conversations, ui: ^fluid.UI) {
	id := fluid.button(page.scene,
		{fluid.relative(page.area, .Left, 24), fluid.relative(page.area, .Bottom, 8)},
		{fluid.relative(page.area, .Width, -48), fluid.at(56)}, "Create conversation",
	)
	fluid.set_color(ui, id, {47, 99, 165, 255})
	fluid.animate_to(ui, id,
		{fluid.relative(page.area, .Left, 24), fluid.relative(page.area, .Bottom, -80)},
		{fluid.relative(page.area, .Width, -48), fluid.at(56)}, entry_animation(),
	)
	page.send_button = id
}

send_message :: proc(page: ^Conversations, ui: ^fluid.UI) {
	id := page.send_button
	inject_at(&page.items, 0, Conversation{element = id, arriving = true})
	items := page.items[:]
	// Retarget bottom-up to preserve the current starting positions.
	for i := len(items) - 1; i > 0; i -= 1 {
		animation := stack_animation()
		if items[i].arriving {
			animation = flight_animation()
			animation.duration = fluid.animation_remaining(ui, items[i].element)
		}
		fluid.animate_to(ui, items[i].element,
			{fluid.relative(page.sidebar, .Left, 16), fluid.relative(items[i - 1].element, .Bottom, 10, target = true)},
			{fluid.relative(page.sidebar, .Width, -32), fluid.at(44)}, animation,
		)
	}
	// set_label retains a copy, so this formatted string can be temporary.
	fluid.set_label(ui, id, fmt.tprintf("Conversation %d", len(items)))
	if len(items) == 1 { fluid.remove(ui, page.empty_hint) }
	fluid.animate_to(ui, id,
		{fluid.relative(page.sidebar, .Left, 16), fluid.relative(page.heading, .Bottom, 16)},
		{fluid.relative(page.sidebar, .Width, -32), fluid.at(44)}, flight_animation(),
	)
	create_send_button(page, ui)
}

select_conversation :: proc(page: ^Conversations, ui: ^fluid.UI, id: fluid.Element_ID) {
	for item in page.items { fluid.set_selected(ui, item.element, item.element == id) }
}

update_conversations :: proc(page: ^Conversations, ui: ^fluid.UI) {
	// Finish oldest first so the newest arrival wins selection in a shared frame.
	for i := len(page.items) - 1; i >= 0; i -= 1 {
		item := &page.items[i]
		if item.arriving && fluid.animation_finished(ui, item.element) {
			item.arriving = false
			fluid.set_color(ui, item.element, {48, 54, 66, 255})
			select_conversation(page, ui, item.element)
		}
	}
	if fluid.pressed(ui, page.send_button) { send_message(page, ui) }
	for item in page.items {
		if !item.arriving && fluid.pressed(ui, item.element) {
			select_conversation(page, ui, item.element)
		}
	}
}
