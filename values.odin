package fluid

import "core:math"

// Bounds are numeric values in the element's window, in UI units.
bounds :: proc(ui: ^UI, id: Element_ID) -> Pins {
	return get_element(ui, id).pins
}

width :: proc(pins: Pins) -> f32 { return max(f32(0), pins.right - pins.left) }
height :: proc(pins: Pins) -> f32 { return max(f32(0), pins.bottom - pins.top) }

rect :: proc(x, y, width, height: f32) -> Pins {
	return {x, y, x + width, y + height}
}

contains :: proc(pins: Pins, point: [2]f32) -> bool {
	return point[0] >= pins.left && point[0] < pins.right &&
		point[1] >= pins.top && point[1] < pins.bottom
}

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
