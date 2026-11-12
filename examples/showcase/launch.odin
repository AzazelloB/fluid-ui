package main

import "core:math"
import fluid "../.."
import "vendor:sdl3"

Launch_Reveal :: struct {
	origin:   [2]f32,
	started:  u64,
	finished: bool,
}

create_launch_reveal :: proc(window: ^fluid.Window) -> Launch_Reveal {
	mouse := fluid.pointer_position(window)
	r := fluid.bounds(window.ui, window.viewport)
	// Use the center when a terminal/search launch leaves the cursor elsewhere.
	if mouse[0] < 0 || mouse[0] >= r.w || mouse[1] < 0 || mouse[1] >= r.h {
		mouse = {r.w / 2, r.h / 2}
	}
	return {origin = mouse}
}

// Returns true once, when the transparent reveal window can be replaced.
draw_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window) -> bool {
	if reveal.finished {
		return false
	}
	now := sdl3.GetTicksNS()
	flags := sdl3.GetWindowFlags(window.handle)
	// Visibility starts the reveal; keyboard focus does not control rendering.
	if reveal.started == 0 && .HIDDEN not_in flags {
		reveal.started = now
	}
	t: f32
	if reveal.started > 0 {
		t = clamp(f32(f64(now - reveal.started) / 1e9 / 0.45), 0, 1)
	}
	if t >= 1 {
		reveal.finished = true
		return true
	}
	r := fluid.bounds(window.ui, window.viewport)
	scale := window.pixel_density
	center := reveal.origin * scale
	dx := max(reveal.origin[0], r.w - reveal.origin[0]) * scale
	dy := max(reveal.origin[1], r.h - reveal.origin[1]) * scale
	diagonal := math.sqrt(dx * dx + dy * dy)
	radius := diagonal * t * t * (3 - 2 * t)
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
	return false
}
