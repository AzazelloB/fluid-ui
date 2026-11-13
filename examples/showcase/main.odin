package main

import fluid "../.."

main :: proc() {
	app: Showcase
	fluid.run({
		title = "Fluid UI",
		size = {1000, 700},
		minimum_size = {900, 540},
		flags = {.TRANSPARENT, .BORDERLESS},
	}, &app, create_showcase)
}
