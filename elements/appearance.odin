package elements

import fluid ".."

draw_default :: proc(view: fluid.Element_View) {
	draw_element_surface(view)
	draw_element_label(view)
}

// Draw the styled surface or focus outline from the supplied view.
draw_element_surface :: proc(view: fluid.Element_View) {
	scale := fluid.pixel_scale(view.window)
	pixels := fluid.pixel_rect(view.pins, scale)
	if view.surface {
		fluid.paint_styled_surface(view.window.renderer, pixels, view.style, view.color, view.hovered, view.focus_visible, scale)
	} else if view.focus_visible {
		if color, styled := view.style.focus_border.?; styled {
			fluid.rounded_outline(view.window.renderer, pixels, view.style.radius * scale, max(view.style.border_width, 0.0625) * scale, color, view.style.square_corners)
		}
	}
}

draw_element_label :: proc(view: fluid.Element_View) {
	if view.label != "" {
		fluid.draw_label(view.window, fluid.element_text(view), view.pins, view.text_color, view.text_align, view.text_wrap)
	}
}
