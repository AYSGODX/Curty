#!/usr/bin/swift
// Собирает Resources/AppIcon.icns из одного исходника — знака на прозрачном фоне.
//
// iconutil здесь не используется намеренно: на macOS 26 он отвергает
// сгенерированный набор с «Invalid Iconset» и рвёт установку. Файл пишется
// напрямую через ImageIO.
//
//   Scripts/generate-icon.swift Resources/Logo.png Resources/AppIcon.icns
//
// Третьим аргументом можно попросить лист предпросмотра: знак в реальных
// размерах и плитка так, как она выглядит в шторке.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fputs("usage: generate-icon.swift <logo.png> <AppIcon.icns> [preview.png]\n", stderr)
    exit(64)
}

let logoURL = URL(fileURLWithPath: arguments[1])
let iconURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(logoURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("error: не удалось прочитать \(logoURL.path)\n", stderr)
    exit(66)
}

// Сетка иконок macOS: холст 1024, сама плитка — 824 по центру, остальное поля.
// Без них иконка выглядит крупнее соседних в доке.
let plateInset: CGFloat = 100
/// Доля плитки, которую занимает знак. Подобрано на глаз по листу
/// предпросмотра: меньше — знак теряется, больше — упирается в углы.
let glyphScale: CGFloat = 0.62

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Скруглённый квадрат Apple — суперэллипс, а не прямоугольник с дугами:
/// у дуг заметно другой изгиб на большом размере.
func squirclePath(in rect: CGRect, exponent: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = Double(rect.width / 2), b = Double(rect.height / 2)
    let cx = Double(rect.midX), cy = Double(rect.midY)
    let steps = 720
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * Double.pi
        let cosT = cos(t), sinT = sin(t)
        let x = cx + copysign(pow(abs(cosT), 2 / exponent), cosT) * a
        let y = cy + copysign(pow(abs(sinT), 2 / exponent), sinT) * b
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func renderIcon(side: Int) -> CGImage {
    let size = CGFloat(side)
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    let scale = size / 1_024
    let plate = CGRect(x: plateInset * scale, y: plateInset * scale,
                       width: (1_024 - plateInset * 2) * scale,
                       height: (1_024 - plateInset * 2) * scale)
    let shape = squirclePath(in: plate)

    // Подложка почти белая с еле заметным переходом: знак тёмный, и на тёмном
    // доке без подложки он бы просто исчез.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        CGColor(srgbRed: 0.925, green: 0.925, blue: 0.945, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.maxY),
                           end: CGPoint(x: 0, y: plate.minY), options: [])
    ctx.restoreGState()

    // Волосяная кромка, иначе на белом фоне Finder иконка растворяется.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10))
    ctx.setLineWidth(max(1, size / 512))
    ctx.strokePath()
    ctx.restoreGState()

    let glyphSide = plate.width * glyphScale
    let ratio = CGFloat(logo.width) / CGFloat(logo.height)
    let glyphSize = ratio >= 1
        ? CGSize(width: glyphSide, height: glyphSide / ratio)
        : CGSize(width: glyphSide * ratio, height: glyphSide)
    ctx.draw(logo, in: CGRect(x: plate.midX - glyphSize.width / 2,
                              y: plate.midY - glyphSize.height / 2,
                              width: glyphSize.width, height: glyphSize.height))
    return ctx.makeImage()!
}

let variants = [16, 32, 32, 64, 128, 256, 256, 512, 512, 1_024]
guard let destination = CGImageDestinationCreateWithURL(
    iconURL as CFURL, UTType.icns.identifier as CFString, variants.count, nil
) else {
    fputs("error: не удалось создать \(iconURL.path)\n", stderr)
    exit(73)
}
for side in variants { CGImageDestinationAddImage(destination, renderIcon(side: side), nil) }
guard CGImageDestinationFinalize(destination) else {
    fputs("error: не удалось записать \(iconURL.path)\n", stderr)
    exit(73)
}
print("готово: \(iconURL.path)")

// --- Лист предпросмотра ------------------------------------------------------

guard arguments.count >= 4 else { exit(0) }

let sheetWidth = 760, sheetHeight = 420
let sheet = CGContext(data: nil, width: sheetWidth, height: sheetHeight, bitsPerComponent: 8,
                      bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.interpolationQuality = .high
sheet.setFillColor(CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))

// Слева — светлая половина: так видно, как иконка держится на белом.
sheet.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetWidth / 2, height: sheetHeight))

var x = 24
for side in [128, 64, 32, 16] {
    let image = renderIcon(side: side)
    sheet.draw(image, in: CGRect(x: x, y: 250, width: side, height: side))
    sheet.draw(image, in: CGRect(x: x + sheetWidth / 2, y: 250, width: side, height: side))
    x += side + 20
}

// Плитка шторки: 36×36 в рамке рельса, в трёхкратном увеличении.
let railScale = 3
let tile = renderIcon(side: 36 * railScale)
sheet.setFillColor(CGColor(srgbRed: 0.095, green: 0.095, blue: 0.11, alpha: 1))
sheet.fill(CGRect(x: 24, y: 30, width: 58 * railScale, height: 60 * railScale))
sheet.draw(tile, in: CGRect(x: 24 + 11 * railScale, y: 30 + 12 * railScale,
                            width: 36 * railScale, height: 36 * railScale))
if let preview = sheet.makeImage(),
   let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[3]) as CFURL,
                                             UTType.png.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(out, preview, nil)
    CGImageDestinationFinalize(out)
    print("предпросмотр: \(arguments[3])")
}
