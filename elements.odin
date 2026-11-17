package fluid

import "core:mem"
import "core:os"
import "core:strings"

@(private="package")
add_element :: proc(scene: ^Scene, definition: Element) -> Element_ID {
	app := scene.ui
	element := definition
	element.owner = scene
	element.pins = checked_pins(element.pins)
	if element.text_color == (Color{}) {
		element.text_color = {230, 236, 244, 255}
	}
	element.label = strings.clone(definition.label, os.heap_allocator())
	id := register_element(app, element)
	append(&scene.members, id)
	if scene.active {
		append(&app.active, id)
	}
	return id
}

// Retains a copy for the element, even if text came from a temporary allocator.
set_label :: proc(app: ^UI, id: Element_ID, text: string) {
	element := get_element(app, id)
	if element.label == text {
		return
	}
	previous := element.label
	element.label = strings.clone(text, os.heap_allocator())
	update_cached_label(element)
	delete(previous, os.heap_allocator())
}

// Invalidate the ID before recycling its slot. Other elements store values.
remove :: proc(app: ^UI, id: Element_ID) {
	element := get_element(app, id)
	if element.owner != nil {
		remove_id(&element.owner.members, id)
	}
	deactivate_element(app, id)
	remove_id(&app.events, id)
	release_text(element)
	allocator := os.heap_allocator()
	delete(element.label, allocator)
	mem.free(element.press.data, allocator)
	mem.free(element.update.data, allocator)
	generation := element.generation + 1
	element^ = Element{generation = generation}
	append(&app.free_elements, slot(id))
}

set_color :: proc(app: ^UI, id: Element_ID, color: Color) {
	get_element(app, id).color = color
}

set_selected :: proc(app: ^UI, id: Element_ID, selected: bool) {
	get_element(app, id).selected = selected
}

set_layout :: proc(app: ^UI, id: Element_ID, pins: Pins) {
	element := get_element(app, id)
	element.pins = checked_pins(pins)
	element.motion = {}
}

// Update numeric destination pins without restarting an in-flight animation.
set_target :: proc(app: ^UI, id: Element_ID, pins: Pins) {
	get_element(app, id).pins = checked_pins(pins)
}

element_window :: proc(app: ^UI, id: Element_ID) -> ^Window {
	return coordinate_window(get_element(app, id))
}

set_style :: proc(app: ^UI, id: Element_ID, style: Style) {
	get_element(app, id).style = style
}

set_text_style :: proc(app: ^UI, id: Element_ID, size: Text_Size = .Body,
	color: Color = {230, 236, 244, 255}, align: Text_Align = .Center,
	weight: Text_Weight = .Regular,
) {
	element := get_element(app, id)
	if element.text_size != size || element.text_weight != weight {
		release_text(element)
	}
	element.text_size = size
	element.text_color = color
	element.text_align = align
	element.text_weight = weight
}

// Wrapped text starts at the top of its bounds and is clipped to them.
set_text_wrap :: proc(app: ^UI, id: Element_ID, wrap: bool = true) {
	get_element(app, id).text_wrap = wrap
}
