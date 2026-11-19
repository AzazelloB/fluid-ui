package fluid

Animation :: struct {
	duration: f64,
	sample:   Motion_Sample,
	progress: proc(elapsed, duration: f64) -> f32,
}

// A new request replaces the previous transition.
// set_target can update the numeric destination without restarting its clock.
animate_to :: proc(ui: ^UI, id: Element_ID, pins: Pins, animation: Animation) {
	assert(animation.duration > 0 && animation.sample != nil)
	from := bounds(ui, id)
	element := get_element(ui, id)
	element.pins = checked_pins(pins)
	element.motion = Motion{from = from, animation = animation, frame = ui.frame}
}

@(private="package")
advance_animations :: proc(ui: ^UI, dt: f64) {
	// Hidden elements pause until shown again.
	for id in ui.order {
		element := get_element(ui, id)
		motion := &element.motion
		if element.hidden || motion.animation.sample == nil || motion.frame == ui.frame {
			continue
		}
		motion.elapsed = min(motion.animation.duration, motion.elapsed + max(dt, 0))
		if motion.elapsed >= motion.animation.duration {
			motion^ = {}
		} else {
			t := f32(motion.elapsed / motion.animation.duration)
			if motion.animation.progress != nil {
				t = motion.animation.progress(motion.elapsed, motion.animation.duration)
			}
			motion.progress = clamp(t, 0, f32(0.99999994))
		}
	}
}
