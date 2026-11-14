package main

import fluid "../.."

Rectangles :: struct {
	scene: ^fluid.Scene,
	stage, anchor, toggle: fluid.Element_ID,
	shifted: bool,
}

create_rectangles :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.rectangles
	page.scene = fluid.create_scene(ui.window)
	append(&entry.scenes, page.scene)
	scene := page.scene
	left := fluid.relative(app.sidebar, .Right, 36)
	width := fluid.distance(app.sidebar, .Right, ui.window.viewport, .Right, -72)
	page.stage = demo_surface(scene, {left, fluid.at(24)},
		{width, fluid.relative(ui.window.viewport, .Height, -48)}, radius = 20)
	page.toggle = fluid.button(scene,
		{fluid.relative(page.stage, .Right, -124), fluid.relative(page.stage, .Top, 20)},
		{fluid.at(104), fluid.at(36)}, "Move")
	fluid.on_press(ui, page.toggle, page, shift_anchor)

	// The anchor alone is animated. Every other position/size reads a live reference.
	page.anchor = demo_surface(scene,
		{fluid.relative(page.stage, .Left, 28), fluid.relative(page.stage, .Top, 100)},
		{fluid.at(184), fluid.at(136)}, {41, 83, 75, 255}, radius = 14, shadow = 12)
	fluid.set_style(ui, page.anchor, {radius = 14, border = {106, 179, 156, 255}, border_width = 1, shadow = 12})
	// The far edge is independently attached to the stage, not to the source card.
	right_x := fluid.relative(page.stage, .Right, -244)
	_ = demo_surface(scene, {right_x, fluid.relative(page.anchor, .Top)},
		{fluid.at(216), fluid.at(56)}, {29, 47, 53, 255}, radius = 10)
	_ = demo_surface(scene, {right_x, fluid.relative(page.anchor, .Bottom, -56)},
		{fluid.at(216), fluid.at(56)}, {42, 41, 53, 255}, radius = 10)
	// A distant bar shares the anchor's width.
	bar := demo_surface(scene,
		{fluid.relative(page.stage, .Left, 28), fluid.relative(page.stage, .Bottom, -38)},
		{fluid.relative(page.anchor, .Width), fluid.at(10)}, {143, 225, 196, 255}, radius = 5)
	fluid.set_style(ui, bar, {radius = 5})
}

shift_anchor :: proc(page: ^Rectangles, ui: ^fluid.UI, id: fluid.Element_ID) {
	page.shifted = !page.shifted
	fluid.animate_to(ui, page.anchor,
		{fluid.relative(page.stage, .Left, 28), fluid.relative(page.stage, .Top, page.shifted ? 200 : 100)},
		{fluid.at(page.shifted ? 224 : 184), fluid.at(136)},
		{duration = 0.65, sample = smooth_damp, progress = damp_progress})
	fluid.set_label(ui, id, page.shifted ? "Reset" : "Move")
}
