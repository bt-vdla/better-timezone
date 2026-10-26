// Draws the app icon. Run: swift tools/AppIcon.swift Skies/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// "One orbit": sun and moon on a single ring over a deep night-blue sky. Drawn in a 128-unit design space.
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

func drawIcon(_ ctx: CGContext, in rect: CGRect) {
    let s = rect.width / 128
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + (128 - y) * s) }  // flip: design y goes down
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Sky: lit from the upper left, deepening to night.
    let sky = CGGradient(colorsSpace: space, colors: [rgb(52, 92, 186), rgb(22, 36, 92), rgb(7, 11, 34)] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(sky, startCenter: p(34, 26), startRadius: 0, endCenter: p(34, 26), endRadius: 125 * s, options: [.drawsAfterEndLocation])

    // A few stars, lower right where the night is deepest.
    for (x, y, r, a) in [(104.0, 30.0, 0.9, 0.7), (112, 52, 0.7, 0.5), (22, 98, 0.8, 0.55), (48, 112, 0.6, 0.45), (114, 112, 0.7, 0.4), (80, 18, 0.6, 0.4)] {
        ctx.setFillColor(rgb(255, 255, 255, a))
        ctx.fillEllipse(in: CGRect(x: p(x, y).x - r * s, y: p(x, y).y - r * s, width: 2 * r * s, height: 2 * r * s))
    }

    // The orbit.
    ctx.setStrokeColor(rgb(255, 255, 255, 0.32))
    ctx.setLineWidth(2.2 * s)
    ctx.strokeEllipse(in: CGRect(x: p(28, 100).x, y: p(28, 100).y, width: 72 * s, height: 72 * s))

    // Sun with its glow, on the ring at upper left.
    let sun = p(38.5, 38.5)
    // Screen blend: the glow adds light to the sky instead of greying it.
    let glow = CGGradient(colorsSpace: space, colors: [rgb(255, 200, 90, 0.75), rgb(255, 170, 60, 0)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.drawRadialGradient(glow, startCenter: sun, startRadius: 9 * s, endCenter: sun, endRadius: 28 * s, options: [])
    ctx.restoreGState()
    let disc = CGGradient(colorsSpace: space, colors: [rgb(255, 246, 200), rgb(255, 214, 74)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: sun.x - 11 * s, y: sun.y - 11 * s, width: 22 * s, height: 22 * s))
    ctx.clip()
    ctx.drawRadialGradient(disc, startCenter: CGPoint(x: sun.x - 3 * s, y: sun.y + 3 * s), startRadius: 0, endCenter: sun, endRadius: 11 * s, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Crescent moon opposite it: the disc, less a disc slid toward the sun's far side.
    let moon = p(89.5, 89.5), r = 9 * s
    ctx.saveGState()
    let moonRect = CGRect(x: moon.x - r, y: moon.y - r, width: 2 * r, height: 2 * r)
    ctx.addEllipse(in: moonRect)
    ctx.clip()
    // The unlit side still blocks the ring behind it, faintly lit by earthshine.
    ctx.setFillColor(rgb(20, 30, 72))
    ctx.fill(moonRect)
    let cut = CGMutablePath()
    cut.addEllipse(in: moonRect)
    cut.addEllipse(in: moonRect.offsetBy(dx: 4.6 * s, dy: 3.6 * s))
    ctx.addPath(cut)
    ctx.setFillColor(rgb(244, 242, 232))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func write(_ size: Int, _ path: String, mac: Bool) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    if mac {
        // macOS grid: an 824/1024 rounded square, centred, with a soft shadow beneath.
        let k = Double(size) / 1024, inset = 100 * k
        let shape = CGPath(roundedRect: full.insetBy(dx: inset, dy: inset), cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: rgb(0, 0, 0, 0.35))
        ctx.addPath(shape); ctx.setFillColor(rgb(7, 11, 34)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        drawIcon(ctx, in: full.insetBy(dx: inset, dy: inset))
        ctx.restoreGState()
    } else {
        drawIcon(ctx, in: full)
    }
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

let out = CommandLine.arguments[1]
write(1024, "\(out)/ios-1024.png", mac: false)
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    write(pt * scale, "\(out)/mac-\(pt)@\(scale)x.png", mac: true)
}
print("ok")
