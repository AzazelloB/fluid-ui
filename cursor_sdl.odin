package fluid

import "vendor:sdl3"

@(private="package")
SDL_Cursors :: struct {
	pointer, move: ^sdl3.Cursor,
}

@(private="package")
create_cursors :: proc() -> SDL_Cursors {
	return SDL_Cursors{
		pointer = sdl3.CreateSystemCursor(.POINTER),
		move = sdl3.CreateSystemCursor(.MOVE),
	}
}

@(private="package")
destroy_cursors :: proc(cursors: SDL_Cursors) {
	handles := [?]^sdl3.Cursor{cursors.pointer, cursors.move}
	for cursor in handles {
		if cursor != nil {
			sdl3.DestroyCursor(cursor)
		}
	}
}

@(private="package")
update_cursor :: proc(app: ^UI) {
	cursor: ^sdl3.Cursor
	if app.drag.element >= 0 {
		cursor = app.cursors.move
	} else if app.hovered >= 0 {
		element := get_element(app, Element_ID(app.hovered))
		cursor = element.draggable ? app.cursors.move : app.cursors.pointer
	}
	if cursor == nil {
		cursor = sdl3.GetDefaultCursor()
	}
	if cursor != nil && cursor != sdl3.GetCursor() {
		_ = sdl3.SetCursor(cursor)
	}
}
