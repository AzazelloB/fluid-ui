package main

import "core:math"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Layout stays in window coordinates. Font glyphs are rasterized at native
// display density, and only the renderer works in physical pixels.
sync_text_density :: proc(app: ^App, window: ^sdl3.Window) {
	density := max(f32(1), sdl3.GetWindowPixelDensity(window))
	if density != app.pixel_density {
		assert(ttf.SetFontSize(app.font, FONT_SIZE * density))
		app.pixel_density = density
	}
}

measure_text :: proc(app: ^App, label: string) -> (f32, f32) {
	width, height: i32
	assert(ttf.GetStringSize(app.font, raw_data(label), len(label), &width, &height))
	return f32(width) / app.pixel_density, f32(height) / app.pixel_density
}

draw_label :: proc(app: ^App, element: ^Element, rect: sdl3.FRect) {
	if element.text == nil {
		element.text = ttf.CreateText(app.text_engine, app.font, raw_data(element.label), len(element.label))
		assert(element.text != nil)
		element.text_label = element.label
	} else if element.label != element.text_label {
		assert(ttf.SetTextString(element.text, raw_data(element.label), len(element.label)))
		element.text_label = element.label
	}
	width, height: i32
	assert(ttf.GetTextSize(element.text, &width, &height))
	scale := app.pixel_density
	x := math.round(rect.x * scale + (rect.w * scale - f32(width)) / 2)
	y := math.round(rect.y * scale + (rect.h * scale - f32(height)) / 2)
	assert(ttf.SetTextColor(element.text, 235, 239, 247, 255))
	assert(ttf.DrawRendererText(element.text, x, y))
}
