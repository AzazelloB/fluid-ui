package fluid

import "vendor:sdl3"

// Draw without presenting, so applications can composite their own effects.
draw :: proc(app: ^UI, window: ^Window) {
	renderer := window.renderer
	sdl3.SetRenderDrawColor(renderer, 24, 26, 32, 255)
	sdl3.RenderClear(renderer)

	for id in app.active {
		element := get_element(app, id)
		if element.owner.window != window {
			continue
		}
		r := bounds(app, id)
		c := background(app, id)
		sdl3.SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a)
		scale := window.pixel_density
		pixels := sdl3.FRect{r.x * scale, r.y * scale, r.w * scale, r.h * scale}
		if element.kind != .Label {
			sdl3.RenderFillRect(renderer, &pixels)
		}
		if len(element.label) > 0 {
			draw_label(window, element, r)
		}
	}
}
