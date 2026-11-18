package main

import fluid "../.."
import "../../elements"

Catalog_Product :: struct {
	name, finish, price, description: string,
	battery, weight: string,
	backdrop, shell, grille, accent: fluid.Color,
}

CATALOG_PRODUCTS :: [3]Catalog_Product{
	{
		"Sol", "Apricot / Warm white", "$89",
		"Pocket-size sound for sunny afternoons.\n\nSol slips into a small bag and keeps a playlist going from breakfast to the walk home.",
		"12 hours", "310 g",
		{248, 202, 157, 255}, {174, 77, 54, 255}, {96, 47, 42, 255}, {255, 224, 184, 255},
	},
	{
		"Tide", "Sea glass / Deep teal", "$119",
		"Splash-resistant sound for poolside days.\n\nTide has a grippy shell and enough battery to keep playing well into the evening.",
		"16 hours", "420 g",
		{160, 220, 205, 255}, {39, 119, 110, 255}, {27, 66, 67, 255}, {195, 255, 226, 255},
	},
	{
		"Dusk", "Lavender / Ink", "$149",
		"Deeper bass for evenings that run late.\n\nDusk keeps the low end warm at quiet volumes and has enough power for company.",
		"20 hours", "570 g",
		{198, 190, 241, 255}, {109, 89, 176, 255}, {60, 51, 100, 255}, {227, 213, 255, 255},
	},
}

Catalog_Part :: enum {
	Surface, Backdrop, Shell, Grille, Slot_Top, Slot_Middle, Slot_Bottom, Light,
	Name, Finish, Price, Description,
}

Catalog_Card :: struct {
	parts: [Catalog_Part]fluid.Element_ID,
	specs: [4]fluid.Element_ID,
}

Catalog :: struct {
	navigation, scrim, back: fluid.Element_ID,
	cards: [len(CATALOG_PRODUCTS)]Catalog_Card,
	selected: Maybe(int),
	reveal: f32,
	opening: bool,
}

CATALOG_DURATION :: 0.52

create_catalog :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	catalog := &app.catalog
	catalog.navigation = app.sidebar
	scene := fluid.create_scene(ui.window)
	append(&entry.scenes, scene)
	catalog.scrim = elements.panel(scene, {}, {})
	fluid.set_pointer_behavior(ui, catalog.scrim, .Block)
	catalog.back = elements.button(scene, {}, "‹ Back")
	fluid.set_style(ui, catalog.back, {radius = 1.25})
	fluid.on_press(ui, catalog.back, catalog, close_catalog_card)

	for product, index in CATALOG_PRODUCTS {
		card := &catalog.cards[index]
		card.parts[.Surface] = elements.button(scene, {}, "")
		fluid.set_color(ui, card.parts[.Surface], SURFACE)
		fluid.set_draw(ui, card.parts[.Surface], fluid.draw_default)
		fluid.on_press(ui, card.parts[.Surface], catalog, open_catalog_card)
		card.parts[.Backdrop] = elements.panel(scene, {}, product.backdrop)
		card.parts[.Shell] = elements.panel(scene, {}, product.shell)
		card.parts[.Grille] = elements.panel(scene, {}, product.grille)
		for slot in Catalog_Part.Slot_Top..=Catalog_Part.Slot_Bottom {
			card.parts[slot] = elements.panel(scene, {}, product.shell)
		}
		card.parts[.Light] = elements.panel(scene, {}, product.accent)
		card.parts[.Name] = demo_text(scene, {}, product.name, .Heading, weight = .Bold)
		card.parts[.Finish] = demo_text(scene, {}, product.finish, .Caption, MUTED)
		card.parts[.Price] = demo_text(scene, {}, product.price, align = .Right)
		card.parts[.Description] = demo_text(scene, {}, product.description, .Body, {183, 194, 209, 255})
		fluid.set_text_wrap(ui, card.parts[.Description])

		card.specs = {
			demo_text(scene, {}, "BATTERY", .Caption, MUTED),
			demo_text(scene, {}, product.battery, weight = .Bold),
			demo_text(scene, {}, "WEIGHT", .Caption, MUTED),
			demo_text(scene, {}, product.weight, weight = .Bold),
		}
	}
	fluid.on_update(ui, catalog.scrim, catalog, update_catalog)
	update_catalog(catalog, ui, 0)
}

open_catalog_card :: proc(catalog: ^Catalog, ui: ^fluid.UI, id: fluid.Element_ID) {
	if _, selected := catalog.selected.?; selected {
		return
	}
	for &card, index in catalog.cards {
		if id == card.parts[.Surface] {
			catalog.selected = index
			catalog.opening = true
			fluid.bring_to_front(ui, catalog.scrim)
			for part in card.parts { fluid.bring_to_front(ui, part) }
			for spec in card.specs { fluid.bring_to_front(ui, spec) }
			fluid.bring_to_front(ui, catalog.back)
			return
		}
	}
}

close_catalog_card :: proc(catalog: ^Catalog, ui: ^fluid.UI, id: fluid.Element_ID) {
	catalog.opening = false
}

leave_catalog :: proc(app: ^Showcase, ui: ^fluid.UI) {
	catalog := &app.catalog
	catalog.selected = nil
	catalog.opening = false
	catalog.reveal = 0
	update_catalog(catalog, ui, 0)
}

CATALOG_ART_HEIGHT :: 9.5
CATALOG_INSET :: 0.875

catalog_card_layout :: proc(x, y, w, preview_height: f32) -> [Catalog_Part]fluid.Pins {
	layout: [Catalog_Part]fluid.Pins
	art := fluid.rect(x + CATALOG_INSET, y + CATALOG_INSET, w - 2 * CATALOG_INSET, CATALOG_ART_HEIGHT)
	layout[.Backdrop] = art
	layout_catalog_copy(&layout, art.left, art.bottom + 0.75, fluid.width(art), preview_height)
	layout[.Surface] = {x, y, x + w, layout[.Description].bottom + CATALOG_INSET}
	return layout
}

layout_catalog_copy :: proc(layout: ^[Catalog_Part]fluid.Pins, x, y, w, description_height: f32) {
	price_width := f32(3.5)
	layout[.Name] = fluid.rect(x, y, w - price_width, 1.85)
	layout[.Price] = fluid.rect(x + w - price_width, y + 0.2, price_width, 1.85)
	layout[.Finish] = fluid.rect(x, y + 1.95, w, 1.1)
	layout[.Description] = fluid.rect(x, y + 3.625, w, description_height)
}

catalog_detail_layout :: proc(viewport: fluid.Pins, window: ^fluid.Window, description: string) -> [Catalog_Part]fluid.Pins {
	layout: [Catalog_Part]fluid.Pins
	content_width := min(f32(72), fluid.width(viewport) - 5)
	left := (viewport.right - content_width) / 2
	top := max(f32(2.5), (viewport.bottom - 36) / 2)
	art_width := content_width * 0.57
	art := fluid.rect(left, top, art_width, min(f32(36), viewport.bottom - top - 2.5))
	x := art.right + 2.5
	y := art.top + min(f32(5), fluid.height(art) * 0.16)
	w := viewport.right - left - x
	layout[.Surface] = viewport
	layout[.Backdrop] = art
	_, description_height := fluid.measure_text(window, description, wrap_width = w)
	layout_catalog_copy(&layout, x, y, w, description_height)
	return layout
}

layout_catalog_art :: proc(ui: ^fluid.UI, card: ^Catalog_Card, layout: ^[Catalog_Part]fluid.Pins, progress: f32) {
	// Size the speaker inside the current artwork bounds so its proportions stay intact.
	art := layout[.Backdrop]
	w := min(fluid.width(art) * 0.7, fluid.height(art) * 1.15)
	h := w * 0.54
	x := (art.left + art.right - w) / 2
	y := (art.top + art.bottom - h) / 2
	fluid.set_style(ui, card.parts[.Backdrop], {radius = 0.65 + progress * 0.6})
	layout[.Shell] = fluid.rect(x, y, w, h)
	fluid.set_style(ui, card.parts[.Shell], {radius = h * 0.26, shadow = w * 0.045})
	layout[.Grille] = fluid.rect(x + w * 0.08, y + h * 0.13, w * 0.68, h * 0.74)
	fluid.set_style(ui, card.parts[.Grille], {radius = h * 0.18})
	for slot in Catalog_Part.Slot_Top..=Catalog_Part.Slot_Bottom {
		row := f32(int(slot) - int(Catalog_Part.Slot_Top))
		layout[slot] = fluid.rect(x + w * 0.17, y + h * (0.33 + row * 0.145), w * 0.5, h * 0.045)
		fluid.set_style(ui, card.parts[slot], {radius = h * 0.0225})
	}
	layout[.Light] = fluid.rect(x + w * 0.84, y + h * 0.44, h * 0.12, h * 0.12)
	fluid.set_style(ui, card.parts[.Light], {radius = h * 0.06})
}

morph_catalog_card :: proc(grid, detail: [Catalog_Part]fluid.Pins, reveal, progress: f32) -> [Catalog_Part]fluid.Pins {
	layout: [Catalog_Part]fluid.Pins
	layout[.Surface] = lerp_pins(grid[.Surface], detail[.Surface], progress)
	layout[.Backdrop] = lerp_pins(grid[.Backdrop], detail[.Backdrop], progress)
	// The labels travel below the artwork, then rise beside its right edge.
	around := smoothstep(clamp(reveal / 0.56, 0, 1))
	up := smoothstep(clamp((reveal - 0.5) / 0.5, 0, 1))
	layout[.Backdrop].bottom = grid[.Backdrop].bottom + (detail[.Backdrop].bottom - grid[.Backdrop].bottom) * up
	from_edge := grid[.Name].left - grid[.Backdrop].right
	to_edge := detail[.Name].left - detail[.Backdrop].right
	x := layout[.Backdrop].right + from_edge + (to_edge - from_edge) * around
	y := grid[.Name].top + (detail[.Name].top - grid[.Name].top) * up
	paragraph := lerp_pins(grid[.Description], detail[.Description], progress)
	w := min(fluid.width(paragraph), layout[.Surface].right - x - CATALOG_INSET)
	preview_height := fluid.height(grid[.Description])
	height := preview_height + (fluid.height(detail[.Description]) - preview_height) * up
	layout_catalog_copy(&layout, x, y, w, height)
	return layout
}

layout_catalog_specs :: proc(ui: ^fluid.UI, card: ^Catalog_Card, description: fluid.Pins, reveal: f32) {
	if reveal <= 0.78 {
		for id in card.specs { fluid.set_layout(ui, id, {}) }
		return
	}
	opacity := smoothstep(clamp((reveal - 0.78) / 0.22, 0, 1))
	x := description.left
	y := description.bottom + 1.75 + (1 - opacity) * 0.6
	w := fluid.width(description)
	spec_gap := w * 0.51
	pins := [4]fluid.Pins{
		fluid.rect(x, y, spec_gap, 1.25),
		fluid.rect(x, y + 1.25, spec_gap, 1.8),
		fluid.rect(x + spec_gap, y, w - spec_gap, 1.25),
		fluid.rect(x + spec_gap, y + 1.25, w - spec_gap, 1.8),
	}
	for id, i in card.specs {
		value := i % 2 != 0
		color := value ? INK : MUTED
		color.a = u8(255 * opacity)
		fluid.set_text_style(ui, id, value ? .Body : .Caption, color, .Left, value ? .Bold : .Regular)
		fluid.set_layout(ui, id, pins[i])
	}
}

update_catalog :: proc(catalog: ^Catalog, ui: ^fluid.UI, dt: f64) {
	delta := f32(dt / CATALOG_DURATION)
	if !catalog.opening { delta = -delta }
	catalog.reveal = clamp(catalog.reveal + delta, 0, 1)
	closed: Maybe(int)
	if !catalog.opening && catalog.reveal == 0 {
		closed = catalog.selected
		catalog.selected = nil
	}

	viewport := fluid.bounds(ui, ui.window.viewport)
	navigation := fluid.bounds(ui, catalog.navigation)
	grid_width := min(f32(52), viewport.right - navigation.right - 4)
	left := navigation.right + (viewport.right - navigation.right - grid_width) / 2
	card_width := (grid_width - 2.5) / len(catalog.cards)
	preview_height := 2 * fluid.text_line_height(ui.window)

	index, selected := catalog.selected.?
	fluid.set_layout(ui, catalog.scrim, selected ? viewport : fluid.Pins{})
	fluid.set_color(ui, catalog.scrim, {8, 12, 18, u8(190 * smoothstep(catalog.reveal))})
	back_was_visible := fluid.width(fluid.bounds(ui, catalog.back)) > 0
	fluid.set_layout(ui, catalog.back, {})

	for product, i in CATALOG_PRODUCTS {
		card := &catalog.cards[i]
		x := left + f32(i) * (card_width + 1.25)
		layout := catalog_card_layout(x, 1.5, card_width, preview_height)
		expanded := selected && i == index
		reveal := expanded ? catalog.reveal : 0
		progress := smoothstep(reveal)
		if expanded {
			detail := catalog_detail_layout(viewport, ui.window, product.description)
			layout = morph_catalog_card(layout, detail, reveal, progress)
			if reveal > 0.78 {
				art := layout[.Backdrop]
				alpha := u8(255 * smoothstep((reveal - 0.78) / 0.22))
				back := fluid.rect(art.left + 0.75, art.top + 0.75, 4.75, 2.5)
				fluid.set_layout(ui, catalog.back, back)
				if !back_was_visible && fluid.has_focus(ui, card.parts[.Surface]) {
					fluid.focus(ui, catalog.back)
				}
				fluid.set_color(ui, catalog.back, {24, 33, 45, alpha})
				fluid.set_text_style(ui, catalog.back, .Body, {INK.r, INK.g, INK.b, alpha})
			}
		}
		layout_catalog_art(ui, card, &layout, progress)
		for part in Catalog_Part {
			fluid.set_layout(ui, card.parts[part], layout[part])
		}
		fluid.set_pointer_behavior(ui, card.parts[.Surface], expanded ? .Pass : .Auto)
		fluid.set_style(ui, card.parts[.Surface], {
			radius = 1.125 * (1 - progress),
			border = EDGE,
			hover_border = MUTED,
			focus_border = MINT,
			border_width = 0.0625 * (1 - progress),
			shadow = 0.35 * (1 - progress),
		})
		layout_catalog_specs(ui, card, layout[.Description], reveal)
	}
	if closed_index, did_close := closed.?; did_close && fluid.has_focus(ui, catalog.back) {
		fluid.focus(ui, catalog.cards[closed_index].parts[.Surface])
	}
}
