package fluid

import "vendor:sdl3"

Cursor :: enum {Default, Pointer, Move, Text, Resize_Horizontal}

set_cursor :: proc(ui: ^UI, id: Element_ID, cursor: Cursor) {
	get_element(ui, id).cursor = cursor
}

@(private="package")
SDL_Cursors :: struct {
	pointer, move, text, resize: ^sdl3.Cursor,
}

@(private="package")
create_cursors :: proc() -> SDL_Cursors {
	return SDL_Cursors{
		pointer = sdl3.CreateSystemCursor(.POINTER),
		move = sdl3.CreateSystemCursor(.MOVE),
		text = sdl3.CreateSystemCursor(.TEXT),
		resize = sdl3.CreateSystemCursor(.EW_RESIZE),
	}
}

@(private="package")
destroy_cursors :: proc(cursors: SDL_Cursors) {
	handles := [?]^sdl3.Cursor{cursors.pointer, cursors.move, cursors.text, cursors.resize}
	for cursor in handles {
		if cursor != nil {
			sdl3.DestroyCursor(cursor)
		}
	}
}

@(private="package")
update_cursor :: proc(app: ^UI) {
	cursor: ^sdl3.Cursor
	if app.drag.element != NO_ELEMENT {
		cursor = app.cursors.move
	} else {
		id := app.captured != NO_ELEMENT ? app.captured : app.hovered
		if id != NO_ELEMENT {
			element := get_element(app, id)
			shape := element.cursor
			if shape == .Default {
				shape = element.draggable ? .Move : .Pointer
			}
			switch shape {
			case .Default:
			case .Pointer: cursor = app.cursors.pointer
			case .Move: cursor = app.cursors.move
			case .Text: cursor = app.cursors.text
			case .Resize_Horizontal: cursor = app.cursors.resize
			}
		}
	}
	if cursor == nil {
		cursor = sdl3.GetDefaultCursor()
	}
	if cursor != nil && cursor != sdl3.GetCursor() {
		_ = sdl3.SetCursor(cursor)
	}
}
