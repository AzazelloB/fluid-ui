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
	id := Element_ID(len(app.elements))
	append(&app.elements, element)
	append(&scene.members, id)
	if scene.active { activate_element(app, id) }
	return id
}

// Retains a copy using UI storage, even if text came from a temporary allocator.
set_label :: proc(app: ^UI, id: Element_ID, text: string) {
	if app.elements[id].label == text { return }
	context.allocator = virtual.arena_allocator(&app.storage)
	app.elements[id].label = strings.clone(text)
}

set_color :: proc(app: ^UI, id: Element_ID, color: Color) {
	app.elements[id].color = color
}

set_selected :: proc(app: ^UI, id: Element_ID, selected: bool) {
	app.elements[id].selected = selected
}
