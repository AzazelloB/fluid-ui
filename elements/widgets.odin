package elements

import fluid ".."

FOCUS_BORDER :: fluid.Color{143, 225, 196, 255}

panel :: proc(window: ^fluid.Window, pins: fluid.Pins, color: fluid.Color) -> fluid.Element_ID {
	return fluid.create_element(window, {pins = pins, color = color, surface = true})
}

Button_Variant :: enum {Primary, Secondary}

button :: proc(window: ^fluid.Window, pins: fluid.Pins, label: string,
	variant: Button_Variant = .Primary,
) -> fluid.Element_ID {
	return create_control(window, pins, label, Button_Control{variant = variant})
}

set_button_variant :: proc(ui: ^fluid.UI, id: fluid.Element_ID, variant: Button_Variant) {
	state := &get_control(ui, id).state.(Button_Control)
	state.variant = variant
}

@(private="package")
button_definition :: proc(pins: fluid.Pins, label: string) -> fluid.Element_Definition {
	return {
		pins = pins, label = label, color = {35, 44, 57, 255},
		style = {radius = 0.625, border = {64, 77, 94, 255}, border_width = 0.0625},
		surface = true, pressable = true,
	}
}

@(private="package")
button_style :: proc(style: fluid.Style) -> fluid.Style {
	result := style
	if result.focus_border == nil {
		result.focus_border = FOCUS_BORDER
	}
	return result
}

draggable_panel :: proc(window: ^fluid.Window, pins: fluid.Pins, color: fluid.Color) -> fluid.Element_ID {
	return fluid.create_element(window, {pins = pins, color = color, surface = true, draggable = true})
}

label :: proc(window: ^fluid.Window, pins: fluid.Pins, text: string) -> fluid.Element_ID {
	return fluid.create_element(window, {pins = pins, label = text, style = {focus_border = FOCUS_BORDER}})
}
