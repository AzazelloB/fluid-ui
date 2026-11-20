package main

import fluid "../.."
import "../../elements"

SHOWCASE_TITLE :: "Bamboo Field Station"
when ODIN_OS == .Windows {
	TITLE_BAR_HEIGHT :: f32(2)
} else {
	TITLE_BAR_HEIGHT :: f32(2.5)
}

Title_Bar :: struct {
	drag, title, settings: fluid.Element_ID,
	buttons: [elements.Caption_Button]fluid.Element_ID,
}

create_title_bar :: proc(bar: ^Title_Bar, window: ^fluid.Window) {
	bar.drag = fluid.create_element(window, {})
	fluid.set_window_hit(window.ui, bar.drag, .Drag)
	bar.title = field_text(window, "", TEXT_BODY, INK, .Bold)
	bar.settings = field_button(window, "⚙", .Secondary)
	fluid.set_text_style(window.ui, bar.settings, 1.5, INK, .Center)
	for button in elements.Caption_Button {
		bar.buttons[button] = elements.caption_button(window, {}, button)
	}
}

layout_title_bar :: proc(app: ^Showcase, ui: ^fluid.UI, viewport: fluid.Pins) {
	bar := &app.title_bar
	bottom := min(TITLE_BAR_HEIGHT, viewport.bottom)
	fluid.set_layout(ui, bar.drag, {right = viewport.right, bottom = bottom})
	title_left: f32
	settings_right := viewport.right - 1.25
	when ODIN_OS == .Darwin {
		title_left = 5
		for button in elements.Caption_Button {
			left := 0.625 + f32(button) * 1.25
			fluid.set_layout(ui, bar.buttons[button], fluid.rect(left, 0.625, 1.25, 1.25))
		}
	} else {
		title_left = 1
		button_width :: f32(2.875)
		settings_right -= 3 * button_width
		order := [?]elements.Caption_Button{.Minimize, .Maximize, .Close}
		for button, index in order {
			left := viewport.right - f32(len(order) - index) * button_width
			fluid.set_layout(ui, bar.buttons[button], {left = left, right = left + button_width, bottom = bottom})
		}
	}
	fluid.set_layout(ui, bar.settings, fluid.rect(settings_right - 2.6, (bottom - 1.9) / 2, 2.6, 1.9))
	fluid.set_layout(ui, bar.title, {left = title_left, right = title_left + 14, bottom = bottom})
}
