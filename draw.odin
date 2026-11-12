package fluid

import "vendor:sdl3"

draw :: proc(app: ^UI) {
	renderer := app.renderer

	for id in app.active {
		element := &app.elements[id]
		r := bounds(app, id)
		c := background(app, id)
		sdl3.SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a)
		scale := app.pixel_density
		pixels := sdl3.FRect{r.x * scale, r.y * scale, r.w * scale, r.h * scale}
		if element.kind != .Label {
			sdl3.RenderFillRect(renderer, &pixels)
		}
		if len(element.label) > 0 {
			draw_label(app, element, r)
		}
	}
	sdl3.RenderPresent(renderer)
}
