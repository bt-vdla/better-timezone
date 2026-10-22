import SwiftUI

/// The real sky over one person at one moment, drawn by Sky.metal. The bottom edge is their horizon.
struct SkyBackground: View {
    let person: Person
    let minutes: Double
    /// How far the layer runs on under chrome above and below the visible band.
    var insets = EdgeInsets()
    /// Seconds, for twinkling stars; 0 holds them still (Reduce Motion).
    var time: Double = 0
    /// Halo, starburst and lens-flare strength: full on big skies, gentler behind text.
    var flare: Double = 0.45

    var body: some View {
        let s = skyState(person, minutes)
        let seed = Double(person.city.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 997)
        let insets = insets, time = time.truncatingRemainder(dividingBy: 3600), flare = flare
        Rectangle().visualEffect { content, proxy in
            let w = proxy.size.width, top = insets.top
            let h = max(1, proxy.size.height - insets.top - insets.bottom)
            // Elevation to height: about 50° fills a band, so a low winter sun really does sit low.
            // Full-screen skies get a gentler arc so a high sun stays in view.
            let k = h < 320 ? 0.85 : 0.6
            func y(_ elev: Double) -> Double { top + max(16, h - elev / 50 * h * k) }
            func x(_ t: Double) -> Double { 18 + t * (w - 36) }
            return content.colorEffect(ShaderLibrary.sky(
                .float2(proxy.size), .float2(top, h),
                .float3(s.zenith.x / 255, s.zenith.y / 255, s.zenith.z / 255),
                .float3(s.horizon.x / 255, s.horizon.y / 255, s.horizon.z / 255),
                .float(s.sunElev), .float2(x(s.sunX), y(s.sunElev)),
                .float(s.moonElev), .float2(x(min(1, max(0, s.moonX))), y(s.moonElev)), .float(s.phase),
                .float(seed), .float(time), .float(flare)))
        }
        .accessibilityHidden(true)
    }
}
