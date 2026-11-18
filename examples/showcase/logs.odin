package main

import fluid "../.."
import "../../elements"

import "core:fmt"
import "core:math"
import "core:strings"

LOG_RATE :: 8_192
LOG_HISTORY :: 262_144
LOG_RECORD_BYTES :: 128
LOG_OVERSCAN :: 4
GIB :: 1 << 30
LOG_SEED :: 8 * GIB / LOG_RECORD_BYTES

Log_Level :: enum {Debug, Info, Warn, Error}
Log_Level_Style :: struct {label: string, color: fluid.Color}
log_levels := [Log_Level]Log_Level_Style{
	.Debug = {"DEBUG", {153, 178, 216, 255}},
	.Info  = {"INFO", MINT},
	.Warn  = {"WARN", {244, 196, 115, 255}},
	.Error = {"ERROR", {248, 144, 140, 255}},
}

Log_Event :: struct {level: Log_Level, message: string}
log_events := [?]Log_Event{
	{.Info, "gateway  request complete"},
	{.Debug, "cache    refreshed entry"},
	{.Info, "worker   batch committed"},
	{.Warn, "queue    retry scheduled"},
	{.Info, "storage  segment flushed"},
	{.Debug, "gateway  connection reused"},
	{.Info, "worker   lease renewed"},
	{.Error, "storage  upstream timeout"},
}

Log_Text :: struct {
	first: i64,
	rows: int,
	timestamps, messages: ^fluid.Text,
}

Logs :: struct {
	view, status, metrics, pause, latest: fluid.Element_ID,
	next: i64,
	paused: bool,
	credit: f64,
	text: Log_Text,
	levels: [Log_Level]^fluid.Text,
	sample_start: i64,
	updated_at, sampled_at: u64,
	draw_ns, draws: u64,
}

create_logs :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.logs
	// The synthetic stream grows by sequence number. Each retained record can
	// be reproduced from its sequence, so even the initial 8 GiB is virtual.
	page.next, page.sample_start = LOG_SEED, LOG_SEED
	page.updated_at = fluid.monotonic_ns()
	page.sampled_at = page.updated_at
	scene := fluid.create_scene(ui.window)
	append(&entry.scenes, scene)
	page.status = demo_text(scene, {}, "Following latest", .Body, MINT)
	page.pause = elements.button(scene, {}, "Pause")
	page.latest = elements.button(scene, {}, "Jump to latest", .Secondary)
	page.metrics = demo_text(scene, {}, "", .Caption, MUTED)
	page.view = fluid.create_scroll_view(scene, {
		color = {14, 20, 29, 255},
		style = {radius = 0.75, border = EDGE, border_width = 0.0625, focus_border = MINT},
		stick_to_end = true, state = page, draw = draw_logs, release_graphics = release_log_text,
	})
	fluid.on_press(ui, page.pause, page, toggle_log_stream)
	fluid.on_press(ui, page.latest, page, follow_logs)
	fluid.on_update(ui, page.view, app, update_logs)
	set_log_metrics(page, ui, 0, 0)
	update_logs(app, ui, 0)
}

toggle_log_stream :: proc(page: ^Logs, ui: ^fluid.UI, id: fluid.Element_ID) {
	advance_logs(page, fluid.monotonic_ns())
	page.paused = !page.paused
	fluid.set_label(ui, id, page.paused ? "Resume" : "Pause")
}

follow_logs :: proc(page: ^Logs, ui: ^fluid.UI, id: fluid.Element_ID) {
	fluid.scroll_to_end(ui, page.view)
}

update_logs :: proc(app: ^Showcase, ui: ^fluid.UI, dt: f64) {
	page := &app.logs
	area := content_pins(ui, app.sidebar, showcase_body(ui))
	fluid.set_target(ui, page.status, {area.left, area.top, area.right - 15, area.top + 2.25})
	fluid.set_target(ui, page.latest, {area.right - 15, area.top, area.right - 6.25, area.top + 2.25})
	fluid.set_target(ui, page.pause, {area.right - 5.75, area.top, area.right, area.top + 2.25})
	fluid.set_target(ui, page.view, {area.left, area.top + 3, area.right, area.bottom - 2})
	fluid.set_target(ui, page.metrics, {area.left, area.bottom - 1.75, area.right, area.bottom})
	now := fluid.monotonic_ns()
	advance_logs(page, now)
	font := fluid.text_font(ui.window, .Caption, .Regular)
	row_height := fluid.text_line_advance(font) / f64(fluid.pixel_scale(ui.window))
	fluid.set_scroll_content(ui, page.view, f64(page.next - LOG_HISTORY), f64(page.next), row_height)
	following := fluid.scroll_follows_end(ui, page.view)
	fluid.set_label(ui, page.status, following ? "Following latest" : "Viewing history")
	elapsed := now - page.sampled_at
	if elapsed >= 500_000_000 {
		rate := i64(math.round(f64(page.next - page.sample_start) * 1_000_000_000 / f64(elapsed)))
		draw_ms := page.draws > 0 ? f64(page.draw_ns) / f64(page.draws) / 1_000_000 : 0
		set_log_metrics(page, ui, rate, draw_ms)
		page.sample_start, page.sampled_at = page.next, now
		page.draw_ns, page.draws = 0, 0
	}
}

advance_logs :: proc(page: ^Logs, now: u64) {
	if !page.paused {
		page.credit += f64(now - page.updated_at) * LOG_RATE / 1_000_000_000
		appended := i64(page.credit)
		page.credit -= f64(appended)
		page.next += appended
	}
	page.updated_at = now
}

set_log_metrics :: proc(page: ^Logs, ui: ^fluid.UI, rate: i64, draw_ms: f64) {
	gib := f64(page.next) * LOG_RECORD_BYTES / GIB
	fluid.set_label(ui, page.metrics, fmt.tprintf("%.3f GiB simulated   ·   %d lines retained   ·   %d lines/s   ·   %.2f ms content draw",
		gib, LOG_HISTORY, rate, draw_ms))
}

draw_logs :: proc(state: rawptr, viewport: fluid.Scroll_Viewport) {
	page := cast(^Logs)state
	started := fluid.monotonic_ns()
	defer {
		page.draw_ns += fluid.monotonic_ns() - started
		page.draws += 1
	}
	window := viewport.element.window
	renderer := window.renderer
	scale := fluid.pixel_scale(window)
	font := fluid.text_font(window, .Caption, .Regular)
	first, end := i64(math.floor(viewport.first)), i64(math.ceil(viewport.end))
	text := &page.text
	if text.messages == nil || first < text.first || end > text.first + i64(text.rows) {
		block_first := max(page.next - LOG_HISTORY, first - LOG_OVERSCAN)
		block_end := min(page.next, end + LOG_OVERSCAN)
		prepare_log_text(text, block_first, int(block_end - block_first), font)
	}
	x := f32(viewport.clip.x)
	y := f32(viewport.clip.y) + f32(math.round((f64(text.first) - viewport.first) * viewport.pixels_per_unit))
	fluid.paint_text(renderer, text.timestamps, MUTED, x, y)
	fluid.paint_text(renderer, text.messages, INK, x + 9 * scale, y)
	for sequence in first..<end {
		line: fluid.Text_Span
		if !fluid.text_line(text.messages, i32(sequence - text.first), &line) { break }
		level_index := log_event(sequence).level
		level := log_levels[level_index]
		level_text := fluid.cached_text(&page.levels[level_index], font, level.label)
		fluid.paint_text(renderer, level_text, level.color, x + 5.875 * scale, y + f32(line.rect.y))
	}
}

log_event :: proc(sequence: i64) -> Log_Event {
	variant := (sequence * 17 + sequence / 11) % 41
	return log_events[variant % len(log_events)]
}

prepare_log_text :: proc(text: ^Log_Text, first: i64, rows: int, font: fluid.Text_Style) {
	fluid.release_cached_text(&text.timestamps)
	fluid.release_cached_text(&text.messages)
	// Rasterize each changing column as a block and reuse the severity masks.
	timestamps := strings.builder_make(context.temp_allocator)
	messages := strings.builder_make(context.temp_allocator)
	for row in 0..<rows {
		sequence := first + i64(row)
		seconds := sequence / LOG_RATE
		ms := (sequence % LOG_RATE) * 1000 / LOG_RATE
		newline := row + 1 < rows
		fmt.sbprintf(&timestamps, "%02d:%02d:%02d.%03d", seconds / 3600 % 24, seconds / 60 % 60, seconds % 60, ms, newline = newline)
		fmt.sbprintf(&messages, "%s   seq=%d   shard=%02d   %d ms", log_event(sequence).message,
			sequence, sequence % 32, 1 + sequence % 143, newline = newline)
	}
	text^ = {first, rows, fluid.create_text(font, strings.to_string(timestamps)), fluid.create_text(font, strings.to_string(messages))}
}

release_log_text :: proc(state: rawptr) {
	page := cast(^Logs)state
	fluid.release_cached_text(&page.text.timestamps)
	fluid.release_cached_text(&page.text.messages)
	for &level in page.levels {
		fluid.release_cached_text(&level)
	}
}
