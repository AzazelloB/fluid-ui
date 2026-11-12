package fluid

import virtual "core:mem/virtual"
import ttf "vendor:sdl3/ttf"

// Scenes group activation, not geometry. They start inactive and live until
// destroy(ui); individual elements record their membership automatically.
Scene :: struct {
	ui: ^UI,
	members: [dynamic]Element_ID,
	active: bool,
}

create_scene :: proc(app: ^UI) -> ^Scene {
	context.allocator = virtual.arena_allocator(&app.storage)
	result := new(Scene)
	result.ui = app
	result.members = make([dynamic]Element_ID)
	return result
}

activate :: proc(scene: ^Scene) {
	if scene.active { return }
	scene.active = true
	for id in scene.members { activate_element(scene.ui, id) }
}

deactivate :: proc(scene: ^Scene) {
	if !scene.active { return }
	for id in scene.members { deactivate_element(scene.ui, id) }
	scene.active = false
}

// Detach membership and release native text. Layout data stays addressable
// until the UI session ends, so references to its geometry remain valid.
remove :: proc(app: ^UI, id: Element_ID) {
	element := &app.elements[id]
	if element.owner != nil {
		remove_id(&element.owner.members, id)
		element.owner = nil
	}
	deactivate_element(app, id)
	if element.text != nil {
		ttf.DestroyText(element.text)
		element.text = nil
	}
}

is_active :: proc(app: ^UI, id: Element_ID) -> bool {
	for active in app.active { if active == id { return true } }
	return false
}

@(private="package")
activate_element :: proc(app: ^UI, id: Element_ID) {
	if !is_active(app, id) { append(&app.active, id) }
}

@(private="package")
deactivate_element :: proc(app: ^UI, id: Element_ID) {
	remove_id(&app.active, id)
	if app.hovered == int(id) { app.hovered = -1 }
	if app.pressed == int(id) { app.pressed = -1 }
	if app.dragged == int(id) { app.dragged = -1 }
}

@(private="package")
remove_id :: proc(ids: ^[dynamic]Element_ID, id: Element_ID) {
	for value, i in ids^ {
		if value == id { ordered_remove(ids, i); return }
	}
}

group :: proc(app: ^UI) -> Group_ID {
	context.allocator = virtual.arena_allocator(&app.storage)
	id := Group_ID(len(app.groups))
	append(&app.groups, make([dynamic]Element_ID))
	return id
}

include :: proc(app: ^UI, group: Group_ID, element: Element_ID) {
	for member in app.groups[group] {
		if member == element { return }
	}
	append(&app.groups[group], element)
}
