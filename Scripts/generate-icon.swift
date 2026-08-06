#!/usr/bin/swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift /path/to/AppIcon.iconset\n", stderr)
    exit(64)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try? fileManager.removeItem(at: destination)
try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1_024, "icon_512x512@2x.png"),
]

func point(_ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> NSPoint {
    NSPoint(x: x * scale, y: y * scale)
}

func renderIcon(pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let scale = CGFloat(pixels) / 1_024
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let tileRect = NSRect(x: 72 * scale, y: 72 * scale, width: 880 * scale, height: 880 * scale)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 220 * scale, yRadius: 220 * scale)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.39, green: 0.26, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 0.93, green: 0.42, blue: 0.32, alpha: 1),
    ])!
    gradient.draw(in: tile, angle: -42)

    let notch = NSBezierPath(roundedRect: NSRect(
        x: 367 * scale,
        y: 820 * scale,
        width: 290 * scale,
        height: 116 * scale
    ), xRadius: 58 * scale, yRadius: 58 * scale)
    NSColor(calibratedWhite: 0.07, alpha: 0.88).setFill()
    notch.fill()

    let shield = NSBezierPath()
    shield.move(to: point(512, 730, scale: scale))
    shield.curve(to: point(740, 638, scale: scale),
                 controlPoint1: point(585, 707, scale: scale),
                 controlPoint2: point(668, 682, scale: scale))
    shield.line(to: point(724, 440, scale: scale))
    shield.curve(to: point(512, 256, scale: scale),
                 controlPoint1: point(712, 352, scale: scale),
                 controlPoint2: point(630, 286, scale: scale))
    shield.curve(to: point(300, 440, scale: scale),
                 controlPoint1: point(394, 286, scale: scale),
                 controlPoint2: point(312, 352, scale: scale))
    shield.line(to: point(284, 638, scale: scale))
    shield.curve(to: point(512, 730, scale: scale),
                 controlPoint1: point(356, 682, scale: scale),
                 controlPoint2: point(439, 707, scale: scale))
    shield.close()
    NSColor.white.withAlphaComponent(0.94).setFill()
    shield.fill()

    let keyhole = NSBezierPath(ovalIn: NSRect(x: 470 * scale, y: 480 * scale, width: 84 * scale, height: 84 * scale))
    NSColor(calibratedRed: 0.34, green: 0.25, blue: 0.64, alpha: 1).setFill()
    keyhole.fill()
    let stem = NSBezierPath(roundedRect: NSRect(x: 487 * scale, y: 410 * scale, width: 50 * scale, height: 98 * scale), xRadius: 25 * scale, yRadius: 25 * scale)
    stem.fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

for variant in variants {
    try renderIcon(pixels: variant.pixels, to: destination.appendingPathComponent(variant.name))
}

let manifest = #"""
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "Curty", "version" : 1 }
}
"""#
try Data(manifest.utf8).write(to: destination.appendingPathComponent("Contents.json"), options: .atomic)
