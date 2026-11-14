package main

import fluid "../.."

Rectangles :: struct {
	scene: ^fluid.Scene,
	navigation, stage, anchor, toggle, upper, lower, bar: fluid.Element_ID,
	shifted: bool,
}

create_rectangles :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.rectangles
	page.navigation = app.sidebar
	page.scene = fluid.create_scene(ui.window)
	append(&entry.scenes, page.scene)
	scene := page.scene
	viewport := fluid.bounds(ui, ui.window.viewport)
	navigation := fluid.bounds(ui, page.navigation)
	stage := fluid.Pins{left = navigation.right + 2.25, top = 1.5, right = viewport.right - 2.25, bottom = viewport.bottom - 1.5}
	page.stage = demo_surface(scene, stage, radius = 1.25)
	page.toggle = fluid.button(scene, {
		left = stage.right - 7.75, top = stage.top + 1.25,
		right = stage.right - 1.25, bottom = stage.top + 3.5,
	}, "Move")
	fluid.on_press(ui, page.toggle, page, shift_anchor)
	anchor := anchor_pins(stage, false)
	page.anchor = demo_surface(scene, anchor, {41, 83, 75, 255}, radius = 0.875, shadow = 0.75)
	fluid.set_style(ui, page.anchor, {radius = 0.875, border = {106, 179, 156, 255}, border_width = 0.0625, shadow = 0.75})
	page.upper = demo_surface(scene, {
		left = stage.right - 15.25, top = anchor.top, right = stage.right - 1.75, bottom = anchor.top + 3.5,
	}, {29, 47, 53, 255}, radius = 0.625)
	page.lower = demo_surface(scene, {
		left = stage.right - 15.25, top = anchor.bottom - 3.5, right = stage.right - 1.75, bottom = anchor.bottom,
	}, {42, 41, 53, 255}, radius = 0.625)
	page.bar = demo_surface(scene, {
		left = anchor.left, top = stage.bottom - 2.375, right = anchor.right, bottom = stage.bottom - 1.75,
	}, MINT, radius = 0.3125)
	fluid.set_style(ui, page.bar, {radius = 0.3125})
	fluid.on_update(ui, page.stage, page, update_rectangles)
}

anchor_pins :: proc(stage: fluid.Pins, shifted: bool) -> fluid.Pins {
	left := stage.left + 1.75
	top := stage.top + (shifted ? 12.5 : 6.25)
	return {left = left, top = top, right = left + (shifted ? 14 : 11.5), bottom = top + 8.5}
}

update_rectangles :: proc(page: ^Rectangles, ui: ^fluid.UI, dt: f64) {
	viewport := fluid.bounds(ui, ui.window.viewport)
	navigation := fluid.bounds(ui, page.navigation)
	stage := fluid.Pins{left = navigation.right + 2.25, top = 1.5, right = viewport.right - 2.25, bottom = viewport.bottom - 1.5}
	fluid.set_target(ui, page.stage, stage)
	fluid.set_target(ui, page.toggle, {
		left = stage.right - 7.75, top = stage.top + 1.25, right = stage.right - 1.25, bottom = stage.top + 3.5,
	})
	fluid.set_target(ui, page.anchor, anchor_pins(stage, page.shifted))
	anchor := fluid.bounds(ui, page.anchor)
	fluid.set_target(ui, page.upper, {
		left = stage.right - 15.25, top = anchor.top, right = stage.right - 1.75, bottom = anchor.top + 3.5,
	})
	fluid.set_target(ui, page.lower, {
		left = stage.right - 15.25, top = anchor.bottom - 3.5, right = stage.right - 1.75, bottom = anchor.bottom,
	})
	fluid.set_target(ui, page.bar, {
		left = stage.left + 1.75, top = stage.bottom - 2.375,
		right = stage.left + 1.75 + fluid.width(anchor), bottom = stage.bottom - 1.75,
	})
}

shift_anchor :: proc(page: ^Rectangles, ui: ^fluid.UI, id: fluid.Element_ID) {
	page.shifted = !page.shifted
	stage := fluid.bounds(ui, page.stage)
	fluid.animate_to(ui, page.anchor, anchor_pins(stage, page.shifted), {duration = 0.65, sample = smooth_damp, progress = damp_progress})
	fluid.set_label(ui, id, page.shifted ? "Reset" : "Move")
}
