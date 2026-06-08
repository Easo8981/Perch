#!/usr/bin/env swift
//
// Renders Perch's app icon (a gradient squircle with a white tray glyph) and assembles
// Resources/AppIcon.icns. Run from the repo root: `swift Scripts/make-icon.swift`.
//
import AppKit
import Foundation

let topColor = NSColor(srgbRed: 0.33, green: 0.57, blue: 1.00, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.20, green: 0.36, blue: 0.86, alpha: 1)

func renderPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle background with a vertical gradient (a little margin, macOS-style).
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)
    NSGradient(colors: [topColor, bottomColor])!.draw(in: path, angle: -90)

    // Centered white tray glyph.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let gs = glyph.size
        let origin = NSPoint(x: (s - gs.width) / 2, y: (s - gs.height) / 2)
        glyph.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iconset entries: (filename, pixel size).
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let fm = FileManager.default
let iconset = "Perch.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (name, size) in entries {
    try! renderPNG(size: size).write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}

try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()

try? fm.removeItem(atPath: iconset)
print(iconutil.terminationStatus == 0 ? "✓ Wrote Resources/AppIcon.icns" : "✗ iconutil failed")
