package fluid

import "core:math"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

@(private="package")
DEFAULT_TEXT_COLOR :: Color{230, 236, 244, 255}

@(private="package")
create_text_resources :: proc(window: ^Window_Resources) -> bool {
	for size in Text_Size {
		pixels := font_pixels(size, window.pixel_density)
		font := ttf.OpenFont("/System/Library/Fonts/SFNS.ttf", pixels)
		if font == nil {
			font = ttf.OpenFont("/System/Library/Fonts/Supplemental/Arial.ttf", pixels)
		}
		if font == nil {
			return false
		}
		window.fonts[.Regular][size] = font
		bold := ttf.CopyFont(font)
		if bold == nil {
			return false
		}
		ttf.SetFontStyle(bold, {.BOLD})
		window.fonts[.Bold][size] = bold
	}
	window.text_engine = ttf.CreateRendererTextEngine(window.renderer)
	return window.text_engine != nil
}

@(private="package")
release_text_resources :: proc(window: ^Window_Resources) {
	if window.text_engine != nil {
		ttf.DestroyRendererTextEngine(window.text_engine)
	}
	for sizes in window.fonts {
		for font in sizes {
			if font != nil {
				ttf.CloseFont(font)
			}
		}
	}
}

@(private="file")
font_pixels :: proc(size: Text_Size, density: f32) -> f32 {
	return text_size_units(size) * UI_UNIT_POINTS * density
}

// Layout and measurements stay in font-relative UI units. Only the SDL
// boundary works in logical points or physical pixels.
@(private="package")
sync_text_density :: proc(window: ^Window) {
	density := max(f32(1), sdl3.GetWindowPixelDensity(window.handle))
	if density != window.pixel_density {
		for weight in Text_Weight {
			for size in Text_Size {
				assert(ttf.SetFontSize(window.fonts[weight][size], font_pixels(size, density)))
			}
		}
		window.pixel_density = density
	}
}

@(private="file")
wrap_width_pixels :: proc(width, scale: f32) -> i32 {
	return max(i32(1), i32(width * scale))
}

measure_text :: proc(window: ^Window, label: string, size: Text_Size = .Body,
	weight: Text_Weight = .Regular, wrap_width: f32 = 0,
) -> (f32, f32) {
	pixel_width, pixel_height: i32
	scale := pixel_scale(window)
	font := window.fonts[weight][size]
	if wrap_width > 0 {
		assert(ttf.GetStringSizeWrapped(font, raw_data(label), len(label),
			wrap_width_pixels(wrap_width, scale), &pixel_width, &pixel_height))
	} else {
		assert(ttf.GetStringSize(font, raw_data(label), len(label), &pixel_width, &pixel_height))
	}
	return f32(pixel_width) / scale, f32(pixel_height) / scale
}

text_line_height :: proc(window: ^Window, size: Text_Size = .Body, weight: Text_Weight = .Regular) -> f32 {
	scale := pixel_scale(window)
	return f32(ttf.GetFontLineSkip(window.fonts[weight][size])) / scale
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
		font := window.fonts[element.text_weight][element.text_size]
		element.text = ttf.CreateText(window.text_engine, font, raw_data(element.label), len(element.label))
		assert(element.text != nil)
	}
	scale := pixel_scale(window)
	wrap_pixels: i32
	if element.text_wrap {
		wrap_pixels = wrap_width_pixels(width(rect), scale)
	}
	previous_wrap: i32
	assert(ttf.GetTextWrapWidth(element.text, &previous_wrap))
	if wrap_pixels != previous_wrap {
		assert(ttf.SetTextWrapWidth(element.text, wrap_pixels))
	}
	pixel_width, pixel_height: i32
	assert(ttf.GetTextSize(element.text, &pixel_width, &pixel_height))
	x := rect.left * scale
	switch element.text_align {
	case .Left:
	case .Center: x += (width(rect) * scale - f32(pixel_width)) / 2
	case .Right: x = rect.right * scale - f32(pixel_width)
	}
	color := element.text_color
	assert(ttf.SetTextColor(element.text, color.r, color.g, color.b, color.a))
	if element.text_wrap {
		draw_wrapped_label(window, element.text, rect, math.round(x), scale)
	} else {
		y := math.round(rect.top * scale + (height(rect) * scale - f32(pixel_height)) / 2)
		assert(ttf.DrawRendererText(element.text, math.round(x), y))
	}
}

@(private="package")
draw_wrapped_label :: proc(window: ^Window, text: ^ttf.Text, rect: Pins, x, scale: f32) {
	renderer := window.renderer
	left := i32(math.round(rect.left * scale))
	top := i32(math.round(rect.top * scale))
	clip := sdl3.Rect{left, top, max(i32(0), i32(math.round(rect.right * scale)) - left),
		max(i32(0), i32(math.round(rect.bottom * scale)) - top)}
	assert(sdl3.SetRenderClipRect(renderer, &clip))
	assert(ttf.DrawRendererText(text, x, f32(top)))
	assert(sdl3.SetRenderClipRect(renderer, nil))
}

@(private="package")
release_text :: proc(element: ^Element) {
	if element.text != nil {
		ttf.DestroyText(element.text)
	}
	element.text = nil
}

// Cached labels belong to the text engine that drew them.
@(private="package")
release_window_text :: proc(window: ^Window) {
	for scene in window.scenes {
		for id in scene.members {
			release_text(get_element(window.ui, id))
		}
	}
}
