package fluid

import "core:fmt"
import "core:math"
import "core:os"
import win "core:sys/windows"

foreign import direct2d "system:d2d1.lib"
foreign import directwrite "system:dwrite.lib"

@(default_calling_convention="system")
foreign direct2d {
	D2D1CreateFactory :: proc(kind: u32, iid: ^win.GUID, options: rawptr, factory: ^^D2D_Factory) -> i32 ---
}

@(default_calling_convention="system")
foreign directwrite {
	DWriteCreateFactory :: proc(kind: u32, iid: ^win.GUID, factory: ^^DWrite_Factory) -> i32 ---
}

@(private="package")
Native_Text_Layout :: struct {
	object: ^DWrite_Layout,
	lines: []DWrite_Line,
	dimensions: [2]i32,
	metrics: DWrite_Text_Metrics,
}

@(private="file")
TEXT_FACTORY_ID :: win.GUID{0xb859ee5a, 0xd838, 0x4b5b, {0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48}}
@(private="file")
MASK_FACTORY_ID :: win.GUID{0x06152247, 0x6f50, 0x465a, {0x92, 0x45, 0x11, 0x8b, 0xfd, 0x3b, 0x60, 0x07}}

@(private="file")
Com_Unknown :: struct { vtable: ^Com_Unknown_Methods }
@(private="file")
Com_Unknown_Methods :: struct {
	query_interface, add_ref: rawptr,
	release: proc "system"(self: ^Com_Unknown) -> u32,
}

// The unused slots keep the interfaces aligned with dwrite.h and d2d1.h.
@(private="file")
DWrite_Factory :: struct { vtable: ^DWrite_Factory_Methods }
@(private="file")
DWrite_Factory_Methods :: struct {
	unknown_and_font_collection_methods: [15]rawptr,
	create_format: proc "system"(self: ^DWrite_Factory, family: [^]u16, font_collection: rawptr,
		weight, style, stretch: u32, size: f32, locale: [^]u16, format: ^^DWrite_Format) -> i32,
	create_typography, get_gdi_interop: rawptr,
	create_layout: proc "system"(self: ^DWrite_Factory, text: [^]u16, length: u32,
		format: ^DWrite_Format, width, height: f32, layout: ^^DWrite_Layout) -> i32,
}

@(private="file")
DWrite_Format :: struct { vtable: ^DWrite_Format_Methods }
@(private="file")
DWrite_Format_Methods :: struct {
	unknown_and_alignment_methods: [5]rawptr,
	set_word_wrapping: proc "system"(self: ^DWrite_Format, wrapping: u32) -> i32,
}

@(private="file")
DWrite_Layout :: struct { vtable: ^DWrite_Layout_Methods }
@(private="file")
DWrite_Layout_Methods :: struct {
	format_and_layout_methods: [59]rawptr,
	get_lines: proc "system"(self: ^DWrite_Layout, lines: [^]DWrite_Line_Metrics, capacity: u32, count: ^u32) -> i32,
	get_metrics: proc "system"(self: ^DWrite_Layout, metrics: ^DWrite_Text_Metrics) -> i32,
	get_overhang: proc "system"(self: ^DWrite_Layout, metrics: ^DWrite_Overhang) -> i32,
	cluster_metrics, determine_min_width: rawptr,
	hit_point: proc "system"(self: ^DWrite_Layout, x, y: f32, trailing, inside: ^win.BOOL, hit: ^DWrite_Hit) -> i32,
	hit_position: proc "system"(self: ^DWrite_Layout, position: u32, trailing: win.BOOL, x, y: ^f32, hit: ^DWrite_Hit) -> i32,
	hit_range: proc "system"(self: ^DWrite_Layout, position, length: u32, x, y: f32,
		hits: [^]DWrite_Hit, capacity: u32, count: ^u32) -> i32,
}

@(private="file")
DWrite_Line_Metrics :: struct {
	length, trailing_white_space, newline_length: u32,
	height, baseline: f32,
	trimmed: win.BOOL,
}
@(private="file")
DWrite_Text_Metrics :: struct {
	left, top, width, width_including_trailing_space, height, layout_width, layout_height: f32,
	max_bidi_depth, line_count: u32,
}
@(private="file")
DWrite_Hit :: struct {
	position, length: u32,
	left, top, width, height: f32,
	bidi_level: u32,
	is_text, trimmed: win.BOOL,
}
@(private="file")
DWrite_Overhang :: struct { left, top, right, bottom: f32 }
@(private="file")
DWrite_Line :: struct {
	start, length: i32,
	top, height: f32,
}

@(private="file")
D2D_Factory :: struct { vtable: ^D2D_Factory_Methods }
@(private="file")
D2D_Factory_Methods :: struct {
	unknown_and_factory_methods: [16]rawptr,
	create_dc_target: proc "system"(self: ^D2D_Factory, properties: ^D2D_Target_Properties, target: ^^D2D_Target) -> i32,
}
@(private="file")
D2D_Target_Properties :: struct {
	kind, format, alpha_mode: u32,
	dpi_x, dpi_y: f32,
	usage, minimum_feature_level: u32,
}
@(private="file")
D2D_Target :: struct { vtable: ^D2D_Target_Methods }
@(private="file")
D2D_Target_Methods :: struct {
	resource_and_bitmap_methods: [8]rawptr,
	create_solid_brush: proc "system"(self: ^D2D_Target, color: ^[4]f32, brush_properties: rawptr, brush: ^rawptr) -> i32,
	brush_and_draw_methods: [19]rawptr,
	draw_text_layout: proc "system"(self: ^D2D_Target, origin: [2]f32, layout: ^DWrite_Layout, brush: rawptr, options: u32),
	glyph_and_antialias_methods: [5]rawptr,
	set_text_antialias: proc "system"(self: ^D2D_Target, mode: u32),
	text_and_clip_methods: [12]rawptr,
	clear: proc "system"(self: ^D2D_Target, color: ^[4]f32),
	begin_draw: proc "system"(self: ^D2D_Target),
	end_draw: proc "system"(self: ^D2D_Target, tag1, tag2: ^u64) -> i32,
	properties_methods: [7]rawptr,
	bind_dc: proc "system"(self: ^D2D_Target, dc: win.HDC, rect: ^win.RECT) -> i32,
}

@(private="file")
release_text_com :: proc(pointer: rawptr) {
	if pointer != nil {
		object := cast(^Com_Unknown)pointer
		object.vtable.release(object)
	}
}

@(private="file")
create_dwrite_layout :: proc(text: [^]u16, length: u32, pixels: f32, bold: bool, wrap: i32) -> ^DWrite_Layout {
	factory: ^DWrite_Factory
	iid := TEXT_FACTORY_ID
	if DWriteCreateFactory(0, &iid, &factory) < 0 {
		return nil
	}
	defer release_text_com(factory)
	format: ^DWrite_Format
	weight: u32 = bold ? 700 : 400
	if factory.vtable.create_format(factory, win.L("Segoe UI"), nil, weight, 0, 5, pixels, win.L("en-us"), &format) < 0 {
		return nil
	}
	defer release_text_com(format)
	if wrap == 0 {
		// DWRITE_WORD_WRAPPING_NO_WRAP
		format.vtable.set_word_wrapping(format, 1)
	}
	width := wrap > 0 ? f32(wrap) : 1_000_000
	layout: ^DWrite_Layout
	if factory.vtable.create_layout(factory, text, length, format, width, 1_000_000, &layout) < 0 {
		return nil
	}
	return layout
}

@(private="package")
platform_text_font_metrics :: proc(pixels: f32, bold: bool) -> (height, line_height: i32) {
	sample := [1]u16{'M'}
	layout := create_dwrite_layout(raw_data(sample[:]), 1, pixels, bold, 0)
	if layout != nil {
		defer release_text_com(layout)
		metrics: DWrite_Line_Metrics
		count: u32
		if layout.vtable.get_lines(layout, &metrics, 1, &count) >= 0 && count > 0 {
			line_height = max(1, i32(math.ceil(metrics.height)))
			return line_height, line_height
		}
	}
	line_height = max(1, i32(math.ceil(pixels * 1.2)))
	return line_height, line_height
}

@(private="package")
create_text_layout :: proc(text: ^Text) -> bool {
	characters := raw_data(text.utf16)
	zero: u16
	if len(text.utf16) == 0 {
		characters = &zero
	}
	object := create_dwrite_layout(characters, u32(len(text.utf16)), text.pixels, text.bold, text.wrap)
	if object == nil {
		fmt.eprintln("Cannot create DirectWrite text layout")
		return false
	}
	metrics: DWrite_Text_Metrics
	if object.vtable.get_metrics(object, &metrics) < 0 {
		release_text_com(object)
		return false
	}
	line_metrics := make([]DWrite_Line_Metrics, metrics.line_count, context.temp_allocator)
	count: u32
	if metrics.line_count == 0 || object.vtable.get_lines(object, raw_data(line_metrics), metrics.line_count, &count) < 0 || count == 0 {
		release_text_com(object)
		return false
	}
	lines := make([]DWrite_Line, count, os.heap_allocator())
	start: i32
	top := metrics.top
	for source, i in line_metrics[:count] {
		lines[i] = {start, i32(source.length), top, source.height}
		start += i32(source.length)
		top += source.height
	}
	text.layout = {
		object = object,
		lines = lines,
		metrics = metrics,
		dimensions = {i32(math.ceil(metrics.width_including_trailing_space)), i32(math.ceil(metrics.height))},
	}
	return true
}

@(private="package")
destroy_text_layout :: proc(text: ^Text) {
	release_text_com(text.layout.object)
	delete(text.layout.lines, os.heap_allocator())
	text.layout = {}
}

@(private="file")
windows_line_at_y :: proc(lines: []DWrite_Line, y: f32) -> i32 {
	low, high := 0, len(lines) - 1
	for low < high {
		mid := low + (high - low + 1) / 2
		if y >= lines[mid].top {
			low = mid
		} else {
			high = mid - 1
		}
	}
	return i32(low)
}

@(private="package")
platform_text_span :: proc(text: ^Text, unit: i32, out: ^Text_Span) -> bool {
	lines := text.layout.lines
	last := lines[len(lines) - 1]
	if unit == last.start && last.length == 0 {
		return platform_text_line(text, i32(len(lines) - 1), out)
	}
	layout := text.layout.object
	x, y: f32
	hit: DWrite_Hit
	position := min(unit, i32(len(text.utf16)) - 1)
	if layout.vtable.hit_position(layout, u32(position), win.BOOL(unit > position), &x, &y, &hit) < 0 {
		return false
	}
	line := windows_line_at_y(lines, y)
	rect := text_selection_rect(x, hit.top, x, hit.top + hit.height)
	offset := text_to_byte(text, unit)
	out^ = {offset, max(0, text_to_byte(text, i32(hit.position + hit.length)) - offset), line, rect}
	return true
}

@(private="package")
platform_text_line :: proc(text: ^Text, index: i32, out: ^Text_Span) -> bool {
	if index < 0 || int(index) >= len(text.layout.lines) {
		return false
	}
	line := text.layout.lines[index]
	offset := text_to_byte(text, line.start)
	out^ = {offset, text_to_byte(text, line.start + line.length) - offset, index,
		text_selection_rect(0, line.top, 0, line.top + line.height)}
	return true
}

@(private="package")
platform_text_hit :: proc(text: ^Text, x, y: i32, out: ^Text_Span) -> Text_Hit {
	lines := text.layout.lines
	index := windows_line_at_y(lines, f32(y))
	line := lines[index]
	if line.length == 0 {
		ok := platform_text_line(text, index, out)
		return {out.offset, ok}
	}
	layout := text.layout.object
	trailing, inside: win.BOOL
	hit: DWrite_Hit
	y_on_line := clamp(f32(y), line.top + 0.01, line.top + line.height - 0.01)
	if layout.vtable.hit_point(layout, f32(x), y_on_line, &trailing, &inside, &hit) < 0 {
		return {}
	}
	position := i32(hit.position)
	end := position + i32(hit.length)
	offset, length := text_to_byte(text, position), text_to_byte(text, end) - text_to_byte(text, position)
	if trailing != false && end == line.start + line.length && end > position {
		// Clicking beyond a hard break stays on the current visual line.
		if text.utf16[end - 1] == '\n' {
			end -= 1
		}
		if end > position && text.utf16[end - 1] == '\r' {
			end -= 1
		}
	}
	out^ = {offset, length, index, text_selection_rect(hit.left, hit.top, hit.left + hit.width, hit.top + hit.height)}
	return {text_to_byte(text, trailing != false ? end : position), true}
}

@(private="package")
platform_text_range :: proc(text: ^Text, start, end: i32) -> []IRect {
	layout := text.layout.object
	count: u32
	layout.vtable.hit_range(layout, u32(start), u32(end - start), 0, 0, nil, 0, &count)
	if count == 0 {
		return nil
	}
	hits := make([]DWrite_Hit, count, context.temp_allocator)
	if layout.vtable.hit_range(layout, u32(start), u32(end - start), 0, 0, raw_data(hits), count, &count) < 0 {
		return nil
	}
	rects := make([]IRect, count, context.temp_allocator)
	for hit, i in hits[:count] {
		rects[i] = text_selection_rect(hit.left, hit.top, hit.left + hit.width, hit.top + hit.height)
	}
	return rects
}

@(private="package")
text_ink_bounds :: proc(text: ^Text) -> IRect {
	layout := text.layout.object
	metrics := text.layout.metrics
	overhang: DWrite_Overhang
	if layout.vtable.get_overhang(layout, &overhang) < 0 {
		return {}
	}
	// The overhang describes the ink relative to the layout box, and may be negative.
	left, top := -overhang.left, -overhang.top
	right, bottom := metrics.layout_width + overhang.right, metrics.layout_height + overhang.bottom
	if left >= right || top >= bottom {
		return {}
	}
	return text_pixel_rect(left - 1, top - 1, right + 1, bottom + 1)
}

@(private="package")
rasterize_text :: proc(text: ^Text, ink: IRect) -> []u8 {
	layout := text.layout.object
	dc := win.CreateCompatibleDC(nil)
	if dc == nil {
		return nil
	}
	defer win.DeleteDC(dc)
	info := win.BITMAPINFO{bmiHeader = {
		biSize = size_of(win.BITMAPINFOHEADER), biWidth = ink.w, biHeight = -ink.h, biPlanes = 1, biBitCount = 32,
	}}
	bits: rawptr
	bitmap := win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, nil, 0)
	if bitmap == nil {
		return nil
	}
	defer win.DeleteObject(win.HGDIOBJ(bitmap))
	previous := win.SelectObject(dc, win.HGDIOBJ(bitmap))
	defer win.SelectObject(dc, previous)

	factory: ^D2D_Factory
	iid := MASK_FACTORY_ID
	if D2D1CreateFactory(0, &iid, nil, &factory) < 0 {
		return nil
	}
	defer release_text_com(factory)
	// Software B8G8R8A8 at 96 DPI with the alpha channel ignored. A white
	// glyph over black yields a single-channel coverage mask in every RGB channel.
	properties := D2D_Target_Properties{kind = 1, format = 87, alpha_mode = 3, dpi_x = 96, dpi_y = 96}
	target: ^D2D_Target
	if factory.vtable.create_dc_target(factory, &properties, &target) < 0 {
		return nil
	}
	defer release_text_com(target)
	rect := win.RECT{0, 0, ink.w, ink.h}
	if target.vtable.bind_dc(target, dc, &rect) < 0 {
		return nil
	}
	white := [4]f32{1, 1, 1, 1}
	brush: rawptr
	if target.vtable.create_solid_brush(target, &white, nil, &brush) < 0 {
		return nil
	}
	defer release_text_com(brush)
	black := [4]f32{0, 0, 0, 1}
	target.vtable.begin_draw(target)
	target.vtable.set_text_antialias(target, 2) // D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE
	target.vtable.clear(target, &black)
	target.vtable.draw_text_layout(target, {-f32(ink.x), -f32(ink.y)}, layout, brush, 0)
	if target.vtable.end_draw(target, nil, nil) < 0 {
		return nil
	}

	pixels := cast([^][4]u8)bits
	alpha := make([]u8, int(ink.w) * int(ink.h), os.heap_allocator())
	for &coverage, i in alpha {
		coverage = pixels[i][0]
	}
	return alpha
}
