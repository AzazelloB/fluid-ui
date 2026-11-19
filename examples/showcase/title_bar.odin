package main

import fluid "../.."
import "../../elements"

SHOWCASE_TITLE :: "Fluid UI"
when ODIN_OS == .Windows {
	TITLE_BAR_HEIGHT :: f32(2)
} else {
	TITLE_BAR_HEIGHT :: f32(2.5)
}

Title_Bar :: struct {
	drag, title, divider: fluid.Element_ID,
	buttons: [elements.Caption_Button]fluid.Element_ID,
}

create_title_bar :: proc(bar: ^Title_Bar, window: ^fluid.Window) {
	bar.drag = fluid.create_element(window, {})
	fluid.set_window_hit(window.ui, bar.drag, .Drag)
	bar.title = demo_text(window, {}, SHOWCASE_TITLE, .Caption, INK, weight = .Bold)
	bar.divider = elements.panel(window, {}, EDGE)
	for button in elements.Caption_Button {
		bar.buttons[button] = elements.caption_button(window, {}, button)
	}
}

layout_title_bar :: proc(bar: ^Title_Bar, ui: ^fluid.UI, viewport: fluid.Pins, sidebar_right: f32) {
	bottom := min(TITLE_BAR_HEIGHT, viewport.bottom)
	fluid.set_layout(ui, bar.drag, {right = viewport.right, bottom = bottom})
	fluid.set_layout(ui, bar.divider, {
		left = sidebar_right, top = bottom - 0.0625,
		right = viewport.right, bottom = bottom,
	})
	title_left: f32
	when ODIN_OS == .Darwin {
		title_left = 5
		for button in elements.Caption_Button {
			left := 0.625 + f32(button) * 1.25
			fluid.set_layout(ui, bar.buttons[button], fluid.rect(left, 0.625, 1.25, 1.25))
		}
	} else {
		title_left = 1
		button_width :: f32(2.875)
		order := [?]elements.Caption_Button{.Minimize, .Maximize, .Close}
		for button, index in order {
			left := viewport.right - f32(len(order) - index) * button_width
			fluid.set_layout(ui, bar.buttons[button], {left = left, right = left + button_width, bottom = bottom})
		}
	}
	fluid.set_layout(ui, bar.title, {left = title_left, right = sidebar_right, bottom = bottom})
}
