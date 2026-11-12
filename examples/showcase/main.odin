package main

import "core:fmt"
import "core:mem"
import virtual "core:mem/virtual"
import fluid "../.."
import "vendor:sdl3"

main :: proc() {
	// Application data has one lifetime, independent of the UI's storage.
	storage: virtual.Arena
	if err := virtual.arena_init_growing(&storage); err != nil {
		fmt.eprintln("Cannot initialize application storage:", err)
		return
	}
	defer virtual.arena_destroy(&storage)
	context.allocator = virtual.arena_allocator(&storage)

	ui: fluid.UI
	if !fluid.init(&ui, {
		title = "Fluid UI",
		size = {1000, 700},
		minimum_size = {900, 540},
		// Let SDL show the first window during creation, as in a plain SDL app.
		// Its transparent content provides the reveal without delaying startup.
		flags = {.TRANSPARENT, .BORDERLESS},
	}) {
		return
	}
	defer fluid.destroy(&ui)

	app: Showcase
	create_showcase(&app, &ui)
	launch := create_launch_reveal(ui.window)
	for ui.running {
		dt := fluid.begin_frame(&ui)
		fluid.requests(&ui)
		if !ui.running {
			break
		}
		fluid.update(&ui, dt)
		update_showcase(&app, &ui)
		reveal_complete := false
		for window in ui.windows {
			if window != ui.window && .HIDDEN in sdl3.GetWindowFlags(window.handle) {
				continue
			}
			fluid.draw(&ui, window)
			if window == ui.window {
				reveal_complete = draw_launch_reveal(&launch, window)
			}
			sdl3.RenderPresent(window.renderer)
		}
		if reveal_complete && !fluid.replace_window(ui.window, {}) {
			fmt.eprintln("Cannot replace reveal window:", sdl3.GetError())
			break
		}
		_ = mem.free_all(context.temp_allocator)
	}
}
