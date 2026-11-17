package fluid

import virtual "core:mem/virtual"

// Pages own activation and lazy creation, not navigation layout or demo state.
// Define the fixed list and bind every tab before opening the first page.
Page :: struct($Owner: typeid) {
	title:   string,
	create:  proc(owner: ^Owner, ui: ^UI, page: ^Page(Owner)),
	leave:   proc(owner: ^Owner, ui: ^UI),
	tab:     Element_ID,
	scenes:  [dynamic]^Scene,
	created: bool,
}

Page_Set :: struct($Owner: typeid) {
	ui:      ^UI,
	owner:   ^Owner,
	entries: []Page(Owner),
	current: Maybe(int),
}

create_pages :: proc(pages: ^Page_Set($Owner), ui: ^UI, owner: ^Owner, definitions: []Page(Owner)) {
	assert(pages.ui == nil && owner != nil)
	context.allocator = virtual.arena_allocator(&ui.storage)
	pages.ui = ui
	pages.owner = owner
	pages.entries = make([]Page(Owner), len(definitions))
	copy(pages.entries, definitions)
}

bind_page_tab :: proc(pages: ^Page_Set($Owner), index: int, tab: Element_ID) {
	pages.entries[index].tab = tab
	on_press(pages.ui, tab, pages, select_page_tab)
}

open_page :: proc(pages: ^Page_Set($Owner), index: int) {
	assert(index >= 0 && index < len(pages.entries))
	ui := pages.ui
	context.allocator = virtual.arena_allocator(&ui.storage)
	if previous, exists := pages.current.?; exists {
		if previous == index {
			return
		}
		page := &pages.entries[previous]
		if page.leave != nil {
			page.leave(pages.owner, ui)
		}
		for scene in page.scenes {
			deactivate(scene)
		}
		set_selected(ui, page.tab, false)
	}
	page := &pages.entries[index]
	if !page.created {
		page.scenes = make([dynamic]^Scene)
		page.create(pages.owner, ui, page)
		page.created = true
	}
	for scene in page.scenes {
		activate(scene)
	}
	pages.current = index
	set_selected(ui, page.tab, true)
}

@(private="package")
select_page_tab :: proc(pages: ^Page_Set($Owner), ui: ^UI, id: Element_ID) {
	for page, index in pages.entries {
		if page.tab == id {
			open_page(pages, index)
			return
		}
	}
}
