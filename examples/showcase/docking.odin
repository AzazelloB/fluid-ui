package main

import "core:fmt"
import fluid "../.."
import "vendor:sdl3"

Dock :: enum {Left, Right, Bottom}
CARD_SIZE :: [2]f32{240, 144}

Docking :: struct {
	scene, targets, card_scene: ^fluid.Scene,
	area, card:                 fluid.Element_ID,
	zones:                      [Dock]fluid.Element_ID,
	floating_scene:             ^fluid.Scene,
	grab:                       [2]f32,
	drag_origin:                [2]f32,
	drag_moved:                 bool,
	detach_failed:              bool,
}

create_docking :: proc(page: ^Docking, ui: ^fluid.UI, navigation: fluid.Element_ID) {
	page.scene = fluid.create_scene(ui.window)
	page.targets = fluid.create_scene(ui.window)
	page.card_scene = fluid.create_scene(ui.window)
	_ = fluid.label(page.scene,
		{fluid.relative(navigation, .Right, 24), fluid.at(32)},
		{fluid.distance(navigation, .Right, ui.window.viewport, .Right, -48), fluid.at(32)},
		"One element, multiple windows",
	)
	_ = fluid.label(page.scene,
		{fluid.relative(navigation, .Right, 24), fluid.at(72)},
		{fluid.distance(navigation, .Right, ui.window.viewport, .Right, -48), fluid.at(28)},
		"Drag to dock or pull past the edge to detach",
	)
	page.area = fluid.panel(page.scene,
		{fluid.relative(navigation, .Right, 24), fluid.at(124)},
		{fluid.distance(navigation, .Right, ui.window.viewport, .Right, -48), fluid.relative(ui.window.viewport, .Height, -148)},
		{28, 31, 39, 255},
	)
	page.zones[.Left] = fluid.panel(page.targets,
		{fluid.relative(page.area, .Left, 12), fluid.relative(page.area, .Top, 12)},
		{fluid.at(160), fluid.relative(page.area, .Height, -148)}, {42, 49, 64, 255},
	)
	page.zones[.Right] = fluid.panel(page.targets,
		{fluid.relative(page.area, .Right, -172), fluid.relative(page.area, .Top, 12)},
		{fluid.at(160), fluid.relative(page.area, .Height, -148)}, {42, 49, 64, 255},
	)
	page.zones[.Bottom] = fluid.panel(page.targets,
		{fluid.relative(page.area, .Left, 12), fluid.relative(page.area, .Bottom, -112)},
		{fluid.relative(page.area, .Width, -24), fluid.at(100)}, {42, 49, 64, 255},
	)
	for dock in Dock {
		fluid.set_label(ui, page.zones[dock], dock == .Bottom ? "Horizontal dock" : "Vertical dock")
	}
	page.card = fluid.draggable_panel(page.card_scene,
		{fluid.relative(page.area, .Left, 196), fluid.relative(page.area, .Top, 48)},
		{fluid.at(CARD_SIZE[0]), fluid.at(CARD_SIZE[1])}, {76, 137, 211, 255}, mode = .Independent,
	)
	fluid.set_label(ui, page.card, "Drag me")
}

contains :: proc(rect: fluid.Rect, point: [2]f32) -> bool {
	return point[0] >= rect.x && point[0] < rect.x + rect.w && point[1] >= rect.y && point[1] < rect.y + rect.h
}

fill_floating_window :: proc(page: ^Docking, ui: ^fluid.UI) {
	fluid.set_layout(ui, page.card, {fluid.at(0), fluid.at(0)},
		{fluid.relative(page.floating_scene.window.viewport, .Width), fluid.relative(page.floating_scene.window.viewport, .Height)})
}

move_floating_window :: proc(page: ^Docking, ui: ^fluid.UI, mouse: [2]f32) -> bool {
	// Use desktop coordinates and the original grab point, never a position delta.
	position := fluid.window_position(ui.window) + mouse - page.grab
	if !sdl3.SetWindowPosition(page.floating_scene.window.handle, i32(position[0]), i32(position[1])) {
		fmt.eprintln(sdl3.GetError())
		return false
	}
	fill_floating_window(page, ui)
	return true
}

detach_card :: proc(page: ^Docking, ui: ^fluid.UI, mouse: [2]f32) {
	if page.floating_scene == nil {
		window := fluid.create_window(ui, {
			title = "Fluid card — move by title bar",
			size = {i32(CARD_SIZE[0]), i32(CARD_SIZE[1])},
			minimum_size = {120, 80},
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
	// Present the complete content before revealing a newly created window.
	fluid.draw(ui, window)
	sdl3.RenderPresent(window.renderer)
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
	target := page.zones[dock]
	fluid.set_label(ui, page.card, dock == .Bottom ? "Horizontal card" : "Vertical card")
	fluid.animate_to(ui, page.card,
		{fluid.relative(target, .Left), fluid.relative(target, .Top)},
		{fluid.relative(target, .Width), fluid.relative(target, .Height)}, stack_animation(),
	)
}

reset_card :: proc(page: ^Docking, ui: ^fluid.UI) {
	return_card(page, ui)
	fluid.set_layout(ui, page.card,
		{fluid.relative(page.area, .Left, 196), fluid.relative(page.area, .Top, 48)},
		{fluid.at(CARD_SIZE[0]), fluid.at(CARD_SIZE[1])},
	)
	fluid.set_label(ui, page.card, "Drag me")
}

activate_docking :: proc(page: ^Docking) {
	fluid.activate(page.scene)
	fluid.activate(page.card_scene)
}

deactivate_docking :: proc(page: ^Docking, ui: ^fluid.UI) {
	// The detached window belongs to this page; closing it returns the same card.
	if page.floating_scene != nil {
		reset_card(page, ui)
	}
	fluid.deactivate(page.targets)
	fluid.deactivate(page.card_scene)
	fluid.deactivate(page.scene)
}

update_docking :: proc(page: ^Docking, ui: ^fluid.UI) {
	if page.floating_scene != nil && page.floating_scene.window.close_requested {
		reset_card(page, ui)
		fluid.deactivate(page.targets)
		return
	}
	if fluid.drag_started(ui, page.card) {
		owner := fluid.element_window(ui, page.card)
		r := fluid.bounds(ui, page.card)
		mouse := fluid.pointer_position(owner)
		page.drag_origin = fluid.window_position(owner) + mouse
		page.drag_moved = false
		page.detach_failed = false
		// Keep the same relative grab point as the docked shape contracts.
		fraction := [2]f32{clamp((mouse[0] - r.x) / r.w, 0, 1), clamp((mouse[1] - r.y) / r.h, 0, 1)}
		page.grab = fraction * CARD_SIZE
		position := mouse - page.grab
		fluid.set_layout(ui, page.card,
			{fluid.at(position[0]), fluid.at(position[1])}, {fluid.at(CARD_SIZE[0]), fluid.at(CARD_SIZE[1])})
		fluid.set_label(ui, page.card, "Drag me")
		fluid.rebase_drag(ui, page.card)
		if page.floating_scene != nil && owner == page.floating_scene.window {
			if !sdl3.SetWindowSize(owner.handle, i32(CARD_SIZE[0]), i32(CARD_SIZE[1])) {
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
	page.drag_moved = page.drag_moved || delta[0] * delta[0] + delta[1] * delta[1] > 16
	if page.drag_moved && page.floating_scene != nil && fluid.element_window(ui, page.card) == page.floating_scene.window &&
		contains(fluid.bounds(ui, page.area), mouse) {
		// Move the actual element onto the main window's drawing surface.
		// Keep its source window alive until release so mouse capture survives.
		fluid.transfer(ui, page.card, page.card_scene)
		position := mouse - page.grab
		fluid.set_layout(ui, page.card,
			{fluid.at(position[0]), fluid.at(position[1])}, {fluid.at(CARD_SIZE[0]), fluid.at(CARD_SIZE[1])})
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
		fluid.set_color(ui, page.zones[dock], over ? fluid.Color{61, 95, 143, 255} : fluid.Color{42, 49, 64, 255})
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
		viewport := fluid.bounds(ui, ui.window.viewport)
		r := fluid.bounds(ui, page.card)
		outside := max(-mouse[0], mouse[0] - viewport.w, -mouse[1], mouse[1] - viewport.h)
		// Stay inside the edge until the cursor breaks the tear-off threshold.
		fluid.set_layout(ui, page.card,
			{fluid.at(clamp(r.x, 0, max(f32(0), viewport.w - r.w))), fluid.at(clamp(r.y, 0, max(f32(0), viewport.h - r.h)))},
			{fluid.at(r.w), fluid.at(r.h)},
		)
		if outside > 48 && !page.detach_failed {
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
