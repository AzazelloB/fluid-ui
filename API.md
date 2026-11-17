# Units and geometry

All public lengths are plain `f32` values in UI units. One UI unit equals the
base font size, initially 16 logical points. Pins, padding, radii, text
measurements, window sizes/positions, and pointer coordinates use that unit.
Display density is handled at the SDL boundary.

Set `Config.base_font_size` in `init`/`run`, or use
`set_base_font_size(ui, logical_points)` later. The base size is shared by all
windows. Changing it keeps native window sizes unchanged, so their available
size in UI units changes.

## Pass values

`bounds` returns a struct of numeric edges. Widgets take the same struct:

```odin
viewport := fluid.bounds(ui, ui.window.viewport)
sidebar := fluid.panel(scene, {
    left = viewport.right - 18.75,
    top = 1.5,
    right = viewport.right - 2.25,
    bottom = viewport.bottom - 1.5,
}, color)
```

There are no layout callbacks, stored expressions, or implicit references.
Changing `viewport` afterward does not change `sidebar`. To respond to resizing
or another element moving, calculate new values and send them again. Each demo
owns that work in its ordinary update handler.

`Pins` contains `left`, `top`, `right`, and `bottom`. Those are coordinates, not
width/height. Fixed size is ordinary math: `right = left + width`. Centering and
proportions also use ordinary math. Omitted fields default to zero. Crossed
edges collapse to zero extent; empty rectangles are not drawn or hit.
Non-finite pins assert.

`width(pins)` and `height(pins)` return nonnegative dimensions.
`translated(pins, {dx, dy})` moves both corners without changing size.
`content_size(ui, id)` measures an element's full text in UI units, using its
current width when wrapping is enabled.

`set_text_style` accepts regular or bold weight and left, center, or right
alignment. `set_text_wrap(ui, id)` lays text out from the top of its bounds,
wraps it to the available width, and clips it to the bounds. Use
`text_line_height(window, size, weight)` to size the visible area by line count
or pass a wrap width to `measure_text` to measure the full block.

## Update and animate

- `set_layout(ui, id, pins)` sets numeric pins and cancels any animation.
- `animate_to(ui, id, pins, animation)` animates from the current visible pins
  to the supplied destination.
- `set_target(ui, id, pins)` updates the destination without restarting the
  animation. Without an animation, the new pins take effect immediately.
- `retarget(ui, id, pins, animation)` starts a replacement transition while
  preserving its completion callback.
- `bounds(ui, id)` reads the visible pins; `bounds(ui, id, target = true)` reads
  the destination pins. Animation samplers receive and return `Pins`.

Dragging moves the element's numeric pins. Other elements move with it only if
application code updates them. Removing an element invalidates its ID; other
elements retain their own values.

## Windows

Bounds and pointer coordinates are window-local. `bounds_in(ui, id, window)`
converts to another window's coordinates, or desktop coordinates for `nil`.
`transfer` preserves the element ID and animation progress, translating its
pins and animation origin to preserve desktop position.

Use `window_position`, `pointer_position`, `set_window_position`, and
`set_window_size` for UI units. Raw SDL APIs still expect SDL's own units.
