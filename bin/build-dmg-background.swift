#!/usr/bin/env swift
// Renders the DMG background: a single arrow.right SF Symbol sitting between
// where Furwall.app and the Applications drop-target land in the create-dmg
// layout. The arrow is the only visual hint — keeps the window calm.
//
// Output dimensions match the create-dmg --window-size arg (540x360).
//
// The symbol PNG itself comes from `sfsym` (Homebrew), which emits a clean
// transparent-background bitmap so we don't need any in-Swift tinting/compositing
// tricks that risk leaving an opaque bounding box behind the glyph.
//
// Usage:  swift bin/build-dmg-background.swift <arrow.png> <output.png>

import AppKit

guard CommandLine.arguments.count == 3 else {
    print("usage: build-dmg-background.swift <arrow.png> <output.png>")
    exit(1)
}
let arrowPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

let canvas = NSSize(width: 540, height: 360)
// Icons in create-dmg sit at top-down (140, 130) and (400, 130). Arrow
// belongs at the midpoint, same Y. Cocoa drawing is bottom-up, so flip Y.
let arrowCenter = NSPoint(x: 270, y: canvas.height - 130)
let arrowDrawSize: CGFloat = 56  // matches the sfsym --size we exported at

guard let arrow = NSImage(contentsOfFile: arrowPath) else {
    print("could not load arrow image at \(arrowPath)")
    exit(1)
}

let image = NSImage(size: canvas)
image.lockFocus()

// White background — matches Finder's default DMG window chrome so the
// transition from chrome to canvas isn't visible.
NSColor.white.setFill()
NSRect(origin: .zero, size: canvas).fill()

// Draw the (already-tinted, already-transparent-background) arrow PNG
// directly. No compositing tricks — sfsym handed us pixels we can just
// blit on top.
let drawRect = NSRect(
    x: arrowCenter.x - arrowDrawSize / 2,
    y: arrowCenter.y - arrowDrawSize / 2,
    width: arrowDrawSize,
    height: arrowDrawSize
)
arrow.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("failed to encode PNG")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(canvas.width))x\(Int(canvas.height)))")
