package main

import fluid "../.."
import "../../elements"

INK :: fluid.Color{230, 237, 245, 255}
MUTED :: fluid.Color{139, 157, 178, 255}
MINT :: fluid.Color{143, 225, 196, 255}
SURFACE :: fluid.Color{24, 33, 45, 255}
EDGE :: fluid.Color{46, 60, 77, 255}

// Shared presentation helpers; each demo owns its layout and behavior.
demo_text :: proc(scene: ^fluid.Scene, pins: fluid.Pins, text: string,
	font: fluid.Text_Size = .Body, color: fluid.Color = INK, align: fluid.Text_Align = .Left,
	weight: fluid.Text_Weight = .Regular,
) -> fluid.Element_ID {
	id := elements.label(scene, pins, text)
	fluid.set_text_style(scene.ui, id, font, color, align, weight)
	return id
}

demo_surface :: proc(scene: ^fluid.Scene, pins: fluid.Pins, color: fluid.Color = SURFACE,
	radius: f32 = 1,
) -> fluid.Element_ID {
	id := elements.panel(scene, pins, color)
	fluid.set_style(scene.ui, id, {radius = radius, border = EDGE, border_width = 0.0625})
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
