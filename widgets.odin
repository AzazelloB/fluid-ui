package fluid

import "vendor:sdl3"

panel :: proc(scene: ^Scene, position, size: [2]Value, color: Color) -> Element_ID {
	return add_element(scene, Element{position = position, size = size, color = color})
}

button :: proc(scene: ^Scene, position, size: [2]Value, label: string) -> Element_ID {
	return add_element(scene, Element{
		kind = .Button, position = position, size = size, label = label,
		color = {48, 54, 66, 255},
	})
}

draggable_panel :: proc(scene: ^Scene, position, size: [2]Value, color: Color) -> Element_ID {
	id := panel(scene, position, size, color)
	scene.ui.elements[id].draggable = true
	return id
}

label :: proc(scene: ^Scene, position, size: [2]Value, text: string) -> Element_ID {
	return add_element(scene, Element{kind = .Label, position = position, size = size, label = text})
}

@(private="package")
background :: proc(app: ^UI, id: Element_ID) -> sdl3.Color {
	element := &app.elements[id]
	if element.kind == .Button {
		if app.pressed == int(id) {
			return {60, 90, 140, 255}
		}
		if element.selected {
			if app.hovered == int(id) {
				return {58, 92, 142, 255}
			}
			return {48, 78, 124, 255}
		}
		if app.hovered == int(id) {
			return {65, 73, 89, 255}
		}
	}
	return element.color
}
