import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("Usage: swift tool/prepare_ios_app_icon.swift <input> <output>\n", stderr)
  exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceImage = NSImage(contentsOf: inputURL) else {
  fputs("Unable to read input image: \(inputURL.path)\n", stderr)
  exit(65)
}

var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
guard let sourceCG = sourceImage.cgImage(
  forProposedRect: &proposedRect,
  context: nil,
  hints: [.interpolation: NSImageInterpolation.high]
) else {
  fputs("Unable to decode input image\n", stderr)
  exit(65)
}

let pixels = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
  CGImageAlphaInfo.noneSkipLast.rawValue

guard let context = CGContext(
  data: nil,
  width: pixels,
  height: pixels,
  bitsPerComponent: 8,
  bytesPerRow: pixels * 4,
  space: colorSpace,
  bitmapInfo: bitmapInfo
) else {
  fputs("Unable to create CoreGraphics context\n", stderr)
  exit(70)
}

context.interpolationQuality = .high
context.setFillColor(NSColor.white.cgColor)
context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

let sourceWidth = CGFloat(sourceCG.width)
let sourceHeight = CGFloat(sourceCG.height)
guard sourceWidth > 0, sourceHeight > 0 else {
  fputs("Input image has invalid dimensions\n", stderr)
  exit(65)
}

let scale = min(CGFloat(pixels) / sourceWidth, CGFloat(pixels) / sourceHeight)
let targetWidth = sourceWidth * scale
let targetHeight = sourceHeight * scale
let targetRect = CGRect(
  x: (CGFloat(pixels) - targetWidth) / 2,
  y: (CGFloat(pixels) - targetHeight) / 2,
  width: targetWidth,
  height: targetHeight
)

context.draw(sourceCG, in: targetRect)

guard let outputCG = context.makeImage() else {
  fputs("Unable to render output image\n", stderr)
  exit(70)
}

let bitmap = NSBitmapImageRep(cgImage: outputCG)
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
