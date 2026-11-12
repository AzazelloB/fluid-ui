package main

import "core:math"
import fluid "../.."

damp_progress :: proc(elapsed, duration: f64) -> f32 {
	SPEED :: 7.0
	time := clamp(elapsed, 0, duration)
	return f32((1 - math.exp(-SPEED * time)) / (1 - math.exp(-SPEED * duration)))
}

smooth_damp :: proc(from, to: fluid.Rect, elapsed, duration: f64) -> fluid.Rect {
	t := damp_progress(elapsed, duration)
	return {
		from.x + (to.x - from.x) * t,
		from.y + (to.y - from.y) * t,
		from.w + (to.w - from.w) * t,
		from.h + (to.h - from.h) * t,
	}
}

arc :: proc(from, to: fluid.Rect, elapsed, duration: f64) -> fluid.Rect {
	result := smooth_damp(from, to, elapsed, duration)
	t := damp_progress(elapsed, duration)
	dx, dy := to.x - from.x, to.y - from.y
	// A short retarget near the sidebar needs a smaller bend.
	height := min(f32(96), math.sqrt(dx * dx + dy * dy) * 0.2)
	result.y -= 4 * height * t * (1 - t)
	return result
}

flight_animation :: proc() -> fluid.Animation { return {duration = 0.9, sample = arc} }
stack_animation :: proc() -> fluid.Animation { return {duration = 0.4, sample = smooth_damp} }
entry_animation :: proc() -> fluid.Animation { return {duration = 0.14, sample = smooth_damp} }
