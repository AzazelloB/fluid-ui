package main

import fluid "../.."

main :: proc() {
	app: Showcase
	fluid.run({
		title = SHOWCASE_TITLE,
		size = {62.5, 43.75 + TITLE_BAR_HEIGHT},
		minimum_size = {56.25, 33.75 + TITLE_BAR_HEIGHT},
		flags = {.Transparent, .Custom_Title_Bar},
	}, &app, create_showcase)
}
