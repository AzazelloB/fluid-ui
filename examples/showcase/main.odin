package main

import "core:fmt"
import "core:mem"
import virtual "core:mem/virtual"
import fluid "../.."

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
	if !fluid.init(&ui, {title = "Fluid UI", size = {1000, 700}, minimum_size = {900, 540}}) { return }
	defer fluid.destroy(&ui)

	app: Showcase
	create_showcase(&app, &ui)
	for ui.running {
		dt := fluid.begin_frame(&ui)
		fluid.requests(&ui)
		if !ui.running { break }
		fluid.update(&ui, dt)
		update_showcase(&app, &ui)
		fluid.draw(&ui)
		_ = mem.free_all(context.temp_allocator)
	}
}
