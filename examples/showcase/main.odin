package main

import fluid "../.."

main :: proc() {
	app: Showcase
	fluid.run({
		title = "Fluid UI",
		size = {62.5, 43.75},
		minimum_size = {56.25, 33.75},
		flags = {.TRANSPARENT, .BORDERLESS},
	}, &app, create_showcase)
}
