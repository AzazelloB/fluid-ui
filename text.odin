package fluid

import "core:math"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Layout stays in window coordinates. Font glyphs are rasterized at native
// display density, and only the renderer works in physical pixels.
@(private="package")
sync_text_density :: proc(window: ^Window) {
	density := max(f32(1), sdl3.GetWindowPixelDensity(window.handle))
	if density != window.pixel_density {
		for size in Text_Size {
			assert(ttf.SetFontSize(window.fonts[size], text_size_points(size) * density))
		}
		window.pixel_density = density
	}
}

measure_text :: proc(window: ^Window, label: string, size: Text_Size = .Body) -> (f32, f32) {
	width, height: i32
	assert(ttf.GetStringSize(window.fonts[size], raw_data(label), len(label), &width, &height))
	return f32(width) / window.pixel_density, f32(height) / window.pixel_density
}

@(private="package")
draw_label :: proc(window: ^Window, element: ^Element, rect: sdl3.FRect) {
	if element.text == nil {
		element.text = ttf.CreateText(window.text_engine, window.fonts[element.text_size], raw_data(element.label), len(element.label))
		assert(element.text != nil)
		element.text_label = element.label
	} else if element.label != element.text_label {
		assert(ttf.SetTextString(element.text, raw_data(element.label), len(element.label)))
		element.text_label = element.label
	}
	width, height: i32
	assert(ttf.GetTextSize(element.text, &width, &height))
	scale := window.pixel_density
	x := math.round(rect.x * scale + (rect.w * scale - f32(width)) / 2)
	y := math.round(rect.y * scale + (rect.h * scale - f32(height)) / 2)
	if element.text_align == .Left {
		x = math.round(rect.x * scale)
	}
	color := element.text_color
	assert(ttf.SetTextColor(element.text, color.r, color.g, color.b, color.a))
	assert(ttf.DrawRendererText(element.text, x, y))
}

@(private="package")
release_text :: proc(element: ^Element) {
	if element.text != nil {
		ttf.DestroyText(element.text)
	}
	element.text = nil
	element.text_label = ""
}
