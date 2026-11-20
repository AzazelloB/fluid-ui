package fluid

import "core:fmt"
import "core:math"
import "core:os"

foreign import text_cf "system:CoreFoundation.framework"
foreign import text_ct "system:CoreText.framework"
foreign import text_cg "system:CoreGraphics.framework"

@(private="file")
Text_CF_Range :: struct { location, length: int }
@(private="file")
Text_CG_Point :: struct { x, y: f64 }
@(private="file")
Text_CG_Rect :: struct { origin: Text_CG_Point, size: struct { width, height: f64 } }

@(private="file", default_calling_convention="c")
foreign text_cf {
	CFRelease :: proc(object: rawptr) ---
	CFRetain :: proc(object: rawptr) -> rawptr ---
	CFDataCreate :: proc(allocator: rawptr, bytes: [^]u8, length: int) -> rawptr ---
	CFStringCreateWithCharacters :: proc(allocator: rawptr, chars: [^]u16, length: int) -> rawptr ---
	CFAttributedStringCreateMutable :: proc(allocator: rawptr, maximum_length: int) -> rawptr ---
	CFAttributedStringReplaceString :: proc(value: rawptr, range: Text_CF_Range, replacement: rawptr) ---
	CFAttributedStringSetAttribute :: proc(value: rawptr, range: Text_CF_Range, key, attribute: rawptr) ---
	CFArrayGetCount :: proc(array: rawptr) -> int ---
	CFArrayGetValueAtIndex :: proc(array: rawptr, index: int) -> rawptr ---
	kCFBooleanTrue: rawptr
}

@(private="file", default_calling_convention="c")
foreign text_ct {
	CTFontManagerCreateFontDescriptorsFromData :: proc(data: rawptr) -> rawptr ---
	CTFontCreateWithFontDescriptor :: proc(descriptor: rawptr, size: f64, transform: rawptr) -> rawptr ---
	CTFontCreateUIFontForLanguage :: proc(kind: u32, size: f64, language: rawptr) -> rawptr ---
	CTFontGetAscent :: proc(font: rawptr) -> f64 ---
	CTFontGetDescent :: proc(font: rawptr) -> f64 ---
	CTFontGetLeading :: proc(font: rawptr) -> f64 ---
	CTTypesetterCreateWithAttributedString :: proc(value: rawptr) -> rawptr ---
	CTTypesetterSuggestLineBreak :: proc(typesetter: rawptr, start: int, width: f64) -> int ---
	CTTypesetterSuggestClusterBreak :: proc(typesetter: rawptr, start: int, width: f64) -> int ---
	CTTypesetterCreateLine :: proc(typesetter: rawptr, range: Text_CF_Range) -> rawptr ---
	CTLineGetTypographicBounds :: proc(line: rawptr, ascent, descent, leading: ^f64) -> f64 ---
	CTLineGetImageBounds :: proc(line, graphics: rawptr) -> Text_CG_Rect ---
	CTLineGetOffsetForStringIndex :: proc(line: rawptr, index: int, secondary: ^f64) -> f64 ---
	CTLineGetStringIndexForPosition :: proc(line: rawptr, point: Text_CG_Point) -> int ---
	CTLineGetGlyphRuns :: proc(line: rawptr) -> rawptr ---
	CTLineDraw :: proc(line, graphics: rawptr) ---
	CTRunGetStringRange :: proc(run: rawptr) -> Text_CF_Range ---
	CTRunGetGlyphCount :: proc(run: rawptr) -> int ---
	CTRunGetStatus :: proc(run: rawptr) -> u32 ---
	CTRunGetPositions :: proc(run: rawptr, range: Text_CF_Range, positions: ^Text_CG_Point) ---
	CTRunGetTypographicBounds :: proc(run: rawptr, range: Text_CF_Range, ascent, descent, leading: ^f64) -> f64 ---
	kCTFontAttributeName: rawptr
	kCTForegroundColorFromContextAttributeName: rawptr
}

@(private="file", default_calling_convention="c")
foreign text_cg {
	CGBitmapContextCreate :: proc(data: rawptr, width, height, component_bits, row_bytes: uintptr,
		color_space: rawptr, bitmap_info: u32) -> rawptr ---
	CGContextRelease :: proc(graphics: rawptr) ---
	CGContextSetGrayFillColor :: proc(graphics: rawptr, gray, alpha: f64) ---
	CGContextSetShouldAntialias :: proc(graphics: rawptr, enabled: bool) ---
	CGContextSetShouldSmoothFonts :: proc(graphics: rawptr, enabled: bool) ---
	CGContextSetTextPosition :: proc(graphics: rawptr, x, y: f64) ---
}

@(private="package")
Native_Text_Layout :: struct {
	lines: [dynamic]Core_Text_Line,
	dimensions: [2]i32,
}

@(private="file")
Core_Text_Line :: struct {
	object: rawptr,
	start, count, hard_break: int,
	top, ascent, height, width: f64,
	ink: IRect,
}

@(private="file", thread_local)
macos_font_descriptors: [2]rawptr

// Set the default regular and bold faces on the UI thread before creating any text.
// Each input contains one font face. The app need not install either face in macOS.
set_macos_text_fonts :: proc(regular, bold: []u8) -> bool {
	descriptors: [2]rawptr
	for data, index in ([2][]u8{regular, bold}) {
		descriptors[index] = read_macos_font_descriptor(data)
		if descriptors[index] == nil {
			for descriptor in descriptors[:index] {
				CFRelease(descriptor)
			}
			return false
		}
	}
	clear_macos_text_fonts()
	macos_font_descriptors = descriptors
	return true
}

// Restore the system faces after the UI session and its text layouts are destroyed.
clear_macos_text_fonts :: proc() {
	for descriptor in macos_font_descriptors {
		if descriptor != nil {
			CFRelease(descriptor)
		}
	}
	macos_font_descriptors = {}
	reset_text_font_metrics()
}

@(private="file")
read_macos_font_descriptor :: proc(bytes: []u8) -> rawptr {
	if len(bytes) == 0 {
		return nil
	}
	data := CFDataCreate(nil, raw_data(bytes), len(bytes))
	if data == nil {
		return nil
	}
	defer CFRelease(data)
	descriptors := CTFontManagerCreateFontDescriptorsFromData(data)
	if descriptors == nil {
		return nil
	}
	defer CFRelease(descriptors)
	if CFArrayGetCount(descriptors) != 1 {
		return nil
	}
	return CFRetain(CFArrayGetValueAtIndex(descriptors, 0))
}

@(private="file")
create_macos_text_font :: proc(pixels: f32, bold: bool) -> rawptr {
	if descriptor := macos_font_descriptors[bold ? 1 : 0]; descriptor != nil {
		if font := CTFontCreateWithFontDescriptor(descriptor, f64(pixels), nil); font != nil {
			return font
		}
	}
	// kCTFontUIFontEmphasizedSystem and kCTFontUIFontSystem.
	return CTFontCreateUIFontForLanguage(bold ? 3 : 2, f64(pixels), nil)
}

@(private="package")
platform_text_font_metrics :: proc(pixels: f32, bold: bool) -> (height, line_height: i32, advance: f64) {
	font := create_macos_text_font(pixels, bold)
	if font == nil {
		advance = max(1, f64(pixels * 1.2))
		line_height = i32(math.ceil(advance))
		return line_height, line_height, advance
	}
	defer CFRelease(font)
	base_height := CTFontGetAscent(font) + CTFontGetDescent(font)
	leading := max(0, CTFontGetLeading(font))
	height = max(1, i32(math.ceil(base_height)))
	line_height = height + i32(math.ceil(leading))
	advance = max(1, base_height + leading)
	return height, line_height, advance
}

@(private="package")
create_text_layout :: proc(text: ^Text) -> bool {
	font := create_macos_text_font(text.pixels, text.bold)
	if font == nil {
		fmt.eprintln("Cannot load the macOS system font")
		return false
	}
	defer CFRelease(font)
	font_ascent, font_descent, font_leading := CTFontGetAscent(font), CTFontGetDescent(font), CTFontGetLeading(font)
	units := text.utf16
	typesetter: rawptr
	defer {
		if typesetter != nil {
			CFRelease(typesetter)
		}
	}
	if len(units) > 0 {
		source := CFStringCreateWithCharacters(nil, raw_data(units), len(units))
		if source == nil {
			return false
		}
		defer CFRelease(source)
		attributed := CFAttributedStringCreateMutable(nil, 0)
		if attributed == nil {
			return false
		}
		defer CFRelease(attributed)
		CFAttributedStringReplaceString(attributed, {}, source)
		whole := Text_CF_Range{0, len(units)}
		CFAttributedStringSetAttribute(attributed, whole, kCTFontAttributeName, font)
		CFAttributedStringSetAttribute(attributed, whole, kCTForegroundColorFromContextAttributeName, kCFBooleanTrue)
		typesetter = CTTypesetterCreateWithAttributedString(attributed)
		if typesetter == nil {
			return false
		}
	}

	text.layout.lines = make([dynamic]Core_Text_Line, os.heap_allocator())
	top, width: f64
	for first := 0; first <= len(units); {
		end := first
		for end < len(units) && units[end] != '\r' && units[end] != '\n' && units[end] != 0x2028 && units[end] != 0x2029 {
			end += 1
		}
		hard_break: int
		if end < len(units) {
			hard_break = 1
			if units[end] == '\r' && end + 1 < len(units) && units[end + 1] == '\n' {
				hard_break = 2
			}
		}
		for start := first; start <= end; {
			count := end - start
			if text.wrap > 0 && count > 0 {
				limit := CTTypesetterSuggestLineBreak(typesetter, start, f64(text.wrap))
				if limit <= 0 {
					limit = CTTypesetterSuggestClusterBreak(typesetter, start, f64(text.wrap))
				}
				if limit <= 0 {
					limit = (units[start] >= 0xd800 && units[start] <= 0xdbff) ? 2 : 1
				}
				count = min(count, limit)
			}
			line := Core_Text_Line{start = start, count = count, top = top}
			ascent, descent, leading: f64
			if count > 0 {
				line.object = CTTypesetterCreateLine(typesetter, {start, count})
				if line.object == nil {
					destroy_text_layout(text)
					return false
				}
				line.width = CTLineGetTypographicBounds(line.object, &ascent, &descent, &leading)
			}
			line.ascent = max(ascent, font_ascent)
			line.height = line.ascent + max(descent, font_descent) + max(leading, font_leading, 0)
			width = max(width, line.width)
			top += line.height
			start += count
			if start == end {
				line.hard_break = hard_break
				append(&text.layout.lines, line)
				break
			}
			append(&text.layout.lines, line)
		}
		if hard_break == 0 {
			break
		}
		first = end + hard_break
	}
	text.layout.dimensions = {i32(math.ceil(width)), i32(math.ceil(top))}
	return true
}

@(private="package")
destroy_text_layout :: proc(text: ^Text) {
	for line in text.layout.lines {
		if line.object != nil {
			CFRelease(line.object)
		}
	}
	delete(text.layout.lines)
	text.layout = {}
}

@(private="file")
macos_line_rect :: proc(line: Core_Text_Line, left, right: f64) -> IRect {
	return text_selection_rect(f32(left), f32(line.top), f32(right), f32(line.top + line.height))
}

@(private="package")
platform_text_line :: proc(text: ^Text, index: i32, out: ^Text_Span) -> bool {
	if index < 0 || int(index) >= len(text.layout.lines) {
		return false
	}
	line := text.layout.lines[index]
	offset := text_to_byte(text, i32(line.start))
	end := text_to_byte(text, i32(line.start + line.count + line.hard_break))
	out^ = {offset, end - offset, index, macos_line_rect(line, 0, line.width)}
	return true
}

@(private="package")
platform_text_span :: proc(text: ^Text, unit: i32, out: ^Text_Span) -> bool {
	lines := text.layout.lines
	lo, hi := 0, len(lines) - 1
	for lo < hi {
		mid := lo + (hi - lo + 1) / 2
		if int(unit) >= lines[mid].start {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	line := lines[lo]
	x: f64
	if line.object != nil {
		x = CTLineGetOffsetForStringIndex(line.object, min(int(unit), line.start + line.count), nil)
	}
	out^ = {text_to_byte(text, unit), 0, i32(lo), macos_line_rect(line, x, x)}
	return true
}

@(private="package")
platform_text_hit :: proc(text: ^Text, x, y: i32, out: ^Text_Span) -> Text_Hit {
	lines := text.layout.lines
	lo, hi := 0, len(lines) - 1
	for lo < hi {
		mid := lo + (hi - lo + 1) / 2
		if f64(y) >= lines[mid].top {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	line := lines[lo]
	caret, under := line.start, line.start
	left, right: f64
	if line.object != nil {
		caret = clamp(CTLineGetStringIndexForPosition(line.object, {f64(x), 0}), line.start, line.start + line.count)
		under = min(caret, line.start + line.count - 1)
		if caret > line.start && caret < line.start + line.count {
			before := CTLineGetOffsetForStringIndex(line.object, caret - 1, nil)
			at := CTLineGetOffsetForStringIndex(line.object, caret, nil)
			if f64(x) >= min(before, at) && f64(x) < max(before, at) {
				under = caret - 1
			}
		}
		if under > line.start && text.utf16[under] >= 0xdc00 && text.utf16[under] <= 0xdfff {
			under -= 1
		}
		left = CTLineGetOffsetForStringIndex(line.object, under, nil)
		next := under + ((text.utf16[under] >= 0xd800 && text.utf16[under] <= 0xdbff) ? 2 : 1)
		right = CTLineGetOffsetForStringIndex(line.object, next, nil)
		offset := text_to_byte(text, i32(under))
		out^ = {offset, text_to_byte(text, i32(next)) - offset, i32(lo), macos_line_rect(line, min(left, right), max(left, right))}
	} else {
		platform_text_line(text, i32(lo), out)
	}
	return {text_to_byte(text, i32(caret)), true}
}

@(private="file")
macos_run_edge :: proc(line: Core_Text_Line, run: Text_CF_Range, index: int, left, right: f64, rtl: bool) -> f64 {
	if index == run.location {
		return rtl ? right : left
	}
	if index == run.location + run.length {
		return rtl ? left : right
	}
	secondary: f64
	primary := CTLineGetOffsetForStringIndex(line.object, index, &secondary)
	return clamp(primary >= left && primary <= right ? primary : secondary, left, right)
}

@(private="package")
platform_text_range :: proc(text: ^Text, start, end: i32) -> []IRect {
	rects := make([dynamic]IRect, context.temp_allocator)
	for line in text.layout.lines {
		if line.start + line.count + line.hard_break <= int(start) {
			continue
		}
		if line.start >= int(end) {
			break
		}
		if line.object != nil {
			runs := CTLineGetGlyphRuns(line.object)
			for i in 0..<CFArrayGetCount(runs) {
				run := CFArrayGetValueAtIndex(runs, i)
				range := CTRunGetStringRange(run)
				first, last := max(int(start), range.location), min(int(end), range.location + range.length)
				if first >= last || CTRunGetGlyphCount(run) == 0 {
					continue
				}
				origin: Text_CG_Point
				CTRunGetPositions(run, {0, 1}, &origin)
				left := origin.x
				right := left + CTRunGetTypographicBounds(run, {}, nil, nil, nil)
				rtl := CTRunGetStatus(run) & 1 != 0
				x0 := macos_run_edge(line, range, first, left, right, rtl)
				x1 := macos_run_edge(line, range, last, left, right, rtl)
				append(&rects, macos_line_rect(line, min(x0, x1), max(x0, x1)))
			}
		}
		if line.hard_break > 0 && int(end) > line.start + line.count {
			x := line.object != nil ? CTLineGetOffsetForStringIndex(line.object, line.start + line.count, nil) : 0
			append(&rects, macos_line_rect(line, x, x))
		}
	}
	return rects[:]
}

@(private="package")
text_ink_bounds :: proc(text: ^Text) -> IRect {
	ink: IRect
	for &line in text.layout.lines {
		if line.object == nil {
			continue
		}
		bounds := CTLineGetImageBounds(line.object, nil)
		if bounds.size.width <= 0 || bounds.size.height <= 0 {
			continue
		}
		baseline := line.top + line.ascent
		left, top := bounds.origin.x, baseline - bounds.origin.y - bounds.size.height
		right, bottom := left + bounds.size.width, top + bounds.size.height
		line.ink = text_pixel_rect(f32(left) - 1, f32(top) - 1, f32(right) + 1, f32(bottom) + 1)
		if ink.w == 0 {
			ink = line.ink
		} else {
			x, y := min(ink.x, line.ink.x), min(ink.y, line.ink.y)
			ink = {x, y, max(ink.x + ink.w, line.ink.x + line.ink.w) - x, max(ink.y + ink.h, line.ink.y + line.ink.h) - y}
		}
	}
	return ink
}

@(private="package")
rasterize_text :: proc(text: ^Text, ink: IRect) -> []u8 {
	alpha := make([]u8, int(ink.w) * int(ink.h), os.heap_allocator())
	// kCGImageAlphaOnly stores one coverage byte per pixel, independent of glyph color.
	graphics := CGBitmapContextCreate(raw_data(alpha), uintptr(ink.w), uintptr(ink.h), 8, uintptr(ink.w), nil, 7)
	if graphics == nil {
		delete(alpha, os.heap_allocator())
		return nil
	}
	defer CGContextRelease(graphics)
	CGContextSetGrayFillColor(graphics, 1, 1)
	CGContextSetShouldAntialias(graphics, true)
	CGContextSetShouldSmoothFonts(graphics, false)
	for line in text.layout.lines {
		if line.ink.w > 0 && line.ink.y + line.ink.h > ink.y && line.ink.y < ink.y + ink.h {
			y := f64(ink.h + ink.y) - line.top - line.ascent
			CGContextSetTextPosition(graphics, -f64(ink.x), y)
			CTLineDraw(line.object, graphics)
		}
	}
	return alpha
}
