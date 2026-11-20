package main

import NS "core:sys/darwin/Foundation"
import AppKit "vendor:darwin/AppKit"

set_showcase_dock_icon :: proc() {
	NS.scoped_autoreleasepool()
	name := NS.String.stringWithUTF8String("AppIcon")
	ext := NS.String.stringWithUTF8String("icns")
	path := NS.Bundle.mainBundle()->pathForResource_ofType(name, ext)
	if path == nil {
		return
	}
	icon := AppKit.Image.alloc()->initWithContentsOfFile(path)
	if icon == nil {
		return
	}
	defer icon->release()
	// Use the artwork directly in the running app's Dock tile.
	AppKit.Application.sharedApplication()->setApplicationIconImage(icon)
}
