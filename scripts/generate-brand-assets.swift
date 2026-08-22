#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let sourceURL = root.appendingPathComponent("public/logo-jolene-carre.png")

guard let source = NSImage(contentsOf: sourceURL) else {
  fputs("Impossible de lire \(sourceURL.path)\n", stderr)
  exit(1)
}

func url(_ relativePath: String) -> URL {
  root.appendingPathComponent(relativePath)
}

func pngRepresentation(
  width: Int,
  height: Int,
  opaque: Bool,
  draw: (NSRect) -> Void
) throws -> Data {
  // AppKit ne fournit pas de contexte de dessin fiable pour un bitmap RGB
  // 24 bits. Les sorties dessinées restent entièrement opaques lorsque
  // `opaque` vaut true ; l'AppIcon Apple est, lui, une copie RGB exacte.
  let samplesPerPixel = 4
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: samplesPerPixel,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: width * samplesPerPixel,
    bitsPerPixel: samplesPerPixel * 8
  ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw NSError(domain: "JoleneBrandAssets", code: 1)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  draw(NSRect(x: 0, y: 0, width: width, height: height))
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "JoleneBrandAssets", code: 2)
  }
  return data
}

func write(_ data: Data, to relativePath: String) throws {
  let destination = url(relativePath)
  try fileManager.createDirectory(
    at: destination.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try data.write(to: destination, options: .atomic)
  print("✓ \(relativePath)")
}

func copyCanonical(to relativePath: String) throws {
  try write(Data(contentsOf: sourceURL), to: relativePath)
}

func drawSource(in rect: NSRect) {
  source.draw(
    in: rect,
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
  )
}

func resizedCanonical(width: Int, height: Int, opaque: Bool = true) throws -> Data {
  try pngRepresentation(width: width, height: height, opaque: opaque) { canvas in
    drawSource(in: canvas)
  }
}

func aspectFillCanonical(width: Int, height: Int) throws -> Data {
  try pngRepresentation(width: width, height: height, opaque: true) { canvas in
    let scale = max(canvas.width / source.size.width, canvas.height / source.size.height)
    let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
    let drawRect = NSRect(
      x: (canvas.width - drawSize.width) / 2,
      y: (canvas.height - drawSize.height) / 2,
      width: drawSize.width,
      height: drawSize.height
    )
    drawSource(in: drawRect)
  }
}

func splash(width: Int, height: Int, dark: Bool) throws -> Data {
  try pngRepresentation(width: width, height: height, opaque: true) { canvas in
    (dark
      ? NSColor(calibratedRed: 0.102, green: 0.063, blue: 0.141, alpha: 1)
      : NSColor.white
    ).setFill()
    canvas.fill()

    // Discret sur un écran de lancement très haut, plutôt qu'une grande carte.
    let iconSize = floor(min(canvas.width, canvas.height) * 0.22)
    let iconRect = NSRect(
      x: floor((canvas.width - iconSize) / 2),
      y: floor((canvas.height - iconSize) / 2),
      width: iconSize,
      height: iconSize
    )
    drawSource(in: iconRect)
  }
}

func roundLegacyIcon(size: Int) throws -> Data {
  try pngRepresentation(width: size, height: size, opaque: false) { canvas in
    NSColor.clear.setFill()
    canvas.fill()
    NSBezierPath(ovalIn: canvas).addClip()
    drawSource(in: canvas)
  }
}

func rasterizedCanonicalRGBA() throws -> NSBitmapImageRep {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 1024 * 4,
    bitsPerPixel: 32
  ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw NSError(domain: "JoleneBrandAssets", code: 3)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  drawSource(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  return bitmap
}

func extractedWhiteArtwork() throws -> (image: NSImage, bounds: NSRect) {
  let input = try rasterizedCanonicalRGBA()
  guard let output = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: input.pixelsWide,
    pixelsHigh: input.pixelsHigh,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: input.pixelsWide * 4,
    bitsPerPixel: 32
  ) else {
    throw NSError(domain: "JoleneBrandAssets", code: 4)
  }

  var minX = input.pixelsWide
  var minY = input.pixelsHigh
  var maxX = 0
  var maxY = 0

  guard let inputBytes = input.bitmapData, let outputBytes = output.bitmapData else {
    throw NSError(domain: "JoleneBrandAssets", code: 5)
  }

  for y in 0..<input.pixelsHigh {
    for x in 0..<input.pixelsWide {
      let inputOffset = y * input.bytesPerRow + x * 4
      let outputOffset = y * output.bytesPerRow + x * 4
      let red = CGFloat(inputBytes[inputOffset]) / 255
      let green = CGFloat(inputBytes[inputOffset + 1]) / 255
      let blue = CGFloat(inputBytes[inputOffset + 2]) / 255
      let minimum = min(red, green, blue)
      let spread = max(red, green, blue) - minimum
      let whiteness = max(0, min(1, (minimum - 0.72) / 0.25))
      let neutrality = max(0, min(1, (0.18 - spread) / 0.16))
      let alpha = whiteness * neutrality

      if alpha > 0.01 {
        outputBytes[outputOffset] = 255
        outputBytes[outputOffset + 1] = 255
        outputBytes[outputOffset + 2] = 255
        outputBytes[outputOffset + 3] = UInt8(round(alpha * 255))
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      } else {
        outputBytes[outputOffset] = 0
        outputBytes[outputOffset + 1] = 0
        outputBytes[outputOffset + 2] = 0
        outputBytes[outputOffset + 3] = 0
      }
    }
  }

  guard minX <= maxX, minY <= maxY else {
    throw NSError(domain: "JoleneBrandAssets", code: 6)
  }

  let image = NSImage(size: NSSize(width: output.pixelsWide, height: output.pixelsHigh))
  image.addRepresentation(output)
  let bounds = NSRect(
    x: minX,
    // Les lignes du buffer sont indexées depuis le haut, alors que NSImage
    // dessine depuis le bas.
    y: input.pixelsHigh - maxY - 1,
    width: maxX - minX + 1,
    height: maxY - minY + 1
  )
  return (image, bounds)
}

let artwork = try extractedWhiteArtwork()

func adaptiveBackground(size: Int) throws -> Data {
  try pngRepresentation(width: size, height: size, opaque: true) { canvas in
    let gradient = NSGradient(
      colorsAndLocations:
        (NSColor(calibratedRed: 0.882, green: 0.259, blue: 0.522, alpha: 1), 0),
        (NSColor(calibratedRed: 0.545, green: 0.153, blue: 0.494, alpha: 1), 1)
    )
    gradient?.draw(
      from: NSPoint(x: canvas.minX, y: canvas.maxY),
      to: NSPoint(x: canvas.maxX, y: canvas.minY),
      options: []
    )
  }
}

func adaptiveForeground(size: Int) throws -> Data {
  try pngRepresentation(width: size, height: size, opaque: false) { canvas in
    NSColor.clear.setFill()
    canvas.fill()

    let targetWidth = floor(canvas.width * 0.62)
    let targetHeight = targetWidth * artwork.bounds.height / artwork.bounds.width
    let target = NSRect(
      x: floor((canvas.width - targetWidth) / 2),
      y: floor((canvas.height - targetHeight) / 2),
      width: targetWidth,
      height: targetHeight
    )
    artwork.image.draw(
      in: target,
      from: artwork.bounds,
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: false,
      hints: [.interpolation: NSImageInterpolation.high]
    )
  }
}

// Une seule source canonique pour les icônes principales.
for destination in [
  "resources/icon.png",
  "public/app-icon-1024.png",
  "src/assets/icon-jolene.png",
  "ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png",
] {
  try copyCanonical(to: destination)
}

// Web, PWA, Apple Touch et images sociales.
try write(resizedCanonical(width: 96, height: 96), to: "public/favicon-96.png")
try write(resizedCanonical(width: 192, height: 192), to: "public/icon-192x192.png")
try write(resizedCanonical(width: 512, height: 512), to: "public/icon-512x512.png")
try write(aspectFillCanonical(width: 1200, height: 628), to: "public/logo-jolene-bandeau.png")
try write(aspectFillCanonical(width: 1200, height: 630), to: "public/og-default.png")

// Splash source et copies iOS.
let lightSplash = try splash(width: 2732, height: 2732, dark: false)
let darkSplash = try splash(width: 2732, height: 2732, dark: true)
try write(lightSplash, to: "resources/splash.png")
try write(darkSplash, to: "resources/splash-dark.png")

for scale in ["1x", "2x", "3x"] {
  try write(
    lightSplash,
    to: "ios/App/App/Assets.xcassets/Splash.imageset/Default@\(scale)~universal~anyany.png"
  )
  try write(
    darkSplash,
    to: "ios/App/App/Assets.xcassets/Splash.imageset/Default@\(scale)~universal~anyany-dark.png"
  )
}

// Icônes Android héritées et adaptatives.
let androidDensities: [(name: String, legacy: Int, adaptive: Int)] = [
  ("ldpi", 36, 81),
  ("mdpi", 48, 108),
  ("hdpi", 72, 162),
  ("xhdpi", 96, 216),
  ("xxhdpi", 144, 324),
  ("xxxhdpi", 192, 432),
]

for density in androidDensities {
  let directory = "android/app/src/main/res/mipmap-\(density.name)"
  try write(
    resizedCanonical(width: density.legacy, height: density.legacy),
    to: "\(directory)/ic_launcher.png"
  )
  try write(roundLegacyIcon(size: density.legacy), to: "\(directory)/ic_launcher_round.png")
  try write(
    adaptiveBackground(size: density.adaptive),
    to: "\(directory)/ic_launcher_background.png"
  )
  try write(
    adaptiveForeground(size: density.adaptive),
    to: "\(directory)/ic_launcher_foreground.png"
  )
}

// Les dimensions déjà versionnées correspondent aux densités Android attendues.
let androidResURL = url("android/app/src/main/res")
if let enumerator = fileManager.enumerator(
  at: androidResURL,
  includingPropertiesForKeys: nil
) {
  for case let splashURL as URL in enumerator where splashURL.lastPathComponent == "splash.png" {
    let relativePath = splashURL.path.replacingOccurrences(of: root.path + "/", with: "")
    guard relativePath.hasPrefix("android/app/src/main/res/"),
          let currentData = try? Data(contentsOf: splashURL),
          let current = NSBitmapImageRep(data: currentData) else { continue }
    let dark = splashURL.deletingLastPathComponent().lastPathComponent.contains("night")
    try write(
      splash(width: current.pixelsWide, height: current.pixelsHigh, dark: dark),
      to: relativePath
    )
  }
}

// ICO de repli pour les navigateurs historiques.
let faviconData = try Data(contentsOf: url("public/favicon-96.png"))
func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
  var littleEndian = value.littleEndian
  withUnsafeBytes(of: &littleEndian) { bytes in
    data.append(contentsOf: bytes)
  }
}

// Un fichier ICO peut encapsuler directement une image PNG.
var ico = Data()
appendLittleEndian(UInt16(0), to: &ico) // réservé
appendLittleEndian(UInt16(1), to: &ico) // type icône
appendLittleEndian(UInt16(1), to: &ico) // une image
ico.append(UInt8(96))
ico.append(UInt8(96))
ico.append(UInt8(0)) // palette
ico.append(UInt8(0)) // réservé
appendLittleEndian(UInt16(1), to: &ico) // plans
appendLittleEndian(UInt16(32), to: &ico) // profondeur
appendLittleEndian(UInt32(faviconData.count), to: &ico)
appendLittleEndian(UInt32(22), to: &ico) // en-tête 6 + entrée 16
ico.append(faviconData)
try write(ico, to: "public/favicon.ico")
