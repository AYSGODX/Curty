#!/usr/bin/swift
// Собирает знак Curty во всех видах, в которых он встречается.
//
//   Scripts/generate-icon.swift Resources [preview.png]
//
// Пишет в указанный каталог:
//   AppIcon.icns    — иконка приложения, все размеры от 16 до 1024;
//   LogoSmall.png   — то же лицо в 128 точках, для плитки в рельсе шторки;
//   MenuBarIcon.png — шаблон для строки меню: один силуэт знака, без плиты.
//
// Знак рисуется кодом, а не берётся из картинки. Раньше исходником был
// Resources/Logo.png, и всё остальное вырезалось из него по цвету — приём,
// который держался ровно до тех пор, пока лицо было белой буквой на оранжевом.
// У графитовой плиты с янтарным знаком отбирать по яркости нечего: плита и знак
// в тёмных каналах почти совпадают. Рисуя фигуру, мы точно знаем, где она.
//
// iconutil здесь не используется намеренно: на macOS 26 он отвергает
// сгенерированный набор с «Invalid Iconset» и рвёт установку. Файл пишется
// напрямую через ImageIO.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: generate-icon.swift <resources-dir> [preview.png]\n", stderr)
    exit(64)
}

let resourcesURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// Сетка иконок macOS: холст 1024, сама плитка — 824 по центру, остальное поля.
// Без них иконка выглядит крупнее соседних в доке.
let plateInset: CGFloat = 100

let amber = CGColor(srgbRed: 0.941, green: 0.659, blue: 0.118, alpha: 1)

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

/// «C» собрана как деталь, а не набрана шрифтом: кольцо с радиальным вырезом,
/// торцы плоские и смотрят в центр. Так она остаётся собой в шестнадцати
/// пикселях, где у любой гарнитуры уже теряются засечки и модуляция штриха.
func markPath(center: CGPoint, outer: CGFloat, thicknessRatio: CGFloat = 0.44, gapDegrees: CGFloat = 74) -> CGPath {
    let path = CGMutablePath()
    let inner = outer * (1 - thicknessRatio)
    let half = gapDegrees / 2 * .pi / 180
    path.addArc(center: center, radius: outer, startAngle: half, endAngle: 2 * .pi - half, clockwise: false)
    path.addArc(center: center, radius: inner, startAngle: 2 * .pi - half, endAngle: half, clockwise: true)
    path.closeSubpath()
    return path
}

/// Графитовая плита: тёмный низ, светлее верх, мягкий продольный отлив и фаска —
/// светлая сверху, тёмная снизу. Тот же материал, что у самой панели.
func drawPlate(_ ctx: CGContext, in rect: CGRect) {
    let shape = squirclePath(in: rect)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let base = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 0.255, green: 0.259, blue: 0.267, alpha: 1),
        CGColor(srgbRed: 0.145, green: 0.149, blue: 0.157, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: rect.maxY),
                           end: CGPoint(x: 0, y: rect.minY), options: [])

    // Отлив шлифовки: широкие мягкие ленты, без единой линии. Линии на
    // маленьких размерах превращаются в рябь.
    let sheen = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.00),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.04),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.04),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.00),
    ] as CFArray, locations: [0, 0.18, 0.38, 0.6, 0.82, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.minX, y: 0),
                           end: CGPoint(x: rect.maxX, y: 0), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setLineWidth(max(1, rect.width / 90))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let edge = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.32),
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(edge, start: CGPoint(x: 0, y: rect.maxY),
                           end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// Знак выгравирован в плите и залит светом: под фигурой тёмный провал, снизу
/// светлая кромка канавки, внутри — янтарь с ореолом.
func drawMark(_ ctx: CGContext, in rect: CGRect) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let path = markPath(center: center, outer: rect.width * 0.30)
    let relief = rect.width * 0.010

    ctx.saveGState()
    ctx.translateBy(x: 0, y: -relief)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: rect.width * 0.045, color: amber.copy(alpha: 0.85))
    ctx.addPath(path)
    ctx.setFillColor(amber)
    ctx.fillPath()
    ctx.restoreGState()
}

func renderFace(side: Int) -> CGImage {
    let size = CGFloat(side)
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    let scale = size / 1_024
    let plate = CGRect(x: plateInset * scale, y: plateInset * scale,
                       width: (1_024 - plateInset * 2) * scale,
                       height: (1_024 - plateInset * 2) * scale)
    drawPlate(ctx, in: plate)
    drawMark(ctx, in: plate)
    return ctx.makeImage()!
}

/// Шаблон для строки меню: один силуэт знака в прозрачности, без плиты.
/// Система сама красит его под светлую и тёмную панель и инвертирует при
/// нажатии; цветной значок этого не умеет и выглядит чужим среди соседей.
func renderMenuBarTemplate(side: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let size = CGFloat(side)
    // В строке меню знак живёт один, без плиты вокруг, поэтому занимает почти
    // всё поле: те же пропорции, что на плите, здесь выглядели бы точкой.
    let path = markPath(center: CGPoint(x: size / 2, y: size / 2), outer: size * 0.42)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    guard let out = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(out, image, nil)
    CGImageDestinationFinalize(out)
    print("готово: \(url.path)")
}

// --- Иконка приложения -------------------------------------------------------

let iconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
let variants = [16, 32, 32, 64, 128, 256, 256, 512, 512, 1_024]
guard let destination = CGImageDestinationCreateWithURL(
    iconURL as CFURL, UTType.icns.identifier as CFString, variants.count, nil
) else {
    fputs("error: не удалось создать \(iconURL.path)\n", stderr)
    exit(73)
}
for side in variants { CGImageDestinationAddImage(destination, renderFace(side: side), nil) }
guard CGImageDestinationFinalize(destination) else {
    fputs("error: не удалось записать \(iconURL.path)\n", stderr)
    exit(73)
}
print("готово: \(iconURL.path)")

// --- Плитка в шторке и значок строки меню ------------------------------------

// Плитка рисуется размером в тридцать с небольшим пунктов. Ужимать в них
// растр на тысячу пикселей — верный способ получить рваный край, поэтому рядом
// кладётся заранее уменьшенная копия с честным пересчётом.
write(renderFace(side: 128), to: resourcesURL.appendingPathComponent("LogoSmall.png"))
// 18 пунктов на экране с двойной плотностью.
let menuBar = renderMenuBarTemplate(side: 36)
write(menuBar, to: resourcesURL.appendingPathComponent("MenuBarIcon.png"))

// --- Лист предпросмотра ------------------------------------------------------

guard arguments.count >= 3 else { exit(0) }

let sheetWidth = 760, sheetHeight = 300
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
    let image = renderFace(side: side)
    sheet.draw(image, in: CGRect(x: x, y: 140, width: side, height: side))
    sheet.draw(image, in: CGRect(x: x + sheetWidth / 2, y: 140, width: side, height: side))
    x += side + 20
}

// Значок строки меню в обеих панелях, в трёхкратном увеличении.
for (index, background) in [(0.96, 0.96, 0.97), (0.16, 0.16, 0.17)].enumerated() {
    let originX = 24 + index * sheetWidth / 2
    sheet.setFillColor(CGColor(srgbRed: background.0, green: background.1, blue: background.2, alpha: 1))
    sheet.fill(CGRect(x: originX, y: 30, width: 120, height: 80))
    sheet.saveGState()
    sheet.clip(to: CGRect(x: originX + 30, y: 50, width: 54, height: 54), mask: menuBar)
    sheet.setFillColor(index == 0
        ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
        : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
    sheet.fill(CGRect(x: originX + 30, y: 50, width: 54, height: 54))
    sheet.restoreGState()
}

if let preview = sheet.makeImage(),
   let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL,
                                             UTType.png.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(out, preview, nil)
    CGImageDestinationFinalize(out)
    print("предпросмотр: \(arguments[2])")
}
