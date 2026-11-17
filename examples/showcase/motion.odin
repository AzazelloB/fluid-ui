package main

import "core:math"
import fluid "../.."

damped_animation :: proc(duration: f64, sample: fluid.Motion_Sample = lerp_pins) -> fluid.Animation {
	return {duration = duration, sample = sample, progress = damp_progress}
}

damp_progress :: proc(elapsed, duration: f64) -> f32 {
	SPEED :: 7.0
	time := clamp(elapsed, 0, duration)
	return f32((1 - math.exp(-SPEED * time)) / (1 - math.exp(-SPEED * duration)))
}

lerp_pins :: proc(from, to: fluid.Pins, t: f32) -> fluid.Pins {
	return {
		from.left + (to.left - from.left) * t,
		from.top + (to.top - from.top) * t,
		from.right + (to.right - from.right) * t,
		from.bottom + (to.bottom - from.bottom) * t,
	}
}

arc :: proc(from, to: fluid.Pins, t: f32) -> fluid.Pins {
	result := lerp_pins(from, to, t)
	dx, dy := to.left - from.left, to.top - from.top
	height := min(f32(6), math.sqrt(dx * dx + dy * dy) * 0.2)
	offset := 4 * height * t * (1 - t)
	result.top -= offset
	result.bottom -= offset
	return result
}

smoothstep :: proc(t: f32) -> f32 {
	return t * t * (3 - 2 * t)
}
