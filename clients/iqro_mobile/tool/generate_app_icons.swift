#!/usr/bin/env swift

import AppKit
import Foundation

// This is an exact raster port of Android's authoritative
// drawable/ic_launcher_foreground.xml geometry and color tokens.

private let canvasSize: CGFloat = 108
private let background = NSColor(
  calibratedRed: 7 / 255,
  green: 62 / 255,
  blue: 52 / 255,
  alpha: 1
)
private let gold = NSColor(
  calibratedRed: 207 / 255,
  green: 168 / 255,
  blue: 94 / 255,
  alpha: 1
)
private let paper = NSColor(
  calibratedRed: 255 / 255,
  green: 253 / 255,
  blue: 248 / 255,
  alpha: 1
)

private struct IconTarget {
  let path: String
  let pixels: Int
  let includesBackground: Bool
}

private enum IconGenerationError: Error {
  case bitmapContextCreation
  case imageCreation
  case pngEncoding
}

private let targets = [
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png", pixels: 20, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png", pixels: 40, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png", pixels: 60, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png", pixels: 29, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png", pixels: 58, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png", pixels: 87, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png", pixels: 40, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png", pixels: 80, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png", pixels: 120, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png", pixels: 120, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png", pixels: 180, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png", pixels: 76, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png", pixels: 152, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png", pixels: 167, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", pixels: 1024, includesBackground: true),
  IconTarget(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png", pixels: 108, includesBackground: false),
  IconTarget(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png", pixels: 216, includesBackground: false),
  IconTarget(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png", pixels: 324, includesBackground: false),
  IconTarget(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", pixels: 48, includesBackground: true),
  IconTarget(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", pixels: 72, includesBackground: true),
  IconTarget(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", pixels: 96, includesBackground: true),
  IconTarget(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", pixels: 144, includesBackground: true),
  IconTarget(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", pixels: 192, includesBackground: true),
]

private func render(_ target: IconTarget, root: URL) throws {
  var pixels = [UInt8](
    repeating: 0,
    count: target.pixels * target.pixels * 4
  )
  let png = try pixels.withUnsafeMutableBytes { storage -> Data in
    let alpha = target.includesBackground
      ? CGImageAlphaInfo.noneSkipLast
      : CGImageAlphaInfo.premultipliedLast
    guard let context = CGContext(
      data: storage.baseAddress,
      width: target.pixels,
      height: target.pixels,
      bitsPerComponent: 8,
      bytesPerRow: target.pixels * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: alpha.rawValue
    ) else {
      throw IconGenerationError.bitmapContextCreation
    }

    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphics
    graphics.shouldAntialias = true
    graphics.imageInterpolation = .high

    let scale = CGFloat(target.pixels) / canvasSize
    context.scaleBy(x: scale, y: scale)
    if target.includesBackground {
      background.setFill()
      NSBezierPath(
        rect: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
      ).fill()
    } else {
      context.clear(
        CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
      )
    }

  let headphones = NSBezierPath()
  headphones.move(to: NSPoint(x: 29, y: 41))
  headphones.line(to: NSPoint(x: 29, y: 64))
  headphones.curve(
    to: NSPoint(x: 54, y: 88),
    controlPoint1: NSPoint(x: 29, y: 79),
    controlPoint2: NSPoint(x: 39, y: 88)
  )
  headphones.curve(
    to: NSPoint(x: 79, y: 64),
    controlPoint1: NSPoint(x: 69, y: 88),
    controlPoint2: NSPoint(x: 79, y: 79)
  )
  headphones.line(to: NSPoint(x: 79, y: 41))
  headphones.lineWidth = 5
  headphones.lineCapStyle = .round
  headphones.lineJoinStyle = .round
  gold.setStroke()
  headphones.stroke()

  let book = NSBezierPath()
  book.move(to: NSPoint(x: 20, y: 46))
  book.curve(
    to: NSPoint(x: 54, y: 36),
    controlPoint1: NSPoint(x: 32, y: 49),
    controlPoint2: NSPoint(x: 44, y: 45)
  )
  book.curve(
    to: NSPoint(x: 88, y: 46),
    controlPoint1: NSPoint(x: 64, y: 45),
    controlPoint2: NSPoint(x: 76, y: 49)
  )
  book.line(to: NSPoint(x: 84, y: 21))
  book.curve(
    to: NSPoint(x: 54, y: 17),
    controlPoint1: NSPoint(x: 73, y: 25),
    controlPoint2: NSPoint(x: 63, y: 24)
  )
  book.curve(
    to: NSPoint(x: 24, y: 21),
    controlPoint1: NSPoint(x: 45, y: 24),
    controlPoint2: NSPoint(x: 35, y: 25)
  )
  book.close()
  paper.setFill()
  book.fill()

  let centerLine = NSBezierPath()
  centerLine.move(to: NSPoint(x: 54, y: 36))
  centerLine.line(to: NSPoint(x: 54, y: 17))
  centerLine.lineWidth = 2.5
  centerLine.lineCapStyle = .round
  gold.setStroke()
  centerLine.stroke()

    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let image = context.makeImage() else {
      throw IconGenerationError.imageCreation
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw IconGenerationError.pngEncoding
    }
    return data
  }
  let output = root.appendingPathComponent(target.path)
  do {
    try png.write(to: output)
  } catch {
    let cocoa = error as NSError
    fputs(
      "Write failed for \(output.path), \(png.count) bytes, details: \(cocoa.userInfo)\n",
      stderr
    )
    throw error
  }
}

let root = URL(
  fileURLWithPath: FileManager.default.currentDirectoryPath,
  isDirectory: true
)
for target in targets {
  do {
    try render(target, root: root)
    print("Generated \(target.path)")
  } catch {
    fputs("Failed to generate \(target.path): \(error)\n", stderr)
    exit(1)
  }
}
