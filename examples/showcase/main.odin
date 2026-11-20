package main

import "core:os"
import fluid "../.."

main :: proc() {
	app := Showcase{controls = {size_index = 1, number_value = 42, price_value = 25, pixels_value = 16}}
	defer {
		allocator := os.heap_allocator()
		delete(app.controls.name_value.? or_else "", allocator)
		delete(app.controls.notes_value.? or_else "", allocator)
		delete(app.conversations.draft, allocator)
		for title in app.conversations.titles {
			delete(title, allocator)
		}
	}
	fluid.run({
		title = SHOWCASE_TITLE,
		size = {62.5, 43.75 + TITLE_BAR_HEIGHT},
		minimum_size = {56.25, 33.75 + TITLE_BAR_HEIGHT},
		flags = {.Transparent, .Custom_Title_Bar},
		background = WINDOW_BACKGROUND, text_color = WINDOW_TEXT,
	}, &app, create_showcase)
}
