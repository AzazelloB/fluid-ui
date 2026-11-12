- [x] Page showcasing multi-window workflow
      A page with an element. Dragging reveals drop areas; dropping adapts the element to the area's dimensions and orientation. Pulling beyond the tear-off threshold creates a separate window immediately, following the cursor until release. Move that window by its title bar; drag its content back to dock.
- [x] Launch animation
      On open radially reveal the window from the mouse position. If opened by clicking then it works well, if opened through search or terminal then we might need another starting point if detectable. Possible approach: render a window transparent at first and then reveal from the mouse cursor that will be known by then. The app should launch as fast as possible for best effect.
