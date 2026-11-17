package fluid

import "core:math"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Layout and measurements stay in font-relative UI units. Only the SDL
// boundary works in logical points or physical pixels.
@(private="package")
sync_text_density :: proc(window: ^Window) {
	density := max(f32(1), sdl3.GetWindowPixelDensity(window.handle))
	if density != window.pixel_density || window.font_unit_size != window.ui.base_font_size {
		for size in Text_Size {
			assert(ttf.SetFontSize(window.fonts[size], text_size_units(size) * window.ui.base_font_size * density))
		}
		window.pixel_density = density
		window.font_unit_size = window.ui.base_font_size
	}
}

measure_text :: proc(window: ^Window, label: string, size: Text_Size = .Body) -> (f32, f32) {
	pixel_width, pixel_height: i32
	assert(ttf.GetStringSize(window.fonts[size], raw_data(label), len(label), &pixel_width, &pixel_height))
	scale := window.pixel_density * window.ui.base_font_size
	return f32(pixel_width) / scale, f32(pixel_height) / scale
}

@(private="package")
update_cached_label :: proc(element: ^Element) {
	if element.text == nil {
		return
	}
	if len(element.label) == 0 {
		release_text(element)
		return
	}
	assert(ttf.SetTextString(element.text, raw_data(element.label), len(element.label)))
}

@(private="package")
draw_label :: proc(window: ^Window, element: ^Element, rect: Pins) {
	if element.text == nil {
		element.text = ttf.CreateText(window.text_engine, window.fonts[element.text_size], raw_data(element.label), len(element.label))
		assert(element.text != nil)
	}
	pixel_width, pixel_height: i32
	assert(ttf.GetTextSize(element.text, &pixel_width, &pixel_height))
	scale := window.pixel_density * window.ui.base_font_size
	x := math.round(rect.left * scale + (width(rect) * scale - f32(pixel_width)) / 2)
	y := math.round(rect.top * scale + (height(rect) * scale - f32(pixel_height)) / 2)
	if element.text_align == .Left {
		x = math.round(rect.left * scale)
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
}
