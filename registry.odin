package fluid

@(private="package")
slot :: proc(id: Element_ID) -> int {
	return int(u64(id) & 0xffff_ffff)
}

valid :: proc(app: ^UI, id: Element_ID) -> bool {
	i := slot(id)
	return i < len(app.elements) && app.elements[i].alive &&
		app.elements[i].generation == u32(u64(id) >> 32)
}

@(private="package")
get_element :: proc(app: ^UI, id: Element_ID) -> ^Element {
	assert(valid(app, id), "Invalid or expired element reference")
	return &app.elements[slot(id)]
}

@(private="package")
register_element :: proc(app: ^UI, definition: Element) -> Element_ID {
	i := len(app.elements)
	element := definition
	element.alive = true
	if len(app.free_elements) > 0 {
		i = pop(&app.free_elements)
		element.generation = app.elements[i].generation
		app.elements[i] = element
	} else {
		append(&app.elements, element)
	}
	assert(element.generation < 0x8000_0000, "Element generation exhausted")
	return Element_ID(u64(i) | (u64(element.generation) << 32))
}

@(private="package")
coordinate_window :: proc(element: ^Element) -> ^Window {
	if element.owner != nil {
		return element.owner.window
	}
	return element.space
}
