package fluid

Animation :: struct {
	duration: f64,
	sample:   Motion_Sample,
	progress: proc(elapsed, duration: f64) -> f32,
}

// A new request replaces the previous transition and its completion action.
// Sampling stays lazy so relative destinations continue to follow live layout.
animate_to :: proc(ui: ^UI, id: Element_ID, position, size: [2]Value, animation: Animation) {
	assert(animation.duration > 0 && animation.sample != nil)
	from := bounds(ui, id)
	element := get_element(ui, id)
	element.position = position
	element.size = size
	element.motion_serial += 1
	element.motion = Motion{from = from, animation = animation, frame = ui.frame}
}

// Explicitly preserve the current completion action when changing a destination.
retarget :: proc(ui: ^UI, id: Element_ID, position, size: [2]Value, animation: Animation) {
	complete := get_element(ui, id).motion.complete
	animate_to(ui, id, position, size, animation)
	get_element(ui, id).motion.complete = complete
}

on_complete :: proc(ui: ^UI, id: Element_ID, owner: ^$Owner, run: proc(owner: ^Owner, ui: ^UI, id: Element_ID)) {
	assert(transitioning(ui, id))
	get_element(ui, id).motion.complete = bind_element(ui, owner, run)
}

clear_completion :: proc(ui: ^UI, id: Element_ID) {
	element := get_element(ui, id)
	element.motion_serial += 1
	element.motion.complete = {}
}

animation_remaining :: proc(ui: ^UI, id: Element_ID) -> f64 {
	motion := get_element(ui, id).motion
	return max(f64(0), motion.animation.duration - motion.elapsed)
}

transitioning :: proc(ui: ^UI, id: Element_ID) -> bool {
	return valid(ui, id) && get_element(ui, id).motion.animation.sample != nil
}

@(private="package")
advance_animations :: proc(ui: ^UI, dt: f64) {
	Completion :: struct {
		id:       Element_ID,
		serial:   u64,
		callback: Element_Callback,
	}
	completed := make([dynamic]Completion, context.temp_allocator)
	// Inactive elements pause automatically; activation needs no scheduler wiring.
	for id in ui.active {
		element := get_element(ui, id)
		motion := &element.motion
		if motion.animation.sample == nil || motion.frame == ui.frame {
			continue
		}
		motion.elapsed = min(motion.animation.duration, motion.elapsed + max(dt, 0))
		if motion.elapsed >= motion.animation.duration {
			if motion.complete.call != nil {
				append(&completed, Completion{id, element.motion_serial, motion.complete})
			}
			motion^ = {}
		} else {
			t := f32(motion.elapsed / motion.animation.duration)
			if motion.animation.progress != nil {
				t = motion.animation.progress(motion.elapsed, motion.animation.duration)
			}
			motion.progress = clamp(t, 0, f32(0.99999994))
		}
	}
	// Callbacks may replace/cancel another completed transition or remove its target.
	for entry in completed {
		if !ui.running {
			return
		}
		if valid(ui, entry.id) && get_element(ui, entry.id).motion_serial == entry.serial {
			entry.callback.call(entry.callback.data, ui, entry.id)
		}
	}
}
