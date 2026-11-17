package fluid

import "core:math"

// Bounds are numeric values in the element's window, in UI units.
bounds :: proc(ui: ^UI, id: Element_ID) -> Pins {
	element := get_element(ui, id)
	result := element.pins
	if element.motion.animation.sample != nil {
		motion := element.motion
		result = checked_pins(motion.animation.sample(motion.from, result, motion.progress))
	}
	return result
}

width :: proc(pins: Pins) -> f32 { return max(f32(0), pins.right - pins.left) }
height :: proc(pins: Pins) -> f32 { return max(f32(0), pins.bottom - pins.top) }

// Translating moves both pins, so it preserves dimensions.
translated :: proc(pins: Pins, offset: [2]f32) -> Pins {
	return {pins.left + offset[0], pins.top + offset[1], pins.right + offset[0], pins.bottom + offset[1]}
}

@(private="package")
checked_pins :: proc(value: Pins) -> Pins {
	pins := value
	assert(!math.is_nan(pins.left) && !math.is_inf(pins.left) &&
		!math.is_nan(pins.top) && !math.is_inf(pins.top) &&
		!math.is_nan(pins.right) && !math.is_inf(pins.right) &&
		!math.is_nan(pins.bottom) && !math.is_inf(pins.bottom), "Non-finite pins")
	// Crossed pins collapse rather than creating a mirrored/hittable rectangle.
	pins.right = max(pins.left, pins.right)
	pins.bottom = max(pins.top, pins.bottom)
	return pins
}
