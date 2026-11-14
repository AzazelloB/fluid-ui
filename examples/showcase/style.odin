package main

import fluid "../.."

INK :: fluid.Color{230, 237, 245, 255}
MUTED :: fluid.Color{139, 157, 178, 255}
MINT :: fluid.Color{143, 225, 196, 255}
SURFACE :: fluid.Color{24, 33, 45, 255}
EDGE :: fluid.Color{46, 60, 77, 255}

// Shared presentation helpers; each demo owns its layout and behavior.
demo_text :: proc(scene: ^fluid.Scene, pins: fluid.Pins, text: string,
	font: fluid.Text_Size = .Body, color: fluid.Color = INK, align: fluid.Text_Align = .Left,
) -> fluid.Element_ID {
	id := fluid.label(scene, pins, text)
	fluid.set_text_style(scene.ui, id, font, color, align)
	return id
}

demo_surface :: proc(scene: ^fluid.Scene, pins: fluid.Pins, color: fluid.Color = SURFACE,
	radius: f32 = 1, shadow: f32 = 0,
) -> fluid.Element_ID {
	id := fluid.panel(scene, pins, color)
	fluid.set_style(scene.ui, id, {radius = radius, border = EDGE, border_width = 0.0625, shadow = shadow})
	return id
}
