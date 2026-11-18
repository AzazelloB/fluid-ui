package main

import "core:math"
import fluid "../.."

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
	if !fluid.set_window_clip(window, fluid.Window_Circle{reveal.origin, 0}) {
		return
	}
	fluid.window_effect(window, 0.45, reveal, draw_launch_reveal, finish_launch_reveal)
}

finish_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window) {
	_ = fluid.set_window_clip(window, nil)
}

draw_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window, t: f32) {
	r := fluid.bounds(window.ui, window.viewport)
	dx := max(reveal.origin[0], fluid.width(r) - reveal.origin[0])
	dy := max(reveal.origin[1], fluid.height(r) - reveal.origin[1])
	diagonal := math.sqrt(dx * dx + dy * dy)
	_ = fluid.set_window_clip(window, fluid.Window_Circle{reveal.origin, diagonal * smoothstep(t)})
}
