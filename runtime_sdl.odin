package fluid

import "core:fmt"
import virtual "core:mem/virtual"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Keep the initialized UI at a stable address until destroy(ui).
// The UI owns all registry storage and native resources for this session.
UI :: struct {
	running:       bool,
	window:        ^sdl3.Window,
	renderer:      ^sdl3.Renderer,
	font:          ^ttf.Font,
	text_engine:   ^ttf.TextEngine,
	pixel_density: f32,
	hovered:       int,
	pressed:       int,
	dragged:       int,
	drag_offset:   [2]f32,
	viewport:      Element_ID,
	elements:      [dynamic]Element, // Stable registry indices; never reordered.
	active:        [dynamic]Element_ID, // Draw order and processing membership.
	groups:        [dynamic][dynamic]Element_ID,
	events:        [dynamic]Element_ID, // Mouse-down presses in the current frame.
	storage:       virtual.Arena,
	previous:      u64,
	sdl_ready, ttf_ready, arena_ready: bool,
}

Config :: struct {
	title:        cstring,
	size:         [2]i32,
	minimum_size: [2]i32,
}

init :: proc(app: ^UI, config: Config) -> bool {
	app^ = UI{running = true, hovered = -1, pressed = -1, dragged = -1}
	success := false
	defer { if !success { destroy(app) } }
	if err := virtual.arena_init_growing(&app.storage); err != nil {
		fmt.eprintln("Cannot initialize UI storage:", err)
		return false
	}
	app.arena_ready = true
	context.allocator = virtual.arena_allocator(&app.storage)
	app.elements = make([dynamic]Element, 0, 64)
	app.active = make([dynamic]Element_ID, 0, 64)
	app.groups = make([dynamic][dynamic]Element_ID)
	app.events = make([dynamic]Element_ID)
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("SDL initialization failed:", sdl3.GetError())
		return false
	}
	app.sdl_ready = true
	app.window = sdl3.CreateWindow(config.title, config.size[0], config.size[1], {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if app.window == nil { fmt.eprintln(sdl3.GetError()); return false }
	_ = sdl3.SetWindowMinimumSize(app.window, max(i32(1), config.minimum_size[0]), max(i32(1), config.minimum_size[1]))
	app.renderer = sdl3.CreateRenderer(app.window, nil)
	if app.renderer == nil { fmt.eprintln(sdl3.GetError()); return false }
	// One policy for the whole app: continuous, display-paced presentation.
	if !sdl3.SetRenderVSync(app.renderer, 1) { fmt.eprintln(sdl3.GetError()); return false }
	if !ttf.Init() { fmt.eprintln(sdl3.GetError()); return false }
	app.ttf_ready = true
	app.pixel_density = max(f32(1), sdl3.GetWindowPixelDensity(app.window))
	app.font = ttf.OpenFont("/System/Library/Fonts/SFNS.ttf", FONT_SIZE * app.pixel_density)
	if app.font == nil {
		app.font = ttf.OpenFont("/System/Library/Fonts/Supplemental/Arial.ttf", FONT_SIZE * app.pixel_density)
	}
	if app.font == nil { fmt.eprintln(sdl3.GetError()); return false }
	app.text_engine = ttf.CreateRendererTextEngine(app.renderer)
	if app.text_engine == nil { fmt.eprintln(sdl3.GetError()); return false }
	w, h: i32
	if !sdl3.GetWindowSize(app.window, &w, &h) { fmt.eprintln(sdl3.GetError()); return false }
	// A reference source, not a drawable or a parent.
	app.viewport = Element_ID(len(app.elements))
	append(&app.elements, Element{size = {at(f32(w)), at(f32(h))}})
	app.previous = sdl3.GetTicksNS()
	success = true
	return true
}

destroy :: proc(app: ^UI) {
	for element in app.elements {
		if element.text != nil { ttf.DestroyText(element.text) }
	}
	if app.text_engine != nil { ttf.DestroyRendererTextEngine(app.text_engine) }
	if app.font != nil { ttf.CloseFont(app.font) }
	if app.ttf_ready { ttf.Quit() }
	if app.renderer != nil { sdl3.DestroyRenderer(app.renderer) }
	if app.window != nil { sdl3.DestroyWindow(app.window) }
	if app.sdl_ready { sdl3.Quit() }
	if app.arena_ready { virtual.arena_destroy(&app.storage) }
	app^ = {}
}

begin_frame :: proc(app: ^UI) -> f64 {
	// Any GPU backpressure while acquiring this frame belongs before input.
	// Flushing the clear acquires the render target without presenting it.
	sdl3.SetRenderDrawColor(app.renderer, 24, 26, 32, 255)
	sdl3.RenderClear(app.renderer)
	if !sdl3.FlushRenderer(app.renderer) {
		fmt.eprintln(sdl3.GetError())
		app.running = false
	}
	clear(&app.events)
	now := sdl3.GetTicksNS()
	dt := f64(now - app.previous) / 1_000_000_000
	app.previous = now
	return dt
}
