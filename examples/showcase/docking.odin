package main

import "core:fmt"
import fluid "../.."
import "vendor:sdl3"

Dock :: enum {Left, Right, Bottom}
CARD_SIZE :: [2]f32{15, 9}

Docking :: struct {
	scene, targets, card_scene: ^fluid.Scene,
	area, card:                 fluid.Element_ID,
	navigation:                 fluid.Element_ID,
	docked:                     Maybe(Dock),
	zones:                      [Dock]fluid.Element_ID,
	floating_scene:             ^fluid.Scene,
	grab:                       [2]f32,
	drag_origin:                [2]f32,
	drag_moved:                 bool,
	detach_failed:              bool,
}

create_docking :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.docking
	page.navigation = app.sidebar
	page.scene = fluid.create_scene(ui.window)
	page.targets = fluid.create_scene(ui.window)
	page.card_scene = fluid.create_scene(ui.window)
	append(&entry.scenes, page.scene, page.card_scene)
	viewport := fluid.bounds(ui, ui.window.viewport)
	navigation := fluid.bounds(ui, page.navigation)
	area := fluid.Pins{left = navigation.right + 2.25, top = 1.5, right = viewport.right - 2.25, bottom = viewport.bottom - 1.5}
	page.area = demo_surface(page.scene, area, radius = 1.25)
	page.zones[.Left] = demo_surface(page.targets, {
		left = area.left + 0.75, top = area.top + 0.75, right = area.left + 10.75, bottom = area.bottom - 8.5,
	}, {32, 47, 59, 255})
	page.zones[.Right] = demo_surface(page.targets, {
		left = area.right - 10.75, top = area.top + 0.75, right = area.right - 0.75, bottom = area.bottom - 8.5,
	}, {32, 47, 59, 255})
	page.zones[.Bottom] = demo_surface(page.targets, {
		left = area.left + 0.75, top = area.bottom - 7, right = area.right - 0.75, bottom = area.bottom - 0.75,
	}, {32, 47, 59, 255})
	for dock in Dock {
		fluid.set_label(ui, page.zones[dock], dock == .Bottom ? "Bottom" : dock == .Left ? "Left" : "Right")
		fluid.set_text_style(ui, page.zones[dock], .Body, MUTED)
	}
	page.card = fluid.draggable_panel(page.card_scene, card_at({area.left + 12.25, area.top + 3}), {54, 103, 91, 255})
	fluid.set_label(ui, page.card, "Drag")
	fluid.set_style(ui, page.card, {radius = 1, border = {120, 188, 161, 255}, border_width = 0.0625, shadow = 1})
	fluid.on_update(ui, page.area, page, update_docking)
}

contains :: proc(pins: fluid.Pins, point: [2]f32) -> bool {
	return point[0] >= pins.left && point[0] < pins.right && point[1] >= pins.top && point[1] < pins.bottom
}

card_at :: proc(position: [2]f32) -> fluid.Pins {
	return {
		left = position[0],
		top = position[1],
		right = position[0] + CARD_SIZE[0],
		bottom = position[1] + CARD_SIZE[1],
	}
}

fill_floating_window :: proc(page: ^Docking, ui: ^fluid.UI) {
	fluid.set_layout(ui, page.card, fluid.bounds(ui, page.floating_scene.window.viewport))
}

move_floating_window :: proc(page: ^Docking, ui: ^fluid.UI, mouse: [2]f32) -> bool {
	// Use desktop coordinates and the original grab point, never a position delta.
	position := fluid.window_position(ui.window) + mouse - page.grab
	if !fluid.set_window_position(page.floating_scene.window, position) {
		fmt.eprintln(sdl3.GetError())
		return false
	}
	fill_floating_window(page, ui)
	return true
}

detach_card :: proc(page: ^Docking, ui: ^fluid.UI, mouse: [2]f32) {
	if page.floating_scene == nil {
		window := fluid.create_window(ui, {
			title = "Fluid card",
			size = CARD_SIZE,
			minimum_size = {7.5, 5},
			flags = {.HIDDEN},
		})
		if window == nil {
			page.detach_failed = true
			return
		}
		page.floating_scene = fluid.create_scene(window)
		fluid.activate(page.floating_scene)
	}
	// Reuse the window if the same drag briefly brought the card back inside.
	window := page.floating_scene.window
	fluid.transfer(ui, page.card, page.floating_scene)
	if !move_floating_window(page, ui, mouse) {
		page.detach_failed = true
		return_card(page, ui)
		return
	}
	fluid.set_label(ui, page.card, "Drag back to dock")
	if !fluid.show_window(window) {
		page.detach_failed = true
		fmt.eprintln(sdl3.GetError())
		return_card(page, ui)
	}
}

return_card :: proc(page: ^Docking, ui: ^fluid.UI) {
	if page.floating_scene == nil {
		return
	}
	fluid.transfer(ui, page.card, page.card_scene)
	fluid.close_window(page.floating_scene.window)
	page.floating_scene = nil
}

dock_card :: proc(page: ^Docking, ui: ^fluid.UI, dock: Dock) {
	return_card(page, ui)
	page.docked = dock
	fluid.set_label(ui, page.card, dock == .Bottom ? "Horizontal card" : "Vertical card")
	fluid.animate_to(ui, page.card, fluid.bounds(ui, page.zones[dock]), {duration = 0.4, sample = smooth_damp, progress = damp_progress})
}

reset_card :: proc(page: ^Docking, ui: ^fluid.UI) {
	return_card(page, ui)
	page.docked = nil
	area := fluid.bounds(ui, page.area)
	fluid.set_layout(ui, page.card, card_at({area.left + 12.25, area.top + 3}))
	fluid.set_label(ui, page.card, "Drag")
}

leave_docking :: proc(app: ^Showcase, ui: ^fluid.UI) {
	page := &app.docking
	// The detached window belongs to this demo; return its card before closing.
	if page.floating_scene != nil {
		reset_card(page, ui)
	}
	fluid.deactivate(page.targets)
}

update_docking :: proc(page: ^Docking, ui: ^fluid.UI, dt: f64) {
	viewport := fluid.bounds(ui, ui.window.viewport)
	navigation := fluid.bounds(ui, page.navigation)
	area := fluid.Pins{left = navigation.right + 2.25, top = 1.5, right = viewport.right - 2.25, bottom = viewport.bottom - 1.5}
	fluid.set_target(ui, page.area, area)
	fluid.set_target(ui, page.zones[.Left], {
		left = area.left + 0.75, top = area.top + 0.75, right = area.left + 10.75, bottom = area.bottom - 8.5,
	})
	fluid.set_target(ui, page.zones[.Right], {
		left = area.right - 10.75, top = area.top + 0.75, right = area.right - 0.75, bottom = area.bottom - 8.5,
	})
	fluid.set_target(ui, page.zones[.Bottom], {
		left = area.left + 0.75, top = area.bottom - 7, right = area.right - 0.75, bottom = area.bottom - 0.75,
	})
	if !fluid.dragging(ui, page.card) && !fluid.dropped(ui, page.card) {
		if dock, ok := page.docked.?; ok {
			fluid.set_target(ui, page.card, fluid.bounds(ui, page.zones[dock]))
		}
		if page.floating_scene != nil {
			fill_floating_window(page, ui)
		}
	}
	if page.floating_scene != nil && page.floating_scene.window.close_requested {
		reset_card(page, ui)
		fluid.deactivate(page.targets)
		return
	}
	if fluid.drag_started(ui, page.card) {
		owner := fluid.element_window(ui, page.card)
		r := fluid.bounds(ui, page.card)
		mouse := fluid.pointer_position(owner)
		page.docked = nil
		page.drag_origin = fluid.window_position(owner) + mouse
		page.drag_moved = false
		page.detach_failed = false
		// Keep the same relative grab point as the docked shape contracts.
		fraction := [2]f32{clamp((mouse[0] - r.left) / fluid.width(r), 0, 1), clamp((mouse[1] - r.top) / fluid.height(r), 0, 1)}
		page.grab = fraction * CARD_SIZE
		position := mouse - page.grab
		// Return to the normal card size while preserving the grab point.
		fluid.set_layout(ui, page.card, card_at(position))
		fluid.set_label(ui, page.card, "Drag")
		fluid.rebase_drag(ui, page.card)
		if page.floating_scene != nil && owner == page.floating_scene.window {
			if !fluid.set_window_size(owner, CARD_SIZE) {
				fmt.eprintln(sdl3.GetError())
			}
		}
		fluid.activate(page.targets)
		fluid.bring_to_front(ui, page.card)
	}
	if !fluid.dragging(ui, page.card) && !fluid.dropped(ui, page.card) {
		return
	}
	mouse := fluid.pointer_position(ui.window)
	delta := fluid.window_position(ui.window) + mouse - page.drag_origin
	page.drag_moved = page.drag_moved || delta[0] * delta[0] + delta[1] * delta[1] > 0.0625
	if page.drag_moved && page.floating_scene != nil && fluid.element_window(ui, page.card) == page.floating_scene.window &&
		contains(fluid.bounds(ui, page.area), mouse) {
		// Move the actual element onto the main window's drawing surface.
		// Keep its source window alive until release so mouse capture survives.
		fluid.transfer(ui, page.card, page.card_scene)
		position := mouse - page.grab
		fluid.set_layout(ui, page.card, card_at(position))
		fluid.rebase_drag(ui, page.card)
		// Keep capture's source alive, but do not obscure the destination with it.
		_ = sdl3.HideWindow(page.floating_scene.window.handle)
	}
	selected: Maybe(Dock)
	for dock in Dock {
		over := contains(fluid.bounds(ui, page.zones[dock]), mouse)
		if over {
			selected = dock
		}
		fluid.set_color(ui, page.zones[dock], over ? fluid.Color{42, 85, 77, 255} : fluid.Color{32, 47, 59, 255})
	}
	if page.floating_scene != nil && fluid.element_window(ui, page.card) == page.floating_scene.window {
		if page.drag_moved {
			_ = move_floating_window(page, ui, mouse)
		} else {
			fill_floating_window(page, ui)
		}
		if fluid.dropped(ui, page.card) {
			fluid.set_label(ui, page.card, "Drag back to dock")
			fluid.deactivate(page.targets)
		}
		return
	} else {
		if page.floating_scene != nil && fluid.dropped(ui, page.card) {
			return_card(page, ui)
		}
		r := fluid.bounds(ui, page.card)
		outside := max(-mouse[0], mouse[0] - fluid.width(viewport), -mouse[1], mouse[1] - fluid.height(viewport))
		// Stay inside the edge until the cursor breaks the tear-off threshold.
		fluid.set_layout(ui, page.card, fluid.translated(r, {
			clamp(r.left, 0, max(f32(0), fluid.width(viewport) - fluid.width(r))) - r.left,
			clamp(r.top, 0, max(f32(0), fluid.height(viewport) - fluid.height(r))) - r.top,
		}))
		if outside > 3 && !page.detach_failed {
			detach_card(page, ui, mouse)
			if fluid.dropped(ui, page.card) {
				fluid.deactivate(page.targets)
			}
			return
		}
	}
	if fluid.dropped(ui, page.card) {
		if dock, ok := selected.?; ok {
			dock_card(page, ui, dock)
		}
		fluid.deactivate(page.targets)
	}
}
