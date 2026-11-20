package main

import "core:math"
import fluid "../.."
import "../../elements"

Bamboo :: struct {
	background, ring: fluid.Element_ID,
	markers: [Site]fluid.Element_ID,
	time: f64,
	parallax: [2]f32,
	atmosphere: f32,
}

create_bamboo :: proc(app: ^Showcase, ui: ^fluid.UI) {
	scene := &app.forest
	window := ui.window
	scene.background = fluid.create_element(window, {draw = draw_bamboo, behavior = {state = scene}})
	scene.ring = fluid.create_element(window, {draw = draw_marker_ring})
	for site in Site {
		info := sites[site]
		scene.markers[site] = fluid.create_element(window, {
			label = info.code, surface = true, pressable = true, draw = draw_marker, behavior = {state = app},
		})
		fluid.on_press(ui, scene.markers[site], app, select_site)
	}
}

update_bamboo :: proc(app: ^Showcase, ui: ^fluid.UI, stage: fluid.Pins, dt: f64) {
	scene := &app.forest
	w, h := fluid.width(stage), fluid.height(stage)
	fluid.set_layout(ui, scene.background, stage)

	scene.time += dt
	parallax: [2]f32
	pointer := fluid.pointer_position(ui.window)
	parallax_area := app.panels.settings_open ? fluid.bounds(ui, app.panels.settings_art) : stage
	if fluid.contains(parallax_area, pointer) {
		size := [2]f32{fluid.width(parallax_area), fluid.height(parallax_area)}
		parallax = ((pointer - {parallax_area.left, parallax_area.top}) / size - 0.5) * f32(app.panels.forest_motion / 100)
	}
	scene.parallax += (parallax - scene.parallax) * (1 - math.exp(-6 * f32(dt)))
	scene.atmosphere += (f32(app.site) - scene.atmosphere) * (1 - math.exp(-4 * f32(dt)))

	for site in Site {
		marker := sites[site].marker
		point := [2]f32{stage.left + w * marker.x, stage.top + h * marker.y} - scene.parallax * 0.75
		fluid.set_layout(ui, scene.markers[site], fluid.rect(point.x - 1.04, point.y - 1.04, 2.08, 2.08))
	}
	fluid.set_target(ui, scene.ring, marker_ring_pins(scene, ui, app.site))
}

clear_canopy_layout :: proc(scene: ^Bamboo, ui: ^fluid.UI) {
	fluid.set_layout(ui, scene.background, {})
	fluid.set_layout(ui, scene.ring, {})
	for id in scene.markers { fluid.set_layout(ui, id, {}) }
}

draw_marker :: proc(view: fluid.Element_View) {
	app := cast(^Showcase)fluid.element_behavior(view.ui, view.id).state
	site := app.site
	for id, index in app.forest.markers {
		if id == view.id {
			site = index
			break
		}
	}
	frame := view
	frame.color = site == app.site ? sites[site].color : fluid.Color{17, 37, 28, 241}
	frame.style = {radius = 2, border_width = 0.09, border = sites[site].color,
		hover_border = INK, focus_border = INK, shadow = 0.32}
	elements.draw_default(frame)
}

draw_bamboo :: proc(view: fluid.Element_View) {
	scene := cast(^Bamboo)fluid.element_behavior(view.ui, view.id).state
	pixels := fluid.pixel_rect(view.pins, fluid.pixel_scale(view.window))
	fragment := #load("shaders/bamboo.frag.spv", []u32)
	if !fluid.render_shader(view.window.renderer, pixels, fragment, {f32(scene.time), scene.parallax.x, scene.parallax.y, scene.atmosphere}) {
		fluid.rounded_fill(view.window.renderer, pixels, pixels.h * 0.04, {25, 53, 43, 255})
	}
}

marker_ring_pins :: proc(scene: ^Bamboo, ui: ^fluid.UI, site: Site) -> fluid.Pins {
	marker := fluid.bounds(ui, scene.markers[site])
	return {marker.left - 0.24, marker.top - 0.24, marker.right + 0.24, marker.bottom + 0.24}
}

draw_marker_ring :: proc(view: fluid.Element_View) {
	SEGMENTS :: 40
	pixels := fluid.pixel_rect(view.pins, fluid.pixel_scale(view.window))
	center := [2]f32{pixels.x + pixels.w / 2, pixels.y + pixels.h / 2}
	radius := pixels.w / 2
	color := [4]f32{0.95, 0.98, 0.9, 0.85}
	vertices: [SEGMENTS * 2]fluid.Vertex
	indices: [SEGMENTS * 6]i32
	for i in 0..<SEGMENTS {
		angle := f32(i) * (2 * math.PI / SEGMENTS)
		direction := [2]f32{math.cos(angle), math.sin(angle)}
		vertices[i * 2] = {center + direction * radius, color}
		vertices[i * 2 + 1] = {center + direction * (radius - max(1, pixels.w * 0.028)), color}
		v := i32(i * 2)
		next := i32((i + 1) % SEGMENTS * 2)
		quad := [6]i32{v, next, v + 1, v + 1, next, next + 1}
		copy(indices[i * 6:i * 6 + 6], quad[:])
	}
	fluid.render_geometry(view.window.renderer, vertices[:], indices[:])
}
