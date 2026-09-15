import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("Usage: swift tool/prepare_ios_app_icon.swift <input> <output>\n", stderr)
  exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let image = NSImage(contentsOf: inputURL) else {
  fputs("Unable to read input image: \(inputURL.path)\n", stderr)
  exit(65)
}

let pixels = 1024
guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: pixels,
  pixelsHigh: pixels,
  bitsPerSample: 8,
  samplesPerPixel: 3,
  hasAlpha: false,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 24
) else {
  fputs("Unable to allocate output bitmap\n", stderr)
  exit(70)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("Unable to create graphics context\n", stderr)
  exit(70)
}
NSGraphicsContext.current = context
context.imageInterpolation = .high

NSColor.white.setFill()
NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

let sourceSize = image.size
guard sourceSize.width > 0, sourceSize.height > 0 else {
  fputs("Input image has invalid dimensions\n", stderr)
  exit(65)
}

let scale = min(
  CGFloat(pixels) / sourceSize.width,
  CGFloat(pixels) / sourceSize.height
)
let targetSize = NSSize(
  width: sourceSize.width * scale,
  height: sourceSize.height * scale
)
let targetRect = NSRect(
  x: (CGFloat(pixels) - targetSize.width) / 2,
  y: (CGFloat(pixels) - targetSize.height) / 2,
  width: targetSize.width,
  height: targetSize.height
)

image.draw(
  in: targetRect,
  from: .zero,
  operation: .sourceOver,
  fraction: 1.0,
  respectFlipped: true,
  hints: [.interpolation: NSImageInterpolation.high]
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Unable to encode PNG\n", stderr)
  exit(70)
}

do {
  try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try png.write(to: outputURL, options: .atomic)
} catch {
  fputs("Unable to write output image: \(error)\n", stderr)
  exit(74)
}
