# Units and geometry

All public lengths are plain `f32` values in UI units. One UI unit equals
16 logical points (`UI_UNIT_POINTS`). Pins, radii, text measurements, window
sizes and positions, and pointer coordinates use that unit. Display density is
handled at the SDL boundary.

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
`rect(x, y, width, height)` builds edge coordinates from a position and size.
`contains(pins, point)` includes the left and top edges and excludes the right
and bottom edges.
`translated(pins, {dx, dy})` moves both corners without changing size.

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
- `bounds(ui, id)` reads the visible pins. Animation samplers receive and
  return `Pins`.

Dragging moves the element's numeric pins. Other elements move with it only if
application code updates them. Removing an element invalidates its ID; other
elements retain their own values.

## Pointer input

Pointer hit testing checks active elements from front to back. An element
with the default `.Auto` pointer behavior receives hits if it is a button,
is draggable, or has an `on_press` handler. Use
`set_pointer_behavior(ui, id, .Pass)` to let hits through or `.Block` to
stop hits at the element. For example, a scrim can block the controls behind
it while a Back button above it still receives hits.

Presses use the coordinates of the mouse-down event. Behavior callbacks see
hover from before behavior dispatch. Fluid refreshes hover again after
layout and window changes so the cursor and drawing use the same result.
Set `Style.hover_border` to draw a different border color while hovered.

## Windows

Bounds and pointer coordinates are window-local.
`transfer` preserves the element ID and animation progress, translating its
pins and animation origin to preserve desktop position.

Use `window_position`, `pointer_position`, `set_window_position`, and
`set_window_size` for UI units. Multiply UI units by `pixel_scale(window)`
when drawing directly into an SDL renderer.
