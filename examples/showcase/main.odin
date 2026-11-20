package main

import "core:fmt"
import "core:os"
import fluid "../.."

main :: proc() {
	scale: f32 = 1
	flags := fluid.Window_Flags{.Transparent, .Custom_Title_Bar}
	for arg in os.args[1:] {
		switch arg {
		case "--large-ui":
			scale = 1.35
		case "--remote-navigation":
			flags |= {.Directional_Focus}
		}
	}
	app := Showcase{scale = scale}
	defer destroy_notebook(&app.notebook)
	when ODIN_OS == .Darwin {
		regular := #load("assets/BricolageGrotesque-Regular.ttf")
		bold := #load("assets/BricolageGrotesque-Bold.ttf")
		if !fluid.set_macos_text_fonts(regular, bold) {
			fmt.eprintln("Cannot load Bricolage Grotesque")
		}
	}
	defer {
		when ODIN_OS == .Darwin {
			fluid.clear_macos_text_fonts()
		}
	}
	fluid.run({
		title = SHOWCASE_TITLE,
		size = [2]f32{73, 46.5 + TITLE_BAR_HEIGHT} / scale,
		minimum_size = {22.5, 23.5 + TITLE_BAR_HEIGHT},
		flags = flags,
		ui_scale = scale,
		background = WINDOW_BACKGROUND, text_color = INK,
	}, &app, create_showcase)
}
