package fluid

Animation :: struct {
	duration: f64,
	sample:   Motion_Sample,
	progress: proc(elapsed, duration: f64) -> f32,
}

@(private="package")
Motion :: struct {
	id:        Element_ID,
	from, target: Pins,
	elapsed:   f64,
	progress:  f32,
	animation: Animation,
	frame:     u64,
}

// A new request replaces the previous transition.
// set_target can update the numeric destination without restarting its clock.
animate_to :: proc(ui: ^UI, id: Element_ID, pins: Pins, animation: Animation) {
	assert(animation.duration > 0 && animation.sample != nil)
	element := get_element(ui, id)
	motion := Motion{id = id, from = element.pins, target = checked_pins(pins), animation = animation, frame = ui.frame}
	motions := is_active(ui, id) ? &ui.motions : &ui.paused_motions
	if current := find_motion(motions^[:], id); current >= 0 {
		motions[current] = motion
	} else {
		append(motions, motion)
	}
	sample_motion(element, motion)
}

@(private="package")
element_motion :: proc(ui: ^UI, id: Element_ID) -> ^Motion {
	if index := find_motion(ui.motions[:], id); index >= 0 {
		return &ui.motions[index]
	}
	if index := find_motion(ui.paused_motions[:], id); index >= 0 {
		return &ui.paused_motions[index]
	}
	return nil
}

@(private="package")
take_element_motion :: proc(ui: ^UI, id: Element_ID) -> Motion {
	if motion := take_motion(&ui.motions, id); motion.animation.sample != nil {
		return motion
	}
	return take_motion(&ui.paused_motions, id)
}

@(private="package")
find_motion :: proc(motions: []Motion, id: Element_ID) -> int {
	for motion, index in motions {
		if motion.id == id {
			return index
		}
	}
	return -1
}

@(private="package")
take_motion :: proc(motions: ^[dynamic]Motion, id: Element_ID) -> Motion {
	index := find_motion(motions^[:], id)
	if index < 0 {
		return {}
	}
	motion := motions[index]
	unordered_remove(motions, index)
	return motion
}

@(private="package")
sample_motion :: proc(element: ^Element, motion: Motion) {
	element.pins = checked_pins(motion.animation.sample(motion.from, motion.target, motion.progress))
}

@(private="package")
advance_animations :: proc(ui: ^UI, dt: f64) {
	delta := max(dt, 0)
	// Iterate backwards so a swapped-in motion has already been processed.
	for index := len(ui.motions) - 1; index >= 0; index -= 1 {
		motion := &ui.motions[index]
		if motion.frame == ui.frame {
			continue
		}
		motion.elapsed = min(motion.animation.duration, motion.elapsed + delta)
		element := get_element(ui, motion.id)
		if motion.elapsed >= motion.animation.duration {
			element.pins = motion.target
			unordered_remove(&ui.motions, index)
		} else {
			t := f32(motion.elapsed / motion.animation.duration)
			if motion.animation.progress != nil {
				t = motion.animation.progress(motion.elapsed, motion.animation.duration)
			}
			motion.progress = clamp(t, 0, f32(0.99999994))
			sample_motion(element, motion^)
		}
	}
}
