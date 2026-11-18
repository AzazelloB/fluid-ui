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

// Borrow the window font for the requested style.
text_font :: proc(window: ^Window, size: Text_Size, weight: Text_Weight) -> ^ttf.Font {
	return window.fonts[weight][size]
}

// Cached text tied to an element follows its style and renderer lifetime.
element_text :: proc(view: Element_View, placeholder: string = "") -> ^ttf.Text {
	element := get_element(view.ui, view.id)
	content := element.label != "" ? element.label : placeholder
	if content == "" {
		return nil
	}
	return cached_text(view.window, &element.text, text_font(view.window, element.text_size, element.text_weight), content)
}

// Create a renderer text object on first use.
cached_text :: proc(window: ^Window, cache: ^^ttf.Text, font: ^ttf.Font, label: string) -> ^ttf.Text {
	if cache^ == nil {
		cache^ = ttf.CreateText(window.text_engine, font, raw_data(label), len(label))
	}
	return cache^
}

@(private="package")
update_cached_text :: proc(cache: ^^ttf.Text, label: string) {
	if cache^ == nil {
		return
	}
	if label == "" {
		release_cached_text(cache)
		return
	}
	assert(ttf.SetTextString(cache^, raw_data(label), len(label)))
}

// Set a text object’s wrap width in physical pixels.
set_wrap_width :: proc(text: ^ttf.Text, pixels: i32) -> bool {
	previous: i32
	return ttf.GetTextWrapWidth(text, &previous) &&
		(previous == pixels || ttf.SetTextWrapWidth(text, pixels))
}

// Draw text at a physical pixel position.
paint_text :: proc(text: ^ttf.Text, color: Color, x, y: f32) -> bool {
	colored := ttf.SetTextColor(text, color.r, color.g, color.b, color.a)
	drawn := ttf.DrawRendererText(text, x, y)
	return colored && drawn
}

// Draw text in UI-unit bounds with alignment and wrapping.
draw_label :: proc(window: ^Window, text: ^ttf.Text, rect: Pins, color: Color,
	align: Text_Align = .Center, wrap: bool = false,
) {
	assert(text != nil)
	scale := pixel_scale(window)
	assert(set_wrap_width(text, wrap ? wrap_width_pixels(width(rect), scale) : 0))
	pixel_width, pixel_height: i32
	assert(ttf.GetTextSize(text, &pixel_width, &pixel_height))
	x := rect.left * scale
	switch align {
	case .Left:
	case .Center: x += (width(rect) * scale - f32(pixel_width)) / 2
	case .Right: x = rect.right * scale - f32(pixel_width)
	}
	if wrap {
		renderer := window.renderer
		left := i32(math.round(rect.left * scale))
		top := i32(math.round(rect.top * scale))
		clip := sdl3.Rect{left, top, max(i32(0), i32(math.round(rect.right * scale)) - left),
			max(i32(0), i32(math.round(rect.bottom * scale)) - top)}
		assert(sdl3.SetRenderClipRect(renderer, &clip))
		assert(paint_text(text, color, math.round(x), f32(top)))
		assert(sdl3.SetRenderClipRect(renderer, nil))
	} else {
		y := math.round(rect.top * scale + (height(rect) * scale - f32(pixel_height)) / 2)
		assert(paint_text(text, color, math.round(x), y))
	}
}

// Release text before its renderer or font is replaced.
release_cached_text :: proc(cache: ^^ttf.Text) {
	if cache^ != nil {
		ttf.DestroyText(cache^)
		cache^ = nil
	}
}

// Cached labels belong to the text engine that drew them.
@(private="package")
release_window_text :: proc(window: ^Window) {
	for scene in window.scenes {
		for id in scene.members {
			release_element_text(get_element(window.ui, id))
		}
	}
}

@(private="package")
release_element_text :: proc(element: ^Element) {
	release_cached_text(&element.text)
	if element.behavior.release_graphics != nil {
		element.behavior.release_graphics(element.behavior.state)
	}
}
