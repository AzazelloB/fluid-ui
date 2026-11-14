package fluid

import "core:strings"
import virtual "core:mem/virtual"

@(private="package")
add_element :: proc(scene: ^Scene, definition: Element) -> Element_ID {
	app := scene.ui
	context.allocator = virtual.arena_allocator(&app.storage)
	element := definition
	element.owner = scene
	if element.text_color == (Color{}) {
		element.text_color = {230, 236, 244, 255}
	}
	element.label = strings.clone(definition.label)
	id := register_element(app, element)
	append(&scene.members, id)
	if scene.active {
		activate_element(app, id)
	}
	return id
}

// Retains a copy using UI storage, even if text came from a temporary allocator.
set_label :: proc(app: ^UI, id: Element_ID, text: string) {
	if get_element(app, id).label == text {
		return
	}
	context.allocator = virtual.arena_allocator(&app.storage)
	get_element(app, id).label = strings.clone(text)
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
	element.motion_serial += 1
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
) {
	element := get_element(app, id)
	if element.text_size != size {
		release_text(element)
	}
	element.text_size = size
	element.text_color = color
	element.text_align = align
}
