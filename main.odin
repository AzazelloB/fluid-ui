package main

import "core:fmt"
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Run: odin run .
// If Homebrew's SDL3 isn't found, append:
//   -extra-linker-flags:"-L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib"

App :: struct {
	running:       bool,
	font:          ^ttf.Font,
	text_engine:   ^ttf.TextEngine,
	pixel_density: f32,
	hovered:       int,
	pressed:       int,
	current_page:  int,
	viewport:      Element_ID,
	groups:        [dynamic][dynamic]Element_ID,
	elements:      [dynamic]Element, // Flat, append-only storage; IDs survive growth.
	dragged:       int,
	drag_offset:   [2]f32,
}

main :: proc() {
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("SDL initialization failed:", sdl3.GetError())
		return
	}
	defer sdl3.Quit()

	window := sdl3.CreateWindow(
		"Fluid UI", 800, 600, {.RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	if window == nil {
		fmt.eprintln("Window creation failed:", sdl3.GetError())
		return
	}
	defer sdl3.DestroyWindow(window)

	renderer := sdl3.CreateRenderer(window, nil)
	if renderer == nil {
		fmt.eprintln("Renderer creation failed:", sdl3.GetError())
		return
	}
	defer sdl3.DestroyRenderer(renderer)
	// Input drives drawing; don't add a presentation wait after reading input.
	if !sdl3.SetRenderVSync(renderer, 0) {
		fmt.eprintln("Cannot disable renderer vsync:", sdl3.GetError())
		return
	}

	if !ttf.Init() {
		fmt.eprintln("Text initialization failed:", sdl3.GetError())
		return
	}
	defer ttf.Quit()
	density := max(f32(1), sdl3.GetWindowPixelDensity(window))
	font := ttf.OpenFont("/System/Library/Fonts/SFNS.ttf", FONT_SIZE * density)
	if font == nil {
		font = ttf.OpenFont("/System/Library/Fonts/Supplemental/Arial.ttf", FONT_SIZE * density)
	}
	if font == nil {
		fmt.eprintln("Font loading failed:", sdl3.GetError())
		return
	}
	defer ttf.CloseFont(font)
	text_engine := ttf.CreateRendererTextEngine(renderer)
	if text_engine == nil {
		fmt.eprintln("Text renderer creation failed:", sdl3.GetError())
		return
	}
	defer ttf.DestroyRendererTextEngine(text_engine)

	app := App{
		running = true, dragged = -1, hovered = -1, pressed = -1, current_page = -1,
		font = font, text_engine = text_engine, pixel_density = density,
	}
	defer {
		for element in app.elements {
			if element.text != nil {
				ttf.DestroyText(element.text)
			}
		}
		for members in app.groups {
			delete(members)
		}
		delete(app.groups)
		delete(app.elements)
	}
	width, height: i32
	if !sdl3.GetWindowSize(window, &width, &height) {
		fmt.eprintln("Cannot read window size:", sdl3.GetError())
		return
	}
	// A non-drawing element supplies window dimensions. It isn't a parent.
	app.viewport = Element_ID(len(app.elements))
	append(&app.elements, Element{size = {at(f32(width)), at(f32(height))}})

	define_layout(&app)

	previous := sdl3.GetTicksNS()

	for app.running {
		now := sdl3.GetTicksNS()
		dt := f64(now - previous) / 1_000_000_000
		previous = now

		requests(&app, window)
		if !app.running {
			break
		}
		update(&app, dt)
		draw(&app, renderer)

		// No animations yet: sleep until input or a window event needs a redraw.
		// nil leaves the event queued for requests() on the next iteration.
		if !sdl3.WaitEvent(nil) {
			fmt.eprintln("Waiting for input failed:", sdl3.GetError())
			break
		}
	}
}
