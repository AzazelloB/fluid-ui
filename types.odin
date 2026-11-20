package fluid

UI_UNIT_POINTS :: f32(16)

Text_Align :: enum {Center, Left, Right}
Text_Weight :: enum {Regular, Bold}

Corner :: enum {Top_Right, Bottom_Right, Bottom_Left, Top_Left}

Style :: struct {
	radius: f32,
	border: Color,
	border_width: f32,
	shadow: f32,
	hover_border, focus_border: Maybe(Color),
	square_corners: bit_set[Corner],
}

Pointer_Behavior :: enum {Auto, Pass, Block}
Color :: struct {r, g, b, a: u8}

// Plain numbers are multiples of the UI's base font size. Pins describe an
// axis-aligned rectangle; right/bottom are coordinates, not dimensions.
Pins :: struct {
	left, top, right, bottom: f32,
}

// Low 32 bits identify a slot; upper bits identify its lifetime.
Element_ID :: distinct int

Motion_Sample :: proc(from, to: Pins, progress: f32) -> Pins

Element :: struct {
	generation:    u32,
	alive:         bool,
	window:        ^Window,
	pins:          Pins,
	focusable:     bool,
	behavior:      Element_Behavior,
	draw:          Element_Draw,
	cursor:        Cursor,
	pressable:     bool,
	draggable:     bool,
	pointer:       Pointer_Behavior,
	window_hit:    Window_Hit,
	draw_order:    u64,
	press:         Element_Callback(Element_ID),
	update:        Element_Callback(f64),
}
