import SwiftUI

extension EnvironmentValues {
    /// True while the window holding these views can't be seen (closed, minimised, covered, another Space):
    /// every clock and twinkle holds still, since an AppKit window keeps ticking them otherwise.
    @Entry var offscreen = false
}

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
    /// False for skies too small to hold a sun or moon without covering text: the colours still tell day from night.
    var discs = true
    /// Richer colours for small skies on black (the notch); 0 is the real palette.
    var vividness: Double = 0
    /// Stars twinkle on the sky's own 15 fps clock, so a night sky never re-runs the screen around it.
    /// They drift at under 1 Hz, so 15 fps still reads as smooth and costs half of 30.
    var twinkle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreen) private var offscreen
    #if os(macOS)
    /// A Mac window left in the background keeps its stars still; they pick up again once it's in use.
    @Environment(\.controlActiveState) private var activeState
    private var still: Bool { offscreen || activeState == .inactive || ProcessInfo.processInfo.isLowPowerModeEnabled }
    #else
    /// Low Power Mode keeps the stars, just not their twinkle; checked again with each minute's redraw.
    private var still: Bool { offscreen || ProcessInfo.processInfo.isLowPowerModeEnabled }
    #endif

    var body: some View {
        let real = skyState(person, minutes)
        Group {
            if twinkle && !reduceMotion && real.sunElev < -5 {
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: still)) { ctx in sky(real, time: ctx.date.timeIntervalSinceReferenceDate) }
            } else {
                sky(real, time: time)
            }
        }
        .accessibilityHidden(true)
    }

    private func sky(_ real: SkyState, time: Double) -> some View {
        let s = SkyState(sunElev: real.sunElev, sunX: real.sunX, moonElev: real.moonElev, moonX: real.moonX, phase: real.phase,
                         zenith: vivid(real.zenith, vividness), horizon: vivid(real.horizon, vividness))
        let seed = Double(person.city.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 997)
        let insets = insets, time = time.truncatingRemainder(dividingBy: 3600), flare = flare, discs = discs
        return Rectangle().visualEffect { content, proxy in
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
                // Without discs, sun and moon sit far off-canvas: no disc, no halo, but the sky keeps its colour.
                .float(s.sunElev), discs ? .float2(x(s.sunX), y(s.sunElev)) : .float2(-2000, -2000),
                .float(discs ? s.moonElev : -90), .float2(x(min(1, max(0, s.moonX))), y(s.moonElev)), .float(s.phase),
                .float(seed), .float(time), .float(flare)))
        }
    }
}
