package fluid

import "vendor:sdl3"

panel :: proc(scene: ^Scene, pins: Pins, color: Color) -> Element_ID {
	return add_element(scene, Element{pins = checked_pins(pins), color = color})
}

button :: proc(scene: ^Scene, pins: Pins, label: string) -> Element_ID {
	return add_element(scene, Element{
		kind = .Button, pins = checked_pins(pins), label = label,
		color = {35, 44, 57, 255},
		style = {radius = 0.625, border = {64, 77, 94, 255}, border_width = 0.0625},
	})
}

draggable_panel :: proc(scene: ^Scene, pins: Pins, color: Color) -> Element_ID {
	return add_element(scene, Element{pins = checked_pins(pins), color = color, draggable = true})
}

label :: proc(scene: ^Scene, pins: Pins, text: string) -> Element_ID {
	return add_element(scene, Element{kind = .Label, pins = checked_pins(pins), label = text})
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
