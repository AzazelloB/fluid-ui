package fluid

import virtual "core:mem/virtual"

// Scenes group activation, not geometry. Their lifetime ends with their window.
Scene :: struct {
	ui:      ^UI,
	window:  ^Window,
	members: [dynamic]Element_ID,
	active:  bool,
}

create_scene :: proc(window: ^Window) -> ^Scene {
	assert(window.handle != nil)
	app := window.ui
	context.allocator = virtual.arena_allocator(&window.storage)
	result := new(Scene)
	result.ui = app
	result.window = window
	result.members = make([dynamic]Element_ID)
	append(&window.scenes, result)
	return result
}

activate :: proc(scene: ^Scene) {
	assert(scene.window.handle != nil, "Cannot activate a scene in a closed window")
	if scene.active {
		return
	}
	scene.active = true
	append(&scene.ui.active, ..scene.members[:])
}

deactivate :: proc(scene: ^Scene) {
	if !scene.active {
		return
	}
	for id in scene.members {
		deactivate_element(scene.ui, id)
	}
	scene.active = false
}

// Move the actual element, keeping its ID and animation progress.
// Literal positions and animation origins are rebased to preserve screen space.
transfer :: proc(app: ^UI, id: Element_ID, destination: ^Scene) {
	assert(destination.ui == app && destination.window.handle != nil)
	element := get_element(app, id)
	source := element.owner
	assert(source != nil)
	assert(source.window.handle != nil, "Transfer elements before closing their window")
	if source == destination {
		return
	}
	if source.window != destination.window {
		offset := window_position(source.window) - window_position(destination.window)
		element.pins = translated(element.pins, offset)
		element.motion.from = translated(element.motion.from, offset)
		release_text(element)
	}
	remove_id(&source.members, id)
	append(&destination.members, id)
	element.owner = destination
	if source.active && !destination.active {
		deactivate_element(app, id)
	} else if !source.active && destination.active {
		append(&app.active, id)
	}
}

is_active :: proc(app: ^UI, id: Element_ID) -> bool {
	if !valid(app, id) {
		return false
	}
	scene := app.elements[slot(id)].owner
	return scene != nil && scene.active
}

@(private="package")
deactivate_element :: proc(app: ^UI, id: Element_ID) {
	remove_id(&app.active, id)
	if app.hovered == id {
		app.hovered = NO_ELEMENT
	}
	if app.pressed == id {
		app.pressed = NO_ELEMENT
	}
	if app.drag.element == id {
		end_drag(app)
	}
}

bring_to_front :: proc(app: ^UI, id: Element_ID) {
	if !is_active(app, id) {
		return
	}
	remove_id(&app.active, id)
	append(&app.active, id)
}

@(private="package")
remove_id :: proc(ids: ^[dynamic]Element_ID, id: Element_ID) {
	for value, i in ids^ {
		if value == id {
			ordered_remove(ids, i)
			return
		}
	}
}
