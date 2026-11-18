package fluid

Cursor :: enum {Default, Pointer, Move, Text, Resize_Horizontal}

set_cursor :: proc(ui: ^UI, id: Element_ID, cursor: Cursor) {
	get_element(ui, id).cursor = cursor
}

@(private="package")
update_cursor :: proc(app: ^UI) {
	cursor := Cursor.Default
	if app.drag.element != NO_ELEMENT {
		cursor = .Move
	} else if id := app.captured != NO_ELEMENT ? app.captured : app.hovered; id != NO_ELEMENT {
		element := get_element(app, id)
		cursor = element.cursor
		if cursor == .Default && element.window_hit != .Drag {
			cursor = element.draggable ? .Move : .Pointer
		}
	}
	platform_set_cursor(app, cursor)
}
