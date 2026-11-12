package fluid

import "core:strings"
import virtual "core:mem/virtual"

@(private="package")
add_element :: proc(scene: ^Scene, definition: Element) -> Element_ID {
	app := scene.ui
	context.allocator = virtual.arena_allocator(&app.storage)
	element := definition
	element.owner = scene
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

set_layout :: proc(app: ^UI, id: Element_ID, position, size: [2]Value) {
	element := get_element(app, id)
	element.position = position
	element.size = size
	element.motion = {}
}

element_window :: proc(app: ^UI, id: Element_ID) -> ^Window {
	return coordinate_window(get_element(app, id))
}
