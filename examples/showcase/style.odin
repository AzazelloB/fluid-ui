package main

import fluid "../.."
import "../../elements"

TEXT_BODY :: f32(1)
TEXT_CAPTION :: f32(0.8)
TEXT_HEADING :: f32(1.5)

WINDOW_BACKGROUND :: fluid.Color{17, 23, 32, 255}
WINDOW_TEXT :: fluid.Color{230, 236, 244, 255}

INK :: fluid.Color{230, 237, 245, 255}
MUTED :: fluid.Color{139, 157, 178, 255}
MINT :: fluid.Color{143, 225, 196, 255}
SURFACE :: fluid.Color{24, 33, 45, 255}
EDGE :: fluid.Color{46, 60, 77, 255}

CONTROL_PALETTE :: elements.Control_Palette{
	fill = {35, 44, 57, 255}, border = {64, 77, 94, 255},
	hover_border = {98, 112, 129, 255}, focus = MINT,
	selected = {44, 78, 75, 255}, confirmation = {238, 157, 133, 100},
	field = {placeholder = MUTED, selection = {74, 117, 142, 255}, caret = {174, 230, 213, 255}},
}

SCROLL_TRACK :: fluid.Color{30, 42, 57, 255}

// Shared presentation helpers; each demo owns its layout and behavior.
demo_control :: proc(window: ^fluid.Window, id: fluid.Element_ID) -> fluid.Element_ID {
	elements.set_control_palette(window.ui, id, CONTROL_PALETTE)
	return id
}

demo_text :: proc(window: ^fluid.Window, pins: fluid.Pins, text: string,
	font: f32 = TEXT_BODY, color: fluid.Color = INK, align: fluid.Text_Align = .Left,
	weight: fluid.Text_Weight = .Regular,
) -> fluid.Element_ID {
	id := elements.label(window, pins, text)
	fluid.set_text_style(window.ui, id, font, color, align, weight)
	return id
}

demo_surface :: proc(window: ^fluid.Window, pins: fluid.Pins, color: fluid.Color = SURFACE,
	radius: f32 = 1,
) -> fluid.Element_ID {
	id := elements.panel(window, pins, color)
	fluid.set_style(window.ui, id, {radius = radius, border = EDGE, border_width = 0.0625})
	return id
}

// The showcase paints the field chrome and reuses the stock editing layer.
demo_field_style :: proc(view: fluid.Element_View) {
	view := view
	view.style = {
		radius = 0.375, border = EDGE, border_width = 0.0625,
		hover_border = MUTED, focus_border = MINT,
	}
	view.color = SURFACE
	elements.draw_field(view, {placeholder = MUTED, selection = {47, 86, 83, 255}, caret = MINT})
}
