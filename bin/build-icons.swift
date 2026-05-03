#!/usr/bin/env swift
// Renders Furwall's app icon — both Any-Appearance (ebony bg + ivory cat) and
// Dark-Appearance (ivory bg + ebony cat) variants — into:
//
//   Resources/Assets.xcassets/AppIcon.appiconset/  ← bundled into the .app,
//                                                    Any variant only.
//                                                    Drives Finder/Launchpad/
//                                                    Spotlight; static.
//   Resources/AppIcon-Dark.icns                    ← Dark variant, copied into
//                                                    the bundle and loaded at
//                                                    runtime when system
//                                                    appearance is dark
//                                                    (FurwallApp.swift swaps
//                                                    NSApp.applicationIconImage).
//   Resources/AppIcon.icns                         ← Any variant, on disk so
//                                                    Previews/*.swift can
//                                                    load it via
//                                                    NSImage(contentsOfFile:)
//                                                    (single-file render = no
//                                                    bundle context).
//
// We tried bundling dark variants inside AppIcon.appiconset via the
// `appearances` key — the JSON validates and matches working iOS patterns,
// but actool silently drops the dark renditions on macOS even at deployment
// target 15.0. Runtime swap is the working path on macOS.
//
// Hand-design override: drop 1024×1024 PNGs at Resources/icon-master.png
// (any) or Resources/icon-master-dark.png (dark) to override the
// programmatic renders.
//
// Usage: ./bin/build-icons.swift

import AppKit
import CoreGraphics
import Foundation

let canvas: CGFloat = 1024

enum Variant { case any, dark }

// Brand palette — mirrors the in-app furwallAccent color extension.
let ivory = NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.88, alpha: 1)
let ebony = NSColor(calibratedRed: 0.13, green: 0.11, blue: 0.09, alpha: 1)
// Slash inner stripe: warm red. The only color in an otherwise monochrome
// design — also matches the menu bar's "blocking" red.
let alarmRed = NSColor(calibratedRed: 0.85, green: 0.20, blue: 0.18, alpha: 1)

func renderMaster(_ variant: Variant) -> NSImage {
    let bg: NSColor = variant == .any ? ebony : ivory
    let fg: NSColor = variant == .any ? ivory : ebony
    let size = NSSize(width: canvas, height: canvas)
    let img = NSImage(size: size)
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus(); return img
    }

    // ── background squircle ──────────────────────────────────────────────────
    let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                              xRadius: 220, yRadius: 220)
    bgPath.addClip()
    bg.set()
    bgPath.fill()

    // ── cat.fill glyph centered ──────────────────────────────────────────────
    let cfg = NSImage.SymbolConfiguration(pointSize: 580, weight: .regular)
    if let cat = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: cat.size)
        tinted.lockFocus()
        fg.set()
        let imgRect = NSRect(origin: .zero, size: cat.size)
        cat.draw(in: imgRect)
        imgRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let cs = tinted.size
        let dest = NSRect(
            x: (canvas - cs.width) / 2,
            y: (canvas - cs.height) / 2 - 20,
            width: cs.width, height: cs.height
        )
        // Soft drop shadow — gives the cat dimensional weight on either bg.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        tinted.draw(in: dest)
    }

    // ── diagonal slash ───────────────────────────────────────────────────────
    NSGraphicsContext.saveGraphicsState()
    NSShadow().set()  // clear inherited shadow
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -30 * .pi / 180)
    // Outer carve: bg color — appears to cut THROUGH the cat, exposing the
    // squircle behind it. Reads as "no cats" without a separate slash element.
    let outer = NSBezierPath(roundedRect:
        NSRect(x: -490, y: -56, width: 980, height: 112),
        xRadius: 56, yRadius: 56)
    bg.set()
    outer.fill()
    // Inner stripe: warm red. The blocking/alert mark.
    let inner = NSBezierPath(roundedRect:
        NSRect(x: -480, y: -30, width: 960, height: 60),
        xRadius: 30, yRadius: 30)
    alarmRed.set()
    inner.fill()
    NSGraphicsContext.restoreGraphicsState()

    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, to url: URL, size: CGFloat) throws {
    // Allocate a pixel buffer at exactly `size × size` (not point-sized) so the
    // resulting PNG is pixel-exact regardless of the host display's scale.
    // NSImage + lockFocus honors screen scale (Retina = 2x), which produces
    // double-sized PNGs that actool then rejects.
    let pixelSize = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        throw NSError(domain: "build-icons", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize)),
        from: .zero, operation: .copy, fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "build-icons", code: 1)
    }
    try png.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")

// Hand-design overrides.
let anyMasterURL = resources.appendingPathComponent("icon-master.png")
let darkMasterURL = resources.appendingPathComponent("icon-master-dark.png")

let anyMaster: NSImage = {
    if FileManager.default.fileExists(atPath: anyMasterURL.path),
       let img = NSImage(contentsOf: anyMasterURL) {
        print("✓ using hand-designed any-master: Resources/icon-master.png")
        return img
    }
    print("✓ rendering programmatic any-master (ebony bg + ivory cat)")
    return renderMaster(.any)
}()

let darkMaster: NSImage = {
    if FileManager.default.fileExists(atPath: darkMasterURL.path),
       let img = NSImage(contentsOf: darkMasterURL) {
        print("✓ using hand-designed dark-master: Resources/icon-master-dark.png")
        return img
    }
    print("✓ rendering programmatic dark-master (ivory bg + ebony cat)")
    return renderMaster(.dark)
}()

let sizes: [(suffix: String, size: CGFloat)] = [
    ("16x16",       16),
    ("16x16@2x",    32),
    ("32x32",       32),
    ("32x32@2x",    64),
    ("128x128",    128),
    ("128x128@2x", 256),
    ("256x256",    256),
    ("256x256@2x", 512),
    ("512x512",    512),
    ("512x512@2x", 1024),
]

// Helper: write an .icns from a master image at the standard 10 sizes.
func writeICNS(master: NSImage, to icnsURL: URL, scratchName: String) throws {
    let scratch = resources.appendingPathComponent(scratchName)
    try? FileManager.default.removeItem(at: scratch)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    for (suffix, size) in sizes {
        try writePNG(master, to: scratch.appendingPathComponent("icon_\(suffix).png"), size: size)
    }
    let iconutil = Process()
    iconutil.launchPath = "/usr/bin/iconutil"
    iconutil.arguments = ["-c", "icns", "-o", icnsURL.path, scratch.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus != 0 { print("✗ iconutil failed for \(scratchName)"); exit(1) }
    try FileManager.default.removeItem(at: scratch)
}

// ── 1. Resources/AppIcon.icns (Any variant) — used by Previews/*.swift. ──────
let icnsAny = resources.appendingPathComponent("AppIcon.icns")
try writeICNS(master: anyMaster, to: icnsAny, scratchName: "AppIcon.iconset")
print("✓ wrote \(icnsAny.path)")

// ── 2. Resources/AppIcon-Dark.icns — bundled and loaded at runtime by
//      FurwallApp.swift when system appearance is dark.
let icnsDark = resources.appendingPathComponent("AppIcon-Dark.icns")
try writeICNS(master: darkMaster, to: icnsDark, scratchName: "AppIcon-Dark.iconset")
print("✓ wrote \(icnsDark.path)")

// ── 3. Resources/Assets.xcassets/AppIcon.appiconset (Any only). ─────────────
let xcassets = resources.appendingPathComponent("Assets.xcassets")
let iconset = xcassets.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.removeItem(at: xcassets)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let xcassetsContents: [String: Any] = [
    "info": ["author": "xcode", "version": 1]
]
try JSONSerialization.data(
    withJSONObject: xcassetsContents,
    options: [.prettyPrinted, .sortedKeys]
).write(to: xcassets.appendingPathComponent("Contents.json"))

for (suffix, size) in sizes {
    try writePNG(anyMaster,
                 to: iconset.appendingPathComponent("icon_\(suffix).png"), size: size)
}

var imageEntries: [[String: Any]] = []
for (suffix, _) in sizes {
    let parts = suffix.split(separator: "@")
    let dimSize = String(parts[0])
    let scale = parts.count > 1 ? "2x" : "1x"
    imageEntries.append([
        "filename": "icon_\(suffix).png",
        "idiom": "mac",
        "scale": scale,
        "size": dimSize
    ])
}

let appiconContents: [String: Any] = [
    "images": imageEntries,
    "info": ["author": "xcode", "version": 1]
]
try JSONSerialization.data(
    withJSONObject: appiconContents,
    options: [.prettyPrinted, .sortedKeys]
).write(to: iconset.appendingPathComponent("Contents.json"))

print("✓ wrote \(iconset.path) (\(imageEntries.count) Any entries)")
