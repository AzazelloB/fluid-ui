package main

import "core:fmt"
import fluid "../.."
import "../../elements"

Dock :: enum {Left, Right, Bottom}
CARD_SIZE :: [2]f32{15, 9}
DOCK_COLOR :: fluid.Color{32, 47, 59, 255}
DOCK_HIGHLIGHT :: fluid.Color{42, 85, 77, 255}

Docking :: struct {
	targets, card_scene:         ^fluid.Scene,
	area, card, placement:      fluid.Element_ID,
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
	scene := fluid.create_scene(ui.window)
	page.targets = fluid.create_scene(ui.window)
	page.card_scene = fluid.create_scene(ui.window)
	append(&entry.scenes, scene, page.card_scene)
	page.area = demo_surface(scene, {}, radius = 1.25)
	page.placement = elements.options(scene, {}, {"Free", "Left", "Right", "Bottom"}, 0)
	elements.on_change(ui, page.placement, page, choose_dock)
	labels := [Dock]string{.Left = "Left", .Right = "Right", .Bottom = "Bottom"}
	for dock in Dock {
		page.zones[dock] = demo_surface(page.targets, {}, DOCK_COLOR)
		fluid.set_label(ui, page.zones[dock], labels[dock])
		fluid.set_text_style(ui, page.zones[dock], .Body, MUTED)
	}
	layout_docking(page, ui, showcase_body(ui))
	area := fluid.bounds(ui, page.area)
	page.card = elements.draggable_panel(page.card_scene, card_at({area.left + 12.25, area.top + 4}), {54, 103, 91, 255})
	fluid.set_label(ui, page.card, "Drag")
	fluid.set_style(ui, page.card, {radius = 1, border = {120, 188, 161, 255}, border_width = 0.0625, shadow = 1})
	fluid.on_update(ui, page.area, page, update_docking)
}

card_at :: proc(position: [2]f32) -> fluid.Pins {
	return fluid.rect(position[0], position[1], CARD_SIZE[0], CARD_SIZE[1])
}

fill_floating_window :: proc(page: ^Docking, ui: ^fluid.UI) {
	fluid.set_layout(ui, page.card, fluid.bounds(ui, page.floating_scene.window.viewport))
}

move_floating_window :: proc(page: ^Docking, ui: ^fluid.UI, mouse: [2]f32) -> bool {
	// Use desktop coordinates and the original grab point, never a position delta.
	window := page.floating_scene.window
	grab := page.grab * (fluid.window_scale(window) / fluid.UI_UNIT_POINTS)
	position := fluid.desktop_point(ui.window, mouse) - grab
	if !fluid.set_window_position(window, position) {
		fmt.eprintln("Cannot move floating window")
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
			flags = {.Hidden, .Borderless},
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
	if !fluid.show_window(window) {
		page.detach_failed = true
		fmt.eprintln("Cannot show floating window")
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
	page.docked = dock
	elements.set_choice(ui, page.placement, int(dock) + 1)
	fluid.set_label(ui, page.card, dock == .Bottom ? "Horizontal card" : "Vertical card")
	fluid.animate_to(ui, page.card, fluid.bounds(ui, page.zones[dock]), damped_animation(0.4))
}

reset_card :: proc(page: ^Docking, ui: ^fluid.UI) {
	return_card(page, ui)
	page.docked = nil
	elements.set_choice(ui, page.placement, 0)
	area := fluid.bounds(ui, page.area)
	fluid.set_layout(ui, page.card, card_at({area.left + 12.25, area.top + 4}))
	fluid.set_label(ui, page.card, "Drag")
}

choose_dock :: proc(page: ^Docking, ui: ^fluid.UI, change: elements.Control_Change) {
	index := change.value.(int)
	if index == 0 {
		reset_card(page, ui)
		return
	}
	return_card(page, ui)
	dock_card(page, ui, Dock(index - 1))
}

leave_docking :: proc(app: ^Showcase, ui: ^fluid.UI) {
	page := &app.docking
	// The detached window belongs to this demo; return its card before closing.
	if page.floating_scene != nil {
		reset_card(page, ui)
	}
	fluid.deactivate(page.targets)
}

layout_docking :: proc(page: ^Docking, ui: ^fluid.UI, viewport: fluid.Pins) {
	area := content_pins(ui, page.navigation, viewport)
	fluid.set_target(ui, page.area, area)
	fluid.set_target(ui, page.placement, fluid.rect(area.left + 0.75, area.top + 0.75, 21, 2.25))
	fluid.set_target(ui, page.zones[.Left], {
		left = area.left + 0.75, top = area.top + 3.75, right = area.left + 10.75, bottom = area.bottom - 8.5,
	})
	fluid.set_target(ui, page.zones[.Right], {
		left = area.right - 10.75, top = area.top + 3.75, right = area.right - 0.75, bottom = area.bottom - 8.5,
	})
	fluid.set_target(ui, page.zones[.Bottom], {
		left = area.left + 0.75, top = area.bottom - 7, right = area.right - 0.75, bottom = area.bottom - 0.75,
	})
}

update_docking :: proc(page: ^Docking, ui: ^fluid.UI, dt: f64) {
	layout_docking(page, ui, showcase_body(ui))
	dropped := fluid.dropped(ui, page.card)
	in_drag := fluid.dragging(ui, page.card) || dropped
	if !in_drag {
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
		elements.set_choice(ui, page.placement, 0)
		page.drag_origin = fluid.pointer_position(ui.window)
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
				fmt.eprintln("Cannot resize floating window")
			}
		}
		fluid.activate(page.targets)
		fluid.bring_to_front(ui, page.card)
	}
	if !in_drag {
		return
	}
	defer if dropped { fluid.deactivate(page.targets) }
	mouse := fluid.pointer_position(ui.window)
	page.drag_moved = page.drag_moved || mouse != page.drag_origin
	r := card_at(mouse - page.grab)
	viewport := fluid.bounds(ui, ui.window.viewport)
	card_fits := r.left >= viewport.left && r.top >= viewport.top &&
		r.right <= viewport.right && r.bottom <= viewport.bottom
	selected: Maybe(Dock)
	for dock in Dock {
		over := fluid.contains(fluid.bounds(ui, page.zones[dock]), mouse)
		if over {
			selected = dock
		}
		fluid.set_color(ui, page.zones[dock], over ? DOCK_HIGHLIGHT : DOCK_COLOR)
	}
	dock_on_drop := dropped && selected != nil
	card_is_floating := page.floating_scene != nil && fluid.element_window(ui, page.card) == page.floating_scene.window
	if page.drag_moved && card_is_floating && (card_fits || dock_on_drop) {
		fluid.transfer(ui, page.card, page.card_scene)
		fluid.set_layout(ui, page.card, r)
		fluid.rebase_drag(ui, page.card)
		// Keep the source window alive until release so mouse capture survives.
		_ = fluid.hide_window(page.floating_scene.window)
		card_is_floating = false
	}
	if card_is_floating {
		if page.drag_moved {
			_ = move_floating_window(page, ui, mouse)
		} else {
			fill_floating_window(page, ui)
		}
		if dropped {
			fluid.set_label(ui, page.card, "Drag back to dock")
		}
		return
	}
	if !card_fits && !dock_on_drop && !page.detach_failed {
		detach_card(page, ui, mouse)
		if !page.detach_failed {
			if dropped {
				fluid.set_label(ui, page.card, "Drag back to dock")
			}
			return
		}
	}
	if !dropped {
		fluid.set_layout(ui, page.card, r)
		return
	}
	return_card(page, ui)
	if dock, ok := selected.?; ok {
		dock_card(page, ui, dock)
		return
	}
	// Keep a card released in the main window fully visible.
	fluid.set_layout(ui, page.card, card_at({
		clamp(r.left, viewport.left, max(viewport.left, viewport.right - CARD_SIZE[0])),
		clamp(r.top, viewport.top, max(viewport.top, viewport.bottom - CARD_SIZE[1])),
	}))
}
