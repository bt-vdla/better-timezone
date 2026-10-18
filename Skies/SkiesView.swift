import SwiftUI

extension Color {
    init(_ c: RGB, opacity: Double = 1) { self.init(red: c.x / 255, green: c.y / 255, blue: c.z / 255, opacity: opacity) }
    init(hex v: Int, opacity: Double = 1) {
        self.init(RGB(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255)), opacity: opacity)
    }
    static let sun = Color(hex: 0xFFD54A)
    static let mint = Color(hex: 0x6EE7B7)
}

private func sf(_ size: CGFloat, _ weight: Font.Weight) -> Font { .system(size: size, weight: weight) }

struct PressScale: ButtonStyle {
    var scale = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

struct SkiesView: View {
    @State private var model = Scrubber()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: model.isMoving ? nil : 1)) { ctx in
                screen(m: model.minutes(at: ctx.date), now: nowMinutes(ctx.date))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { model.dragChanged($0, width: geo.size.width) }
                    .onEnded { model.dragEnded($0) }
            )
        }
        .background(Color(hex: 0x0A0C1A))
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .pageUp, .pageDown, .home, .escape]) { press in
            switch press.key {
            case .rightArrow: model.step(15)
            case .leftArrow: model.step(-15)
            case .pageUp: model.step(60)
            case .pageDown: model.step(-60)
            default: model.goNow()
            }
            return .handled
        }
        #if os(macOS)
        .pointerStyle(model.isMoving ? .grabActive : .grabIdle)
        #endif
        .onChange(of: reduceMotion, initial: true) { model.reduceMotion = reduceMotion }
    }

    private func screen(m: Double, now: Double) -> some View {
        let h = Local(home.tz, m)
        let delta = (m - now).rounded()
        let when = abs(delta) < 1 ? "Right now" : delta > 0 ? "In \(dur(delta))" : "\(dur(delta)) ago"
        let hourKey = Int(((m + Double(h.off)) / 60).rounded(.down))
        let showNow: Bool = switch model.mode {
            case .live: false
            case .drag: true
            default: abs(delta) >= 1
        }

        return VStack(spacing: 0) {
            ForEach(Array(zones.enumerated()), id: \.1.id) { i, z in
                SkyRow(zone: z, local: z.home ? h : Local(z.tz, m), home: h, stars: starField[i])
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header(when: when, m: m, showNow: showNow) }
        .safeAreaInset(edge: .bottom, spacing: 0) { dock(m: m, now: now, h: h, when: when, hourKey: hourKey) }
        .sensoryFeedback(.selection, trigger: hourKey) { _, _ in model.isMoving }
    }

    private func header(when: String, m: Double, showNow: Bool) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(when)
                    .font(sf(34, .bold)).tracking(-0.6).monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.updatesFrequently)
                // ponytail: String, not Text(_:format:), which swaps in the device time zone.
                Text(Date(timeIntervalSince1970: m * 60)
                    .formatted(Date.FormatStyle(timeZone: home.tz).weekday(.wide).day().month(.wide)))
                    .font(sf(13, .regular)).opacity(0.72)
            }
            Spacer()
            Button("Now", action: model.goNow)
                .font(sf(14, .bold))
                .foregroundStyle(Color(hex: 0x1D1603))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.sun, in: Capsule())
                .buttonStyle(PressScale())
                .scaleEffect(showNow || reduceMotion ? 1 : 0.5)
                .opacity(showNow ? 1 : 0)
                .allowsHitTesting(showNow)
                .animation(.spring(duration: 0.42, bounce: 0.4), value: showNow)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 15)
        .background { glass(tint: Color(hex: 0x0A0C1E, opacity: 0.34), solid: Color(hex: 0x14172E)) }
    }

    private func dock(m: Double, now: Double, h: Local, when: String, hourKey: Int) -> some View {
        let ov = overlap(m)
        return VStack(spacing: 0) {
            Button {
                if let t = ov.target { model.springTo(t, damping: 0.9, response: 0.6) }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.mint).frame(width: 13, height: 13)
                    ov.text.font(sf(13, .regular)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PressScale(scale: 0.98))
            .padding(.horizontal, 18).padding(.bottom, 12)

            Tape(m: m, now: now, hourKey: hourKey)
                .frame(height: 68)
                .onTapGesture(count: 2, perform: model.goNow)
                .accessibilityElement()
                .accessibilityLabel("Scrub time")
                .accessibilityValue("\(home.city) \(clock(h)) \(ampm(h.h)), \(when)")
                .accessibilityAdjustableAction { $0 == .increment ? model.step(15) : model.step(-15) }

            Text("Drag anywhere on the skies. Double‑tap the tape to snap back.")
                .font(sf(12, .regular))
                .opacity(model.hintGone ? 0 : 0.55)
                .animation(.easeOut(duration: 0.5), value: model.hintGone)
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(.top, 14).padding(.bottom, 8)
        .background { glass(tint: Color(hex: 0x080A18, opacity: 0.64), solid: Color(hex: 0x0B0D1C)) }
    }

    private func glass(tint: Color, solid: Color) -> some View {
        ReduceTransparencyAware(tint: tint, solid: solid).ignoresSafeArea()
    }

    private func overlap(_ m: Double) -> (text: Text, target: Double?) {
        let runs = overlapRuns(m)
        func homeTime(_ x: Double) -> (String, String) { let l = Local(home.tz, x); return (clock(l), ampm(l.h)) }
        if let inside = runs.first(where: { $0.lowerBound <= m && m < $0.upperBound }) {
            let e = homeTime(inside.upperBound)
            return (Text("Everyone’s up right now, until \(Text("\(e.0) \(e.1)").bold()) your time"), nil)
        }
        guard let r = runs.first(where: { $0.lowerBound > m }) ?? runs.first else {
            return (Text("No window where everyone’s awake this day"), nil)
        }
        let a = homeTime(r.lowerBound), b = homeTime(r.upperBound)
        let range = a.1 == b.1 ? "\(a.0)–\(b.0) \(b.1)" : "\(a.0) \(a.1)–\(b.0) \(b.1)"
        return (Text("Everyone’s up \(Text(range).bold()) your time. Tap to jump there."), r.lowerBound)
    }
}

private struct ReduceTransparencyAware: View {
    let tint: Color, solid: Color
    @Environment(\.accessibilityReduceTransparency) private var reduce

    var body: some View {
        if reduce { solid } else { Rectangle().fill(.ultraThinMaterial).overlay(tint) }
    }
}

// MARK: - Sky band

struct Star { let x, y, s: Double }

let starField: [[Star]] = {
    var seed = 7.0
    func rnd() -> Double { seed = (seed * 16807).truncatingRemainder(dividingBy: 2147483647); return seed / 2147483647 }
    return zones.map { _ in (0..<12).map { _ in Star(x: rnd(), y: rnd(), s: 0.6 + rnd() * 0.9) } }
}()

struct SkyRow: View {
    let zone: Zone, local: Local, home: Local, stars: [Star]

    var body: some View {
        let (c1, c2) = sky(local.f)
        let lu = luminance(mix(c1, c2, 0.55))
        let ink = Color(mix(RGB(255, 255, 255), RGB(16, 19, 34), smooth(clamp01((lu - 0.32) / 0.16))))
        let (label, dot) = status(local.f)

        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(zone.city).font(sf(20, .semibold))
                Text(zone.tag).font(sf(13, .regular)).opacity(0.72).padding(.top, 2)
                HStack(spacing: 6) {
                    Circle().fill(Color(dot)).frame(width: 7, height: 7)
                        .background(Circle().fill(ink.opacity(0.3)).padding(-1.5))
                    Text(label).font(sf(12, .semibold))
                }
                .padding(.vertical, 4).padding(.leading, 8).padding(.trailing, 10)
                .background(ink.opacity(0.13), in: Capsule())
                .padding(.top, 9)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(clock(local)).font(sf(44, .bold)).tracking(-1).monospacedDigit()
                    Text(ampm(local.h)).font(sf(15, .semibold))
                }
                Text(relative).font(sf(12, .regular)).opacity(0.78)
            }
            .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Orb(f: local.f).padding(.horizontal, 22) }
        .background {
            ZStack {
                LinearGradient(colors: [Color(c1), Color(c2)], startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in
                    for s in stars {
                        let r = s.s
                        ctx.fill(Path(ellipseIn: CGRect(x: s.x * size.width - r, y: s.y * size.height - r, width: r * 2, height: r * 2)),
                                 with: .color(.white))
                    }
                }
                .opacity(clamp01((0.1 - lu) / 0.07))
            }
            .ignoresSafeArea()
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private var relative: String {
        if zone.home {
            return Date(timeIntervalSince1970: Double(local.dn) * 86400)
                .formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated))
        }
        let dd = local.dn - home.dn
        let day = dd == 0 ? "" : dd == 1 ? "Tomorrow, " : dd == -1 ? "Yesterday, " : Calendar.current.shortWeekdaySymbols[local.wd] + ", "
        let diff = Double(local.off - home.off)
        return day + (diff == 0 ? "same time" : "\(dur(diff)) \(diff < 0 ? "behind" : "ahead")")
    }
}

struct Orb: View {
    let f: Double
    private let size = 27.0

    var body: some View {
        GeometryReader { g in
            let day = f >= 6 && f < 18
            let t = day ? (f - 6) / 12 : (f - 18 + 24).truncatingRemainder(dividingBy: 24) / 12
            let x = t * (g.size.width - size) + size / 2
            let y = g.size.height - sin(.pi * t) * g.size.height * 0.72
            Group {
                if day {
                    Circle()
                        .fill(RadialGradient(stops: [.init(color: Color(hex: 0xFFF7C9), location: 0),
                                                     .init(color: .sun, location: 0.58),
                                                     .init(color: Color(hex: 0xFFAE1F), location: 1)],
                                             center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: size * 0.92))
                        .shadow(color: Color(hex: 0xFFCD46, opacity: 0.5), radius: 16)
                } else {
                    Circle().subtracting(Circle().offset(x: -7.7, y: 3.5))
                        .fill(Color(hex: 0xF3EFFF))
                        .shadow(color: Color(hex: 0xF3EFFF, opacity: 0.5), radius: 8)
                }
            }
            .frame(width: size, height: size)
            .position(x: x, y: y)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tape

struct Tape: View {
    let m: Double, now: Double, hourKey: Int

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, bandH = size.height - 20
            let span = cx / pxPerMinute + 30
            var a = ((m - span) / 15).rounded(.down) * 15
            while a <= m + span {
                let xp = cx + (a - m) * pxPerMinute
                if allAwake(a) {
                    ctx.fill(Path(CGRect(x: xp, y: 0, width: 15 * pxPerMinute + 0.6, height: bandH)), with: .color(.mint.opacity(0.24)))
                }
                let l = Local(home.tz, a)
                if l.m == 0 {
                    let mid = l.h == 0
                    ctx.fill(Path(CGRect(x: xp - 0.75, y: 6, width: 1.5, height: mid ? 26 : 18)),
                             with: .color(.white.opacity(mid ? 1 : 0.55)))
                    let label = mid ? Calendar.current.shortWeekdaySymbols[l.wd] : "\(h12(l.h)) \(ampm(l.h))"
                    ctx.draw(Text(label).font(sf(11, mid ? .bold : .medium)).foregroundStyle(.white.opacity(mid ? 1 : 0.6)),
                             at: CGPoint(x: xp, y: size.height - 3), anchor: .bottom)
                } else {
                    ctx.fill(Path(CGRect(x: xp - 0.5, y: 6, width: 1, height: l.m == 30 ? 10 : 6)), with: .color(.white.opacity(0.28)))
                }
                a += 15
            }
            let xn = cx + (now - m) * pxPerMinute
            if xn > -10 && xn < size.width + 10 {
                ctx.fill(Path(ellipseIn: CGRect(x: xn - 3.5, y: bandH - 7.5, width: 7, height: 7)), with: .color(.sun))
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                     .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .top) {
            Capsule().fill(.white)
                .frame(width: 2.5)
                .padding(.bottom, 20)
                .shadow(color: .white.opacity(0.65), radius: 7)
                .keyframeAnimator(initialValue: 1.0, trigger: hourKey) { v, s in v.scaleEffect(x: s) } keyframes: { _ in
                    CubicKeyframe(2.4, duration: 0.01)
                    SpringKeyframe(1, duration: 0.24)
                }
        }
    }
}
