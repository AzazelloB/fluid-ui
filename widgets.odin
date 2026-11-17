package fluid

panel :: proc(scene: ^Scene, pins: Pins, color: Color) -> Element_ID {
	return add_element(scene, Element{pins = pins, color = color})
}

button :: proc(scene: ^Scene, pins: Pins, label: string) -> Element_ID {
	return add_element(scene, Element{
		kind = .Button, pins = pins, label = label,
		color = {35, 44, 57, 255},
		style = {radius = 0.625, border = {64, 77, 94, 255}, border_width = 0.0625},
	})
}

draggable_panel :: proc(scene: ^Scene, pins: Pins, color: Color) -> Element_ID {
	return add_element(scene, Element{pins = pins, color = color, draggable = true})
}

label :: proc(scene: ^Scene, pins: Pins, text: string) -> Element_ID {
	return add_element(scene, Element{kind = .Label, pins = pins, label = text})
}
