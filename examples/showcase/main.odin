package main

import fluid "../.."

main :: proc() {
	app := Showcase{}
	defer destroy_notebook(&app.notebook)
	fluid.run({
		title = SHOWCASE_TITLE,
		size = {73, 46.5 + TITLE_BAR_HEIGHT},
		minimum_size = {61, 38.5 + TITLE_BAR_HEIGHT},
		flags = {.Transparent, .Custom_Title_Bar},
		background = WINDOW_BACKGROUND, text_color = INK,
	}, &app, create_showcase)
}
