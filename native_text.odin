package fluid

import "core:math"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

// Text owns the source, the platform layout, and a lazily rasterized mask.
// All offsets exported to controls are UTF-8 byte offsets.
Text :: struct {
	label: string,
	pixels: f32,
	bold: bool,
	wrap: i32,
	utf16: []u16,
	byte_offsets: []i32,
	layout: Native_Text_Layout,
	prepared, ink_measured: bool,
	ink: IRect,
	mask: []u8,
	mask_rect: IRect,
}

Text_Span :: struct {
	offset, length, line_index: i32,
	rect: IRect,
}

@(private="file")
Font_Metric :: struct {
	pixels: f32,
	bold: bool,
	height, line_height: i32,
	advance: f64,
}

@(private="file", thread_local)
font_metrics: [16]Font_Metric
@(private="file", thread_local)
next_font_metric: int

@(private="package")
reset_text_font_metrics :: proc() {
	font_metrics = {}
	next_font_metric = 0
}

text_font_metrics :: proc(pixels: f32, bold: bool) -> (height, line_height: i32) {
	metric := text_font_metric(pixels, bold)
	return metric.height, metric.line_height
}

// Baseline spacing in physical pixels, before rounding to a pixel boundary.
text_line_advance :: proc(font: Text_Style) -> f64 {
	return text_font_metric(font.pixels, font.bold).advance
}

@(private="file")
text_font_metric :: proc(pixels: f32, bold: bool) -> Font_Metric {
	for metric in font_metrics {
		if metric.height > 0 && metric.pixels == pixels && metric.bold == bold {
			return metric
		}
	}
	height, line_height, advance := platform_text_font_metrics(pixels, bold)
	metric := Font_Metric{pixels, bold, height, line_height, advance}
	font_metrics[next_font_metric] = metric
	next_font_metric = (next_font_metric + 1) % len(font_metrics)
	return metric
}

@(private="package")
native_text_create :: proc(label: string, pixels: f32, bold: bool) -> ^Text {
	text := new(Text, os.heap_allocator())
	text.pixels, text.bold = pixels, bold
	native_text_set_string(text, label)
	return text
}

@(private="package")
native_text_destroy :: proc(text: ^Text) {
	if text == nil {
		return
	}
	clear_text_layout(text)
	delete(text.label, os.heap_allocator())
	delete(text.utf16, os.heap_allocator())
	delete(text.byte_offsets, os.heap_allocator())
	free(text, os.heap_allocator())
}

@(private="package")
native_text_set_string :: proc(text: ^Text, label: string) {
	if text.label == label && text.byte_offsets != nil {
		return
	}
	allocator := os.heap_allocator()
	owned := strings.clone(label, allocator)
	clear_text_layout(text)
	delete(text.label, allocator)
	delete(text.utf16, allocator)
	delete(text.byte_offsets, allocator)
	text.label = owned
	text.utf16 = make([]u16, len(owned) + 1, allocator)
	text.byte_offsets = make([]i32, len(owned) + 1, allocator)
	units := 0
	for offset := 0; offset < len(owned); {
		r, length := utf8.decode_rune_in_string(owned[offset:])
		text.byte_offsets[units] = i32(offset)
		if r >= 0x10000 {
			r -= 0x10000
			text.utf16[units] = 0xd800 + u16(r >> 10)
			units += 1
			text.byte_offsets[units] = i32(offset)
			text.utf16[units] = 0xdc00 + u16(r & 0x3ff)
		} else {
			text.utf16[units] = u16(r)
		}
		units += 1
		offset += length
	}
	text.byte_offsets[units] = i32(len(owned))
	text.utf16 = text.utf16[:units]
	text.byte_offsets = text.byte_offsets[:units + 1]
}

set_wrap_width :: proc(text: ^Text, width: i32) -> bool {
	width := max(0, width)
	if text.wrap != width {
		clear_text_layout(text)
		text.wrap = width
	}
	return prepare_text(text)
}

text_dimensions :: proc(text: ^Text) -> [2]i32 {
	if !prepare_text(text) {
		return {}
	}
	return text.layout.dimensions
}

text_span :: proc(text: ^Text, offset: i32, out: ^Text_Span) -> bool {
	return prepare_text(text) && platform_text_span(text, text_to_utf16(text, offset), out)
}

text_line :: proc(text: ^Text, line: i32, out: ^Text_Span) -> bool {
	return prepare_text(text) && platform_text_line(text, line, out)
}

// Returns the insertion offset and optionally the cluster under the point.
text_hit :: proc(text: ^Text, x, y: i32, cluster: ^Text_Span = nil) -> (i32, bool) {
	if !prepare_text(text) {
		return 0, false
	}
	span: Text_Span
	out := cluster != nil ? cluster : &span
	hit := platform_text_hit(text, x, y, out)
	return hit.caret, hit.ok
}

text_range :: proc(text: ^Text, offset, length: i32) -> []IRect {
	if !prepare_text(text) || length <= 0 {
		return nil
	}
	start := text_to_utf16(text, offset)
	end := text_to_utf16(text, offset + length)
	if start >= end {
		return nil
	}
	return platform_text_range(text, start, end)
}

@(private="package")
native_text_mask :: proc(text: ^Text, visible: IRect) -> (offset, size: [2]i32, alpha: []u8) {
	if !prepare_text(text) || text.label == "" {
		return {}, {}, nil
	}
	if !text.ink_measured {
		text.ink = text_ink_bounds(text)
		text.ink_measured = true
	}
	ink := intersect_pixels(text.ink, visible)
	if ink.w == 0 || ink.h == 0 {
		return {}, {}, nil
	}
	cache := text.mask_rect
	if intersect_pixels(ink, cache) != ink {
		// Keep complete labels cached. For larger text, retain the visible area
		// with a margin so short scrolls can reuse the same rasterization.
		if text.ink.w <= 2048 && text.ink.h <= 2048 {
			ink = text.ink
		} else {
			margin :: 96
			ink = intersect_pixels(text.ink, {ink.x - margin, ink.y - margin, ink.w + 2 * margin, ink.h + 2 * margin})
		}
		mask := rasterize_text(text, ink)
		if len(mask) == 0 {
			return {}, {}, nil
		}
		delete(text.mask, os.heap_allocator())
		text.mask = mask
		text.mask_rect = ink
		cache = ink
	}
	return {cache.x, cache.y}, {cache.w, cache.h}, text.mask
}

@(private="package")
Text_Hit :: struct {
	caret: i32,
	ok: bool,
}

@(private="file")
prepare_text :: proc(text: ^Text) -> bool {
	if !text.prepared {
		text.prepared = create_text_layout(text)
	}
	return text.prepared
}

@(private="file")
clear_text_layout :: proc(text: ^Text) {
	if text.prepared {
		destroy_text_layout(text)
		text.prepared = false
	}
	delete(text.mask, os.heap_allocator())
	text.mask = nil
	text.ink, text.mask_rect = {}, {}
	text.ink_measured = false
}

@(private="package")
text_to_utf16 :: proc(text: ^Text, byte: i32) -> i32 {
	byte := clamp(byte, 0, i32(len(text.label)))
	lo, hi := 0, len(text.byte_offsets)
	for lo < hi {
		mid := lo + (hi - lo) / 2
		if text.byte_offsets[mid] < byte {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo > 0 && text.byte_offsets[lo] > byte {
		lo -= 1
		if lo > 0 && text.byte_offsets[lo] == text.byte_offsets[lo - 1] {
			lo -= 1
		}
	}
	return i32(lo)
}

@(private="package")
text_to_byte :: proc(text: ^Text, unit: i32) -> i32 {
	return text.byte_offsets[clamp(unit, 0, i32(len(text.utf16)))]
}

@(private="package")
text_pixel_rect :: proc(left, top, right, bottom: f32) -> IRect {
	x, y := i32(math.floor(left)), i32(math.floor(top))
	return {x, y, max(0, i32(math.ceil(right)) - x), max(0, i32(math.ceil(bottom)) - y)}
}

@(private="package")
text_selection_rect :: proc(left, top, right, bottom: f32) -> IRect {
	x, y := i32(math.round(left)), i32(math.round(top))
	return {x, y, max(0, i32(math.round(right)) - x), max(1, i32(math.round(bottom)) - y)}
}
