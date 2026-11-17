package fluid

import "core:math"

// Bounds are numeric values in the element's window, in UI units.
// target=true reads the animation destination instead of the visible sample.
bounds :: proc(ui: ^UI, id: Element_ID, target: bool = false) -> Pins {
	element := get_element(ui, id)
	result := element.pins
	if !target && element.motion.animation.sample != nil {
		motion := element.motion
		result = checked_pins(motion.animation.sample(motion.from, result, motion.progress))
	}
	return result
}

bounds_in :: proc(ui: ^UI, id: Element_ID, space: ^Window, target: bool = false) -> Pins {
	return translate_between(bounds(ui, id, target), coordinate_window(get_element(ui, id)), space)
}

content_size :: proc(ui: ^UI, id: Element_ID) -> [2]f32 {
	element := get_element(ui, id)
	if len(element.label) == 0 { return {} }
	wrap_width := element.text_wrap ? width(bounds(ui, id)) : 0
	w, h := measure_text(element.owner.window, element.label, element.text_size, element.text_weight, wrap_width)
	return {w, h}
}

width :: proc(pins: Pins) -> f32 { return max(f32(0), pins.right - pins.left) }
height :: proc(pins: Pins) -> f32 { return max(f32(0), pins.bottom - pins.top) }

// Translating moves both pins, so it preserves dimensions.
translated :: proc(pins: Pins, offset: [2]f32) -> Pins {
	return {pins.left + offset[0], pins.top + offset[1], pins.right + offset[0], pins.bottom + offset[1]}
}

@(private="package")
translate_between :: proc(pins: Pins, source, destination: ^Window) -> Pins {
	result := pins
	if source != destination {
		if source != nil { result = translated(result, window_position(source)) }
		if destination != nil { result = translated(result, -window_position(destination)) }
	}
	return result
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

@(private="package")
hit_test :: proc(app: ^UI, window: ^Window, x, y: f32) -> int {
	for i := len(app.active) - 1; i >= 0; i -= 1 {
		id := app.active[i]
		element := get_element(app, id)
		if element.owner.window != window || (element.kind != .Button && !element.draggable) { continue }
		r := bounds(app, id)
		if x >= r.left && x < r.right && y >= r.top && y < r.bottom { return int(id) }
	}
	return -1
}
