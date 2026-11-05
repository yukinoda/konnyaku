// Renders an SVG to a 1024 x 1024 transparent PNG with AppKit.
// Usage: swift scripts/render-svg.swift input.svg output.png

import AppKit

let arguments = CommandLine.arguments
let svgURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let size = 1024

guard let image = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write("error: cannot load \(svgURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

try bitmap.representation(using: .png, properties: [:])!.write(to: outputURL)
