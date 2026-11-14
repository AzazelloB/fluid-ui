package fluid

import "vendor:sdl3"

panel :: proc(scene: ^Scene, position, size: [2]Value, color: Color) -> Element_ID {
	return add_element(scene, Element{position = position, size = size, color = color})
}

button :: proc(scene: ^Scene, position, size: [2]Value, label: string) -> Element_ID {
	return add_element(scene, Element{
		kind = .Button, position = position, size = size, label = label,
		color = {35, 44, 57, 255},
		style = {radius = 10, border = {64, 77, 94, 255}, border_width = 1},
	})
}

draggable_panel :: proc(scene: ^Scene, position, size: [2]Value, color: Color, mode: Drag_Mode = .References) -> Element_ID {
	id := panel(scene, position, size, color)
	scene.ui.elements[slot(Element_ID(id))].draggable = true
	scene.ui.elements[slot(Element_ID(id))].drag_mode = mode
	return id
}

label :: proc(scene: ^Scene, position, size: [2]Value, text: string) -> Element_ID {
	return add_element(scene, Element{kind = .Label, position = position, size = size, label = text})
}

@(private="package")
background :: proc(app: ^UI, id: Element_ID) -> sdl3.Color {
	element := get_element(app, id)
	if element.kind == .Button {
		color := element.color
		if element.selected {
			color = {44, 78, 75, 255}
		}
		delta: i32
		if app.pressed == int(id) {
			delta = -8
		} else if app.hovered == int(id) {
			delta = 12
		}
		color.r = u8(clamp(i32(color.r) + delta, 0, 255))
		color.g = u8(clamp(i32(color.g) + delta, 0, 255))
		color.b = u8(clamp(i32(color.b) + delta, 0, 255))
		return color
	}
	return element.color
}
