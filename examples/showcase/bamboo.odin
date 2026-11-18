package main

import "core:math"
import fluid "../.."
import "../../elements"

Bamboo :: struct {
	sidebar, background, wind: fluid.Element_ID,
	time: f64,
	parallax: [2]f32,
	paused: bool,
}

create_bamboo :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.bamboo
	page.sidebar = app.sidebar
	scene := fluid.create_scene(ui.window)
	append(&entry.scenes, scene)
	page.background = fluid.create_element(scene, {draw = draw_bamboo, behavior = {state = page}})
	page.wind = elements.button(scene, {}, "Pause wind")
	fluid.set_color(ui, page.wind, {20, 42, 32, 224})
	fluid.set_style(ui, page.wind, {
		radius = 0.625, border = {91, 121, 93, 200}, hover_border = {146, 179, 128, 255}, border_width = 0.0625,
	})
	fluid.on_press(ui, page.wind, page, toggle_bamboo_wind)
	fluid.on_update(ui, page.background, page, update_bamboo)
	update_bamboo(page, ui, 0)
}

update_bamboo :: proc(page: ^Bamboo, ui: ^fluid.UI, dt: f64) {
	stage := showcase_body(ui)
	stage.left = fluid.bounds(ui, page.sidebar).right
	fluid.set_layout(ui, page.background, stage)
	fluid.set_layout(ui, page.wind, fluid.rect(stage.right - 8.25, stage.bottom - 4, 6.75, 2.5))
	if !page.paused {
		page.time += dt
	}
	parallax: [2]f32
	pointer := fluid.pointer_position(ui.window)
	if fluid.contains(stage, pointer) {
		parallax = (pointer - {stage.left, stage.top}) / {fluid.width(stage), fluid.height(stage)} - 0.5
	}
	page.parallax += (parallax - page.parallax) * (1 - math.exp(-6 * f32(dt)))
}

toggle_bamboo_wind :: proc(page: ^Bamboo, ui: ^fluid.UI, id: fluid.Element_ID) {
	page.paused = !page.paused
	fluid.set_label(ui, id, page.paused ? "Resume wind" : "Pause wind")
}

draw_bamboo :: proc(view: fluid.Element_View) {
	page := cast(^Bamboo) fluid.element_behavior(view.ui, view.id).state
	pixels := fluid.pixel_rect(view.pins, fluid.pixel_scale(view.window))
	fragment := #load("shaders/bamboo.frag.spv", []u32)
	if !fluid.render_shader(view.window.renderer, pixels, fragment, {f32(page.time), page.parallax.x, page.parallax.y, 0}) {
		fluid.render_fill_rect(view.window.renderer, pixels, {25, 53, 43, 255})
	}
}
