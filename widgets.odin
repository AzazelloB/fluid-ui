package main

import "vendor:sdl3"

panel :: proc(app: ^App, position, size: [2]Value, color: sdl3.Color) -> Element_ID {
	return add_element(app, Element{position = position, size = size, color = color, visible = true})
}

button :: proc(app: ^App, position, size: [2]Value, label: string, on_press: Press_Action = nil) -> Element_ID {
	return add_element(app, Element{
		kind = .Button, position = position, size = size, label = label,
		color = {48, 54, 66, 255}, visible = true, on_press = on_press,
	})
}

draggable_panel :: proc(app: ^App, position, size: [2]Value, color: sdl3.Color) -> Element_ID {
	id := panel(app, position, size, color)
	app.elements[id].draggable = true
	return id
}

background :: proc(app: ^App, id: Element_ID) -> sdl3.Color {
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
