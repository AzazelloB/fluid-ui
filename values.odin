package fluid

at :: proc(value: f32) -> Value {
	return Value{offset = value}
}

// Position attributes translate to the consuming element's window coordinates.
// Dimensions remain dimensions, including references across native windows.
relative :: proc(element: Element_ID, attribute: Attribute, offset: f32 = 0, target: bool = false) -> Value {
	return Value{source = Anchor{element, attribute, target}, offset = offset}
}

distance :: proc(from: Element_ID, from_attribute: Attribute, to: Element_ID, to_attribute: Attribute, offset: f32 = 0) -> Value {
	return Value{source = Distance{Anchor{from, from_attribute, false}, Anchor{to, to_attribute, false}}, offset = offset}
}

max_of :: proc(group: Group_ID, attribute: Attribute, padding: f32 = 0, minimum: f32 = 0) -> Value {
	return Value{source = Maximum{group, attribute, padding, minimum}}
}

// Follow coordinate dependencies, independent of element insertion order.
// Return the editable source and the accumulated offset from that source.
@(private="package")
resolve :: proc(app: ^UI, coordinate: ^Value, depth: int = 0) -> (^Value, f32) {
	coordinate := coordinate
	depth := depth
	offset: f32
	for {
		assert(depth <= 4 * len(app.elements) + 1, "Cyclic coordinate references")
		depth += 1
		if anchor, ok := coordinate.source.(Anchor); ok {
			assert(valid(app, anchor.element), "Invalid or expired element reference")
			// Content width is an intrinsic leaf, not the row's displayed width.
			if anchor.attribute == .Content_Width {
				return coordinate, offset
			}
			offset += coordinate.offset
			target := get_element(app, anchor.element)
			switch anchor.attribute {
			case .Left:
				coordinate = &target.position[0]
			case .Top:
				coordinate = &target.position[1]
			case .Right:
				coordinate = &target.position[0]
				offset += read(app, &target.size[0], depth, space = coordinate_window(target))
			case .Bottom:
				coordinate = &target.position[1]
				offset += read(app, &target.size[1], depth, space = coordinate_window(target))
			case .Width:
				coordinate = &target.size[0]
			case .Height:
				coordinate = &target.size[1]
			case .Content_Width:
				unreachable()
			}
		} else {
			return coordinate, offset
		}
	}
}

@(private="package")
read_attribute :: proc(app: ^UI, anchor: Anchor, depth: int, target_only: bool = false, space: ^Window = nil) -> f32 {
	result := read_local_attribute(app, anchor, depth, target_only)
	axis: int
	switch anchor.attribute {
	case .Left, .Right:
		axis = 0
	case .Top, .Bottom:
		axis = 1
	case .Width, .Height, .Content_Width:
		return result
	}
	source := coordinate_window(&app.elements[slot(anchor.element)])
	if source != space {
		if source != nil {
			result += window_position(source)[axis]
		}
		if space != nil {
			result -= window_position(space)[axis]
		}
	}
	return result
}

@(private="package")
read_local_attribute :: proc(app: ^UI, anchor: Anchor, depth: int, target_only: bool = false) -> f32 {
	destination := target_only || anchor.target
	assert(valid(app, anchor.element), "Invalid or expired element reference")
	element := get_element(app, anchor.element)
	if !destination && element.motion.animation.sample != nil && anchor.attribute != .Content_Width {
		r := evaluated_bounds(app, anchor.element, depth, false)
		switch anchor.attribute {
		case .Left:
			return r.x
		case .Top:
			return r.y
		case .Width:
			return r.w
		case .Height:
			return r.h
		case .Right:
			return r.x + r.w
		case .Bottom:
			return r.y + r.h
		case .Content_Width:
			unreachable()
		}
	}
	switch anchor.attribute {
	case .Left:
		return read(app, &element.position[0], depth, destination, coordinate_window(element))
	case .Top:
		return read(app, &element.position[1], depth, destination, coordinate_window(element))
	case .Width:
		return read(app, &element.size[0], depth, destination, coordinate_window(element))
	case .Height:
		return read(app, &element.size[1], depth, destination, coordinate_window(element))
	case .Right:
		return read(app, &element.position[0], depth, destination, coordinate_window(element)) + read(app, &element.size[0], depth, destination, coordinate_window(element))
	case .Bottom:
		return read(app, &element.position[1], depth, destination, coordinate_window(element)) + read(app, &element.size[1], depth, destination, coordinate_window(element))
	case .Content_Width:
		if len(element.label) == 0 {
			return 0
		}
		width, _ := measure_text(element.owner.window, element.label, element.text_size)
		return width + TEXT_PADDING * 2
	}
	unreachable()
}

read :: proc(app: ^UI, value: ^Value, depth: int = 0, target_only: bool = false, space: ^Window = nil) -> f32 {
	assert(depth <= 4 * len(app.elements) + 1, "Cyclic coordinate references")
	result := value.offset
	switch source in value.source {
	case Anchor:
		result += read_attribute(app, source, depth + 1, target_only, space)
	case Maximum:
		assert(int(source.group) >= 0 && int(source.group) < len(app.groups), "Invalid group reference")
		largest: f32
		for element in app.groups[source.group] {
			largest = max(largest, read_attribute(app, Anchor{element, source.attribute, false}, depth + 1, target_only, space))
		}
		result += max(source.minimum, largest + source.padding)
	case Distance:
		result += read_attribute(app, source.to, depth + 1, target_only, space) - read_attribute(app, source.from, depth + 1, target_only, space)
	case nil:
	}

	return result
}

bounds :: proc(app: ^UI, id: Element_ID) -> Rect {
	return evaluated_bounds(app, id, 0, false)
}

// Read an element in another window's coordinates, or desktop coordinates for nil.
bounds_in :: proc(app: ^UI, id: Element_ID, space: ^Window) -> Rect {
	r := bounds(app, id)
	source := coordinate_window(&app.elements[slot(id)])
	if source != space {
		offset: [2]f32
		if source != nil {
			offset += window_position(source)
		}
		if space != nil {
			offset -= window_position(space)
		}
		r.x += offset[0]
		r.y += offset[1]
	}
	return r
}

@(private="package")
evaluated_bounds :: proc(app: ^UI, id: Element_ID, depth: int, target_only: bool) -> Rect {
	assert(valid(app, id), "Invalid or expired element reference")
	element := get_element(app, id)
	space := coordinate_window(element)
	result := Rect{
		read(app, &element.position[0], depth + 1, target_only, space),
		read(app, &element.position[1], depth + 1, target_only, space),
		read(app, &element.size[0], depth + 1, target_only, space),
		read(app, &element.size[1], depth + 1, target_only, space),
	}
	motion := element.motion
	if !target_only && motion.animation.sample != nil {
		result = motion.animation.sample(motion.from, result, motion.progress)
	}
	return result
}

@(private="package")
// Decorative surfaces and labels do not intercept buttons or draggable cards.
hit_test :: proc(app: ^UI, window: ^Window, x, y: f32) -> int {
	for i := len(app.active) - 1; i >= 0; i -= 1 {
		id := app.active[i]
		element := get_element(app, id)
		if element.owner.window != window || (element.kind != .Button && !element.draggable) {
			continue
		}
		r := bounds(app, id)
		if x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h {
			return int(id)
		}
	}
	return -1
}
