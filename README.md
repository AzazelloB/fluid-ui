# fluid-ui

An experimental UI library concept in Odin with SDL3. Elements live in a flat
list, with positions and sizes defined through references to other elements
rather than a parent-child tree.

The demo includes a sidebar sized from its button labels, hover and pressed
states, actions on mouse-down, and draggable panels with linked top edges.
Text uses SDL_ttf and the macOS system font at the display's pixel density.

## Run on macOS

Install Odin, SDL3, and SDL_ttf with Homebrew:

```sh
brew install odin sdl3 sdl3_ttf
odin run .
```

If the linker cannot find the Homebrew libraries on Apple Silicon:

```sh
odin run . -extra-linker-flags:"-L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib"
```

Click a menu button to select it. Drag either colored panel; their horizontal
positions are independent, and their top edges stay aligned. Resize the window
to see the sidebar follow its height. Press Escape to exit.

## Source

- `layout.odin`: demo layout and menu actions
- `widgets.odin`: panels, buttons, and visual states
- `ui.odin`: elements, references, content sizing, and hit testing
- `requests.odin`: input handling and dragging
- `text.odin`: text measurement and rendering
- `draw.odin`: drawing
- `update.odin`: application update hook
- `main.odin`: initialization and the event-driven loop

Check and build without running:

```sh
odin build . -vet -out:/tmp/fluid-ui-demo
```
