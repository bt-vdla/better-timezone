import SwiftUI
import CoreGraphics

/// The same fine grain as the sky shader, for skies drawn without it (widgets, plain gradient cards): a small noise
/// tile made once, laid over the colours.
struct Grain: View {
    var strength: Double = 0.16

    private static let tile: CGImage? = {
        let n = 96
        var px = [UInt8](repeating: 0, count: n * n)
        var r: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<px.count {
            r = r &* 6364136223846793005 &+ 1442695040888963407
            let a = Double(r >> 40 & 0xFFFF) / 65535, b = Double(r >> 20 & 0xFFFF) / 65535
            px[i] = UInt8(min(255, max(0, 128 + (a + b - 1) * 150)))
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()

    var body: some View {
        if let tile = Self.tile {
            // Scale 2: one grain per pixel on Retina, which is what makes it read as fine rather than speckled.
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
