package main

import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

TEXT_PADDING :: 16
FONT_SIZE :: 16

Element_Kind :: enum {Panel, Button}
Press_Action :: proc(app: ^App, element: Element_ID)

Element_ID :: distinct int
Group_ID :: distinct int
Attribute :: enum {Left, Top, Right, Bottom, Width, Height, Content_Width}

Anchor :: struct {
	element:   Element_ID,
	attribute: Attribute,
}

// A group is an explicit set of references, not an ownership relationship.
Maximum :: struct {
	group:     Group_ID,
	attribute: Attribute,
	padding:   f32,
	minimum:   f32,
}

Value :: struct {
	// An empty source makes offset a literal value.
	source: union {Anchor, Maximum},
	offset: f32,
}

Element :: struct {
	kind:      Element_Kind,
	position:  [2]Value,
	size:      [2]Value,
	color:     sdl3.Color,
	label:     string,
	text:      ^ttf.Text,
	text_label: string,
	on_press:  Press_Action,
	selected:  bool,
	visible:   bool,
	draggable: bool,
}

at :: proc(value: f32) -> Value {
	return Value{offset = value}
}

relative :: proc(element: Element_ID, attribute: Attribute, offset: f32 = 0) -> Value {
	return Value{source = Anchor{element, attribute}, offset = offset}
}

group :: proc(app: ^App) -> Group_ID {
	id := Group_ID(len(app.groups))
	append(&app.groups, [dynamic]Element_ID{})
	return id
}

include :: proc(app: ^App, group: Group_ID, element: Element_ID) {
	append(&app.groups[group], element)
}

max_of :: proc(group: Group_ID, attribute: Attribute, padding: f32 = 0, minimum: f32 = 0) -> Value {
	return Value{source = Maximum{group, attribute, padding, minimum}}
}

add_element :: proc(app: ^App, element: Element) -> Element_ID {
	id := Element_ID(len(app.elements))
	append(&app.elements, element)
	return id
}

// Follow coordinate dependencies, independent of element insertion order.
// Return the editable source and the accumulated offset from that source.
resolve :: proc(app: ^App, coordinate: ^Value, depth: int = 0) -> (^Value, f32) {
	coordinate := coordinate
	depth := depth
	offset: f32
	for {
		assert(depth <= 4 * len(app.elements) + 1, "Cyclic coordinate references")
		depth += 1
		if anchor, ok := coordinate.source.(Anchor); ok {
			assert(int(anchor.element) >= 0 && int(anchor.element) < len(app.elements), "Invalid element reference")
			// Content width is an intrinsic leaf, not the row's displayed width.
			if anchor.attribute == .Content_Width {
				return coordinate, offset
			}
			offset += coordinate.offset
			target := &app.elements[anchor.element]
			switch anchor.attribute {
			case .Left:
				coordinate = &target.position[0]
			case .Top:
				coordinate = &target.position[1]
			case .Right:
				coordinate = &target.position[0]
				offset += read(app, &target.size[0], depth)
			case .Bottom:
				coordinate = &target.position[1]
				offset += read(app, &target.size[1], depth)
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

read :: proc(app: ^App, coordinate: ^Value, depth: int = 0) -> f32 {
	source, offset := resolve(app, coordinate, depth + 1)
	result := source.offset + offset
	if anchor, ok := source.source.(Anchor); ok {
		label := app.elements[anchor.element].label
		if len(label) > 0 {
			width, _ := measure_text(app, label)
			result += width + TEXT_PADDING * 2
		}
	} else if expression, is_maximum := source.source.(Maximum); is_maximum {
		assert(int(expression.group) >= 0 && int(expression.group) < len(app.groups), "Invalid group reference")
		largest: f32
		for element in app.groups[expression.group] {
			member := relative(element, expression.attribute)
			largest = max(largest, read(app, &member, depth + 1))
		}
		result += max(expression.minimum, largest + expression.padding)
	}
	return result
}

bounds :: proc(app: ^App, id: Element_ID) -> sdl3.FRect {
	element := &app.elements[id]
	return {
		read(app, &element.position[0]), read(app, &element.position[1]),
		read(app, &element.size[0]), read(app, &element.size[1]),
	}
}

hit_test :: proc(app: ^App, x, y: f32) -> int {
	// Last drawn is on top, so check in reverse order.
	for i := len(app.elements) - 1; i >= 0; i -= 1 {
		if !app.elements[i].visible {
			continue
		}
		r := bounds(app, Element_ID(i))
		if x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h {
			return i
		}
	}
	return -1
}
