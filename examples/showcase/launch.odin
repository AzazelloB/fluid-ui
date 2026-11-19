package main

import "core:math"
import fluid "../.."

Launch_Reveal :: struct {
	origin: [2]f32,
	radius: f32,
}

start_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window) {
	mouse := fluid.pointer_position(window)
	r := fluid.bounds(window.ui, window.viewport)
	if !fluid.contains(r, mouse) {
		mouse = {fluid.width(r) / 2, fluid.height(r) / 2}
	}
	reveal^ = {origin = mouse}
	if !fluid.set_window_clip(window, fluid.Window_Mask{reveal, write_launch_mask}) {
		return
	}
	fluid.window_effect(window, 0.45, reveal, draw_launch_reveal, finish_launch_reveal)
}

finish_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window) {
	_ = fluid.set_window_clip(window)
}

draw_launch_reveal :: proc(reveal: ^Launch_Reveal, window: ^fluid.Window, t: f32) {
	r := fluid.bounds(window.ui, window.viewport)
	dx := max(reveal.origin[0], fluid.width(r) - reveal.origin[0])
	dy := max(reveal.origin[1], fluid.height(r) - reveal.origin[1])
	diagonal := math.sqrt(dx * dx + dy * dy)
	reveal.radius = diagonal * smoothstep(t)
	_ = fluid.set_window_clip(window, fluid.Window_Mask{reveal, write_launch_mask})
}

write_launch_mask :: proc(state: rawptr, pixels: []u8, size: [2]i32, scale: f32) {
	reveal := cast(^Launch_Reveal)state
	if reveal.radius <= 0 {
		return
	}
	center := reveal.origin * scale
	radius := reveal.radius * scale
	top := max(0, i32(math.ceil(center.y - radius - 0.5)))
	bottom := min(size.y, i32(math.floor(center.y + radius - 0.5)) + 1)
	for y in top..<bottom {
		dy := f32(y) + 0.5 - center.y
		half_width := math.sqrt(max(0, radius * radius - dy * dy))
		left := max(0, i32(math.ceil(center.x - half_width - 0.5)))
		right := min(size.x, i32(math.floor(center.x + half_width - 0.5)) + 1)
		offset := int(y) * int(size.x)
		if left < right {
			for &pixel in pixels[offset + int(left):offset + int(right)] {
				pixel = 255
			}
		}
	}
}
