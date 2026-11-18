package fluid

UI_UNIT_POINTS :: f32(16)

Text_Size :: enum {Body, Caption, Heading, Title}
text_size_units :: proc(size: Text_Size) -> f32 {
	switch size {
	case .Body: return 1
	case .Caption: return 0.8
	case .Heading: return 1.5
	case .Title: return 2.5
	}
	unreachable()
}
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

// The transition clock lives alongside its target.
Motion :: struct {
	from:      Pins,
	elapsed:   f64,
	progress:  f32,
	animation: Animation,
	frame:     u64,
}

Element :: struct {
	generation:    u32,
	alive:         bool,
	space:         ^Window, // Viewport sources have no scene.
	pins:          Pins,
	color:         Color,
	label:         string,
	style:         Style,
	text_size:     Text_Size,
	text_align:    Text_Align,
	text_weight:   Text_Weight,
	text_wrap:     bool,
	text_color:    Color,
	text:          ^Text,
	selected:      bool,
	focusable:     bool,
	behavior:      Element_Behavior,
	draw:          Element_Draw,
	cursor:        Cursor,
	surface, pressable: bool,
	draggable:     bool,
	pointer:       Pointer_Behavior,
	owner:         ^Scene,
	motion:        Motion,
	press:         Element_Callback(Element_ID),
	update:        Element_Callback(f64),
}
