package main

import fluid "../.."
import "../../elements"

TEXT_SMALL :: f32(0.72)
TEXT_BODY :: f32(0.875)

WINDOW_BACKGROUND :: fluid.Color{15, 24, 22, 255}
SURFACE :: fluid.Color{24, 38, 33, 255}
INSET :: fluid.Color{14, 26, 22, 255}
EDGE :: fluid.Color{52, 71, 59, 255}
INK :: fluid.Color{241, 247, 232, 255}
MUTED :: fluid.Color{164, 184, 170, 255}
LIME :: fluid.Color{210, 246, 147, 255}
JADE :: fluid.Color{112, 231, 194, 255}
HONEY :: fluid.Color{255, 198, 116, 255}
CLAY :: fluid.Color{247, 163, 141, 255}
DARK_INK :: fluid.Color{28, 44, 21, 255}

FIELD_PALETTE :: elements.Control_Palette{
	fill = {32, 47, 41, 255}, border = EDGE,
	hover_border = MUTED, focus = LIME, selected = {44, 64, 52, 255},
	field = {placeholder = MUTED, selection = {61, 105, 84, 255}, caret = LIME},
}

field_control :: proc(window: ^fluid.Window, id: fluid.Element_ID, size: f32 = TEXT_SMALL) -> fluid.Element_ID {
	elements.set_control_palette(window.ui, id, FIELD_PALETTE)
	fluid.set_text_style(window.ui, id, size, INK)
	return id
}

field_button :: proc(window: ^fluid.Window, title: string, variant: elements.Button_Variant = .Primary) -> fluid.Element_ID {
	return field_control(window, elements.button(window, {}, title, variant))
}

field_text :: proc(window: ^fluid.Window, text: string, size: f32 = TEXT_BODY,
	color: fluid.Color = INK, weight: fluid.Text_Weight = .Regular, align: fluid.Text_Align = .Left,
) -> fluid.Element_ID {
	id := elements.label(window, {}, text)
	fluid.set_text_style(window.ui, id, size, color, align, weight)
	return id
}

field_panel :: proc(window: ^fluid.Window, color: fluid.Color = SURFACE, radius: f32 = 0.75) -> fluid.Element_ID {
	id := elements.panel(window, {}, color)
	fluid.set_style(window.ui, id, {radius = radius, border = EDGE, border_width = 0.0625})
	return id
}
