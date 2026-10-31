package main

import "vendor:sdl3"

draw :: proc(app: ^App, renderer: ^sdl3.Renderer) {
	sdl3.SetRenderDrawColor(renderer, 24, 26, 32, 255)
	sdl3.RenderClear(renderer)

	for &element, i in app.elements {
		if !element.visible {
			continue
		}
		r := bounds(app, Element_ID(i))
		c := background(app, Element_ID(i))
		sdl3.SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a)
		scale := app.pixel_density
		pixels := sdl3.FRect{r.x * scale, r.y * scale, r.w * scale, r.h * scale}
		sdl3.RenderFillRect(renderer, &pixels)
		if len(element.label) > 0 {
			draw_label(app, &element, r)
		}
	}
	sdl3.RenderPresent(renderer)
}
