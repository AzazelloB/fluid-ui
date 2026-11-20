package elements

import fluid ".."

Control_Palette :: struct {
	fill, border, hover_border, focus, selected, confirmation: fluid.Color,
	field: Field_Text_Style,
}

DEFAULT_CONTROL_PALETTE :: Control_Palette{
	fill = {48, 48, 48, 255}, border = {80, 80, 80, 255},
	hover_border = {112, 112, 112, 255}, focus = {224, 224, 224, 255},
	selected = {96, 96, 96, 255}, confirmation = {224, 224, 224, 100},
	field = DEFAULT_FIELD_TEXT_STYLE,
}

// Apply a control palette while keeping its existing geometry.
set_control_palette :: proc(ui: ^fluid.UI, id: fluid.Element_ID, palette: Control_Palette) {
	control := get_control(ui, id)
	assert(control != nil)
	control.palette = palette
	style := fluid.element_view(ui, id).style
	style.border = palette.border
	if style.hover_border != nil {
		style.hover_border = palette.hover_border
	}
	fluid.set_style(ui, id, style)
	fluid.set_color(ui, id, palette.fill)
}

panel :: proc(window: ^fluid.Window, pins: fluid.Pins, color: fluid.Color) -> fluid.Element_ID {
	return fluid.create_element(window, {pins = pins, color = color, surface = true, draw = draw_default})
}

Button_Variant :: enum {Primary, Secondary}

button :: proc(window: ^fluid.Window, pins: fluid.Pins, label: string,
	variant: Button_Variant = .Primary,
) -> fluid.Element_ID {
	return create_control(window, pins, label, Button_Control{variant = variant})
}

set_button_selected :: proc(ui: ^fluid.UI, id: fluid.Element_ID, selected: bool) {
	state := &get_control(ui, id).state.(Button_Control)
	state.selected = selected
}

set_button_variant :: proc(ui: ^fluid.UI, id: fluid.Element_ID, variant: Button_Variant) {
	state := &get_control(ui, id).state.(Button_Control)
	state.variant = variant
}

@(private="package")
button_definition :: proc(pins: fluid.Pins, label: string) -> fluid.Element_Definition {
	return {
		pins = pins, label = label, color = DEFAULT_CONTROL_PALETTE.fill,
		style = {radius = 0.625, border = DEFAULT_CONTROL_PALETTE.border, border_width = 0.0625},
		surface = true, pressable = true,
	}
}

draggable_panel :: proc(window: ^fluid.Window, pins: fluid.Pins, color: fluid.Color) -> fluid.Element_ID {
	return fluid.create_element(window, {pins = pins, color = color, surface = true, draggable = true, draw = draw_default})
}

label :: proc(window: ^fluid.Window, pins: fluid.Pins, text: string) -> fluid.Element_ID {
	return fluid.create_element(window, {pins = pins, label = text, style = {focus_border = DEFAULT_CONTROL_PALETTE.focus}, draw = draw_default})
}
