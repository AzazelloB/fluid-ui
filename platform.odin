package fluid

import "core:time"

Key :: enum {
	Unknown,
	A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	Digit_0, Digit_1, Digit_2, Digit_3, Digit_4, Digit_5, Digit_6, Digit_7, Digit_8, Digit_9,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
	Backspace, Delete, Down, End, Escape, Home, Insert, Enter, Keypad_Enter,
	Left, Page_Down, Page_Up, Right, Space, Tab, Up,
}
Key_Modifier :: enum {Shift, Ctrl, Alt, Gui}
Key_Modifiers :: bit_set[Key_Modifier]

Keyboard_Event :: struct {
	key: Key,
	modifiers: Key_Modifiers,
	down, repeat: bool,
	timestamp: u64,
}
Text_Input_Event :: struct {text: string}
Text_Editing_Event :: struct {
	text: string,
	start, length: i32, // Unicode code point indices within the composition.
}

@(private="package")
Platform_Event :: struct {
	kind: enum {
		Quit, Close, Resize, Focus_Lost, Mouse_Leave, Mouse_Move, Mouse_Down, Mouse_Up,
		Wheel, Key, Text_Edit, Text_Input,
	},
	window: ^Window,
	position: [2]f32, // Native window coordinates.
	timestamp: u64,
	clicks: u8,
	modifiers: Key_Modifiers, // Mouse-down modifiers at event time.
	wheel: f32,
	key: Keyboard_Event,
	edit: Text_Editing_Event,
	text: Text_Input_Event,
}

// Monotonic nanoseconds for input and animation timestamps.
monotonic_ns :: proc "contextless" () -> u64 {
	return u64(time.duration_nanoseconds(time.tick_diff({}, time.tick_now())))
}

set_text_input :: proc(window: ^Window, enabled: bool) {
	platform_text_input(window, enabled)
}

clear_composition :: proc(window: ^Window) {
	platform_clear_composition(window)
}

// Position the native IME candidate window using native client coordinates.
set_text_input_area :: proc(window: ^Window, area: IRect) {
	platform_text_input_area(window, {area.x, area.y, area.w, area.h})
}

set_clipboard_text :: proc(window: ^Window, text: string) -> bool {
	return platform_clipboard_set(window, text)
}

// Returned text remains valid until the frame's temporary storage is cleared.
get_clipboard_text :: proc(window: ^Window) -> string {
	return platform_clipboard_get(window)
}
