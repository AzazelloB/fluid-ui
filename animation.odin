package fluid

// User code supplies one pure trajectory for the complete rectangle.
Animation :: struct {
	duration: f64,
	sample: Motion_Sample,
}

animate_to :: proc(app: ^UI, id: Element_ID, position, size: [2]Value, animation: Animation) {
	assert(animation.duration > 0 && animation.sample != nil)
	from := bounds(app, id)
	element := &app.elements[id]
	element.position = position
	element.size = size
	element.motion = Motion{from = from, duration = animation.duration, sample = animation.sample}
}

// Completion remains observable until the next animation on this element.
// Inactive scenes therefore cannot lose completion between frames.
animation_finished :: proc(app: ^UI, id: Element_ID) -> bool {
	motion := app.elements[id].motion
	return motion.duration > 0 && motion.elapsed >= motion.duration
}

animation_remaining :: proc(app: ^UI, id: Element_ID) -> f64 {
	motion := app.elements[id].motion
	return max(f64(0), motion.duration - motion.elapsed)
}

update :: proc(app: ^UI, dt: f64) {
	// No application code is called here, so iteration cannot mutate the set.
	for id in app.active {
		motion := &app.elements[id].motion
		if motion.duration > 0 && motion.elapsed < motion.duration {
			motion.elapsed = min(motion.duration, motion.elapsed + max(dt, 0))
		}
	}
}
