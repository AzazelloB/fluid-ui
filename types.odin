package fluid

import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

TEXT_PADDING :: 16
FONT_SIZE :: 16

Element_Kind :: enum {Panel, Button, Label}
Rect :: sdl3.FRect
Color :: sdl3.Color

Element_ID :: distinct int
Group_ID :: distinct int
Attribute :: enum {Left, Top, Right, Bottom, Width, Height, Content_Width}

Anchor :: struct {
	element:   Element_ID,
	attribute: Attribute,
	target:    bool, // Read the destination rather than an in-flight value.
}

// A group is an explicit set of references, not an ownership relationship.
Maximum :: struct {
	group:     Group_ID,
	attribute: Attribute,
	padding:   f32,
	minimum:   f32,
}

Distance :: struct {
	from, to: Anchor,
}

Motion_Sample :: proc(from, to: Rect, elapsed, duration: f64) -> Rect

Motion :: struct {
	from: Rect,
	elapsed, duration: f64,
	sample: Motion_Sample,
}

Value :: struct {
	// An empty source makes offset a literal value.
	source: union {Anchor, Maximum, Distance},
	offset: f32,
}

Element :: struct {
	kind:      Element_Kind,
	position:  [2]Value,
	size:      [2]Value,
	color:     sdl3.Color,
	label:     string,
	text:      ^ttf.Text,
	text_label: string,
	selected:  bool,
	draggable: bool,
	owner: ^Scene,
	motion: Motion,
}
