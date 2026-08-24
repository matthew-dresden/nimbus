#!/usr/bin/env python3
"""Generates Nimbus.app icon resources: a purple feather rendered from the
SF Symbols 'feather' glyph onto a rounded-rect tile, exported as PNGs for
every macOS icon size, then compiled into Resources/Nimbus.icns via iconutil.

Usage: python3 scripts/make_icon.py <output-dir>
Writes:  <output-dir>/Nimbus.iconset/*.png and <output-dir>/Nimbus.icns
"""

import os
import subprocess
import sys
import tempfile

out_dir = sys.argv[1] if len(sys.argv) > 1 else "Resources"
iconset = os.path.join(out_dir, "Nimbus.iconset")
os.makedirs(iconset, exist_ok=True)

SIZES = [16, 32, 64, 128, 256, 512, 1024]

script = r"""
import AppKit

let size = CGFloat(Int(CommandLine.arguments[1])!)
let outPath = CommandLine.arguments[2]

let purple = NSColor(calibratedRed: 0.48, green: 0.33, blue: 0.95, alpha: 1.0)
let lightPurple = NSColor(calibratedRed: 0.62, green: 0.47, blue: 1.0, alpha: 1.0)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded-square tile with vertical gradient, like a proper macOS icon
let tile = NSBezierPath(roundedRect: NSRect(x: size * 0.04, y: size * 0.04,
                                            width: size * 0.92, height: size * 0.92),
                        xRadius: size * 0.185, yRadius: size * 0.185)
NSColor.white.setFill()
tile.fill()

if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.saveGState()
    tile.addClip()
    let colors = [purple.cgColor, lightPurple.cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()
}

// White feather glyph, centered
let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
if var feather = NSImage(systemSymbolName: "feather", accessibilityDescription: "Nimbus")?
    .withSymbolConfiguration(config) {
    feather.isTemplate = true
    if let tinted = feather.copy() as? NSImage {
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let w = size * 0.52
        let h = w * (tinted.size.height / tinted.size.width)
        tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2 - size * 0.01,
                               width: w, height: h))
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
"""

with tempfile.NamedTemporaryFile(suffix=".swift", mode="w", delete=False) as f:
    f.write(script)
    script_path = f.name

for s in SIZES:
    png = os.path.join(iconset, f"icon_{s}x{s}.png")
    subprocess.run(["swift", script_path, str(s), png], check=True)
    if s <= 512:
        subprocess.run(
            ["cp", png, os.path.join(iconset, f"icon_{s * 2}x{s * 2}@2x.png")],
            check=True,
        )

subprocess.run(
    ["iconutil", "-c", "icns", iconset, "-o", os.path.join(out_dir, "Nimbus.icns")],
    check=True,
)
print(f"icon written: {os.path.join(out_dir, 'Nimbus.icns')}")
