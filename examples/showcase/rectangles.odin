package main

import fluid "../.."
import "../../elements"

Rectangles :: struct {
	navigation, stage, anchor, toggle, upper, lower, bar: fluid.Element_ID,
	shifted: bool,
}

create_rectangles :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.rectangles
	page.navigation = app.sidebar
	scene := fluid.create_scene(ui.window)
	append(&entry.scenes, scene)
	page.stage = demo_surface(scene, {}, radius = 1.25)
	page.toggle = elements.toggle(scene, {}, "Move", false)
	elements.on_change(ui, page.toggle, page, shift_anchor)
	page.anchor = elements.panel(scene, {}, {41, 83, 75, 255})
	fluid.set_style(ui, page.anchor, {radius = 0.875, border = {106, 179, 156, 255}, border_width = 0.0625, shadow = 0.75})
	page.upper = demo_surface(scene, {}, {29, 47, 53, 255}, radius = 0.625)
	page.lower = demo_surface(scene, {}, {42, 41, 53, 255}, radius = 0.625)
	page.bar = elements.panel(scene, {}, MINT)
	fluid.set_style(ui, page.bar, {radius = 0.3125})
	update_rectangles(page, ui, 0)
	fluid.on_update(ui, page.stage, page, update_rectangles)
}

anchor_pins :: proc(stage: fluid.Pins, shifted: bool) -> fluid.Pins {
	left := stage.left + 1.75
	top := stage.top + (shifted ? 12.5 : 6.25)
	return {left = left, top = top, right = left + (shifted ? 14 : 11.5), bottom = top + 8.5}
}

update_rectangles :: proc(page: ^Rectangles, ui: ^fluid.UI, dt: f64) {
	viewport := showcase_body(ui)
	stage := content_pins(ui, page.navigation, viewport)
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

shift_anchor :: proc(page: ^Rectangles, ui: ^fluid.UI, change: elements.Control_Change) {
	page.shifted = change.value.(bool)
	fluid.set_selected(ui, change.id, page.shifted)
	stage := fluid.bounds(ui, page.stage)
	fluid.animate_to(ui, page.anchor, anchor_pins(stage, page.shifted), damped_animation(0.65))
	fluid.set_label(ui, change.id, page.shifted ? "Reset" : "Move")
}
