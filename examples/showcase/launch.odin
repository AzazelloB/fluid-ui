package main

import "core:math"
import fluid "../.."
import "vendor:sdl3"

Launch_Reveal :: struct {
	origin: [2]f32,
}

start_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window) {
	mouse := fluid.pointer_position(window)
	r := fluid.bounds(window.ui, window.viewport)
	if !fluid.contains(r, mouse) {
		mouse = {fluid.width(r) / 2, fluid.height(r) / 2}
	}
	reveal.origin = mouse
	fluid.window_effect(window, 0.45, reveal, draw_launch_reveal, finish_launch_reveal)
}

finish_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window) {
	fluid.set_window_flags(window, {})
}

draw_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window, t: f32) {
	r := fluid.bounds(window.ui, window.viewport)
	scale := fluid.pixel_scale(window)
	center := reveal.origin * scale
	dx := max(reveal.origin[0], fluid.width(r) - reveal.origin[0]) * scale
	dy := max(reveal.origin[1], fluid.height(r) - reveal.origin[1]) * scale
	diagonal := math.sqrt(dx * dx + dy * dy)
	radius := diagonal * smoothstep(t)
	outer := diagonal * 3 + 4
	SEGMENTS :: 192
	vertices: [SEGMENTS * 6]sdl3.Vertex
	for i in 0..<SEGMENTS {
		a := f32(i) * 2 * math.PI / SEGMENTS
		b := f32(i + 1) * 2 * math.PI / SEGMENTS
		d1 := [2]f32{math.cos(a), math.sin(a)}
		d2 := [2]f32{math.cos(b), math.sin(b)}
		points := [6][2]f32{center + d1 * radius, center + d1 * outer, center + d2 * outer,
			center + d1 * radius, center + d2 * outer, center + d2 * radius}
		for point, j in points {
			vertices[i * 6 + j] = {position = {point[0], point[1]}, color = {0, 0, 0, 0}}
		}
	}
	// Erase pixels outside the circle, revealing the actual desktop underneath.
	assert(sdl3.SetRenderDrawBlendMode(window.renderer, sdl3.BLENDMODE_NONE))
	assert(sdl3.RenderGeometry(window.renderer, nil, raw_data(vertices[:]), len(vertices), nil, 0))
}
