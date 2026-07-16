import AppKit
import CoreGraphics
import Foundation

// Renders the app icon: three sheets of frosted glass stacked over a blurred
// wash. The overlay's real material is vibrancy over your content, so the icon
// is that — panels of glass, the front one holding a clip, the ones behind it
// receding into history. Drawn in a 1024 design space and rendered natively at
// every size rather than downscaled, so small sizes stay crisp.
//
//   swift Tools/make-icon.swift

let designSize: CGFloat = 1024
let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

// MARK: - Palette

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let baseTop = srgb(0x4C1D95)      // indigo — the deep end of the wash
let baseBottom = srgb(0x1E1B4B)   // near-navy
let washViolet = srgb(0x8B5CF6)   // the blurred bloom, top-left
let washCoral = srgb(0xFF6B8A)    // the warm counterweight, bottom-right
let inkLine = srgb(0x3B2A7A, 0.5) // the clip's text, seen through glass

// MARK: - Shape

/// Apple's icon silhouette is a superellipse, not a rounded rect — circular
/// corners read subtly wrong next to real macOS icons.
func superellipse(in rect: CGRect, exponent n: CGFloat = 5, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY

    for i in 0...samples {
        let t = (CGFloat(i) / CGFloat(samples)) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = cx + a * (cosT < 0 ? -1 : 1) * pow(abs(cosT), 2 / n)
        let y = cy + b * (sinT < 0 ? -1 : 1) * pow(abs(sinT), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func roundedCard(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func bloom(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor, alpha: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let comps = color.components!
    let solid = CGColor(colorSpace: space, components: [comps[0], comps[1], comps[2], alpha])!
    let clear = CGColor(colorSpace: space, components: [comps[0], comps[1], comps[2], 0])!
    guard let gradient = CGGradient(
        colorsSpace: space,
        colors: [solid, clear] as CFArray,
        locations: [0, 1]
    ) else { return }

    ctx.drawRadialGradient(
        gradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: []
    )
}

// MARK: - Drawing

func drawIcon(in ctx: CGContext, pixelSize: CGFloat) {
    ctx.scaleBy(x: pixelSize / designSize, y: pixelSize / designSize)

    // Standard macOS icon geometry: the shape sits inset in the canvas so it
    // optically matches the size of every other app icon in Finder.
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = superellipse(in: iconRect)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Wash: a blurred desktop seen through the panel.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if let base = CGGradient(colorsSpace: space, colors: [baseTop, baseBottom] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(
            base,
            start: CGPoint(x: 0, y: 924),
            end: CGPoint(x: 0, y: 100),
            options: []
        )
    }
    bloom(ctx, center: CGPoint(x: 230, y: 810), radius: 540, color: washViolet, alpha: 0.95)
    bloom(ctx, center: CGPoint(x: 830, y: 190), radius: 540, color: washCoral, alpha: 0.85)

    // The stack: three sheets offset on the diagonal. Two overlapping rectangles
    // is the universal copy glyph — a third turns copy into copy *history*, and
    // the diagonal keeps each sheet's edge legible where a concentric stack
    // would collapse into one blob.
    let cardSize: CGFloat = 420
    let step: CGFloat = 48
    let origin = CGPoint(x: 262, y: 262)

    for depth in [2, 1] {
        let offset = CGFloat(depth) * step
        let rect = CGRect(
            x: origin.x + offset, y: origin.y + offset,
            width: cardSize, height: cardSize
        )
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: srgb(0x120A2E, 0.4))
        ctx.addPath(roundedCard(rect, radius: 44))
        ctx.setFillColor(srgb(0xFFFFFF, depth == 2 ? 0.32 : 0.55))
        ctx.fillPath()
        ctx.restoreGState()
    }

    let front = CGRect(x: origin.x, y: origin.y, width: cardSize, height: cardSize)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: srgb(0x120A2E, 0.45))
    ctx.addPath(roundedCard(front, radius: 44))
    ctx.setFillColor(srgb(0xFFFFFF, 0.97))
    ctx.fillPath()
    ctx.restoreGState()

    // The signature detail: the front sheet is holding actual text. It's what
    // makes this a clip rather than a generic stack of cards.
    ctx.saveGState()
    ctx.addPath(roundedCard(front, radius: 40))
    ctx.clip()
    let lines: [(x: CGFloat, y: CGFloat, width: CGFloat)] = [
        (314, 524, 316),
        (314, 456, 236),
        (314, 388, 156),
    ]
    for line in lines {
        let bar = CGRect(x: line.x, y: line.y, width: line.width, height: 32)
        ctx.addPath(roundedCard(bar, radius: 16))
        ctx.setFillColor(inkLine)
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Lighting: a soft gloss down from the top edge, the way macOS icons catch
    // light. Kept faint — it should be felt, not seen.
    if let gloss = CGGradient(
        colorsSpace: space,
        colors: [srgb(0xFFFFFF, 0.20), srgb(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gloss,
            start: CGPoint(x: 0, y: 924),
            end: CGPoint(x: 0, y: 560),
            options: []
        )
    }
    ctx.restoreGState()

    // Hairline edge, so the silhouette holds against a light Finder background.
    ctx.addPath(shape)
    ctx.setStrokeColor(srgb(0xFFFFFF, 0.22))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func render(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("could not create context") }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, pixelSize: CGFloat(size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("could not write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let docs = root.appendingPathComponent("docs")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

// iconutil expects this exact set of names.
let iconsetNames: [Int: [String]] = [
    16: ["icon_16x16.png"],
    32: ["icon_16x16@2x.png", "icon_32x32.png"],
    64: ["icon_32x32@2x.png"],
    128: ["icon_128x128.png"],
    256: ["icon_128x128@2x.png", "icon_256x256.png"],
    512: ["icon_256x256@2x.png", "icon_512x512.png"],
    1024: ["icon_512x512@2x.png"],
]

for size in iconSizes {
    let image = render(size: size)
    for name in iconsetNames[size] ?? [] {
        writePNG(image, to: iconset.appendingPathComponent(name))
    }
    // 512 is plenty for the README, which displays it at ~120px.
    if size == 512 {
        writePNG(image, to: docs.appendingPathComponent("icon.png"))
    }
}

print("rendered \(iconSizes.count) sizes -> \(iconset.path)")
