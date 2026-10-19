import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Color {
    init(_ c: RGB, opacity: Double = 1) { self.init(red: c.x / 255, green: c.y / 255, blue: c.z / 255, opacity: opacity) }
    init(hex v: Int, opacity: Double = 1) {
        self.init(RGB(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255)), opacity: opacity)
    }
    static let sun = Color(hex: 0xFFD54A)
    static let mint = Color(hex: 0x6EE7B7)
}

extension Animation {
    /// Strong ease-out for state changes (cubic-bezier(0.23, 1, 0.32, 1)).
    static func easeOutStrong(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
}

func sf(_ size: CGFloat, _ weight: Font.Weight) -> Font { .system(size: size, weight: weight) }

/// Weather-style legibility for white type over a live sky.
extension View {
    func skyLegible() -> some View { compositingGroup().shadow(color: .black.opacity(0.25), radius: 8, y: 1) }
}

struct PressScale: ButtonStyle {
    var scale = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOutStrong(0.12), value: configuration.isPressed)
    }
}

enum Sheet: Identifiable {
    case people, person(UUID), planner
    var id: String {
        switch self {
        case .people: "people"
        case .planner: "planner"
        case .person(let id): id.uuidString
        }
    }
}

struct SkiesView: View {
    let people: People
    @State private var model = Scrubber()
    @State private var sheet: Sheet?
    @State private var width = 390.0
    @AppStorage("coached") private var coached = false
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: model.isMoving ? nil : 1)) { ctx in
            screen(m: model.minutes(at: ctx.date), now: nowMinutes(ctx.date))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { model.dragChanged($0, width: width) }
                .onEnded { model.dragEnded($0) }
        )
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .background(Color(hex: 0x05070F))
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .pageUp, .pageDown, .home, .escape]) { press in
            switch press.key {
            case .rightArrow: model.step(15)
            case .leftArrow: model.step(-15)
            case .pageUp: model.step(60)
            case .pageDown: model.step(-60)
            default: model.jumpNow()
            }
            return .handled
        }
        #if os(macOS)
        .pointerStyle(model.isMoving ? .grabActive : .grabIdle)
        .onAppear(perform: watchScrollWheel)
        #endif
        .onChange(of: reduceMotion, initial: true) { model.reduceMotion = reduceMotion }
        .sheet(item: $sheet) { s in
            switch s {
            case .people: PeopleSheet(people: people)
            case .person(let id): PersonPage(people: people, model: model, id: id)
            case .planner: PlannerSheet(people: people, model: model)
            }
        }
    }

    #if os(macOS)
    private func watchScrollWheel() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            MainActor.assumeIsolated {
                guard sheet == nil, e.window?.isKeyWindow == true else { return }
                let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
                if e.hasPreciseScrollingDeltas {
                    model.scroll(by: abs(dx) >= abs(dy) ? dx : dy, width: width)
                } else if dy != 0 {
                    model.step(dy > 0 ? -15 : 15)
                }
            }
            return e
        }
    }
    #endif

    private func screen(m: Double, now: Double) -> some View {
        let home = people.home
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
            ForEach(people.list) { p in
                SkyRow(person: p, minutes: m, local: p.isHome ? h : Local(p.tz, m), home: h,
                       dimmed: !people.everyone && !people.team.contains(p), picked: !people.picked.isEmpty && people.picked.contains(p.id),
                       animateDigits: !model.isMoving)
                    .contentShape(Rectangle())
                    .onTapGesture { people.toggle(p) }
                    .contextMenu {
                        Button("Open \(p.city)", systemImage: "arrow.up.left.and.arrow.down.right") { sheet = .person(p.id) }
                        if !p.isHome {
                            Button("Plan with \(p.city) only", systemImage: "person.crop.circle") { people.picked = [p.id] }
                        }
                        Button("Edit People…", systemImage: "person.2") { sheet = .people }
                    }
                    .accessibilityAddTraits(people.picked.contains(p.id) ? .isSelected : [])
                    .accessibilityHint(p.isHome ? "" : "Double-tap to include in the overlap")
                    .accessibilityAction(named: "Open \(p.city)") { sheet = .person(p.id) }
            }
        }
        .animation(.easeOutStrong(0.2), value: people.picked)
        .sensoryFeedback(.selection, trigger: people.picked)
        .safeAreaInset(edge: .top, spacing: 0) { header(when: when, m: m, home: home, showNow: showNow) }
        .safeAreaInset(edge: .bottom, spacing: 0) { dock(m: m, now: now, h: h, when: when, hourKey: hourKey) }
        .sensoryFeedback(.selection, trigger: hourKey) { _, _ in model.isMoving }
    }

    private func header(when: String, m: Double, home: Person, showNow: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(when)
                    .font(sf(34, .semibold)).tracking(-0.5).monospacedDigit()
                    .accessibilityAddTraits(.updatesFrequently)
                // ponytail: String, not Text(_:format:), which swaps in the device time zone.
                Text(Date(timeIntervalSince1970: m * 60)
                    .formatted(Date.FormatStyle(timeZone: home.tz).weekday(.wide).day().month(.wide)))
                    .font(sf(15, .medium)).opacity(0.8)
            }
            .skyLegible()
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if showNow {
                        Button("Now", action: model.goNow)
                            .font(sf(15, .semibold))
                            .foregroundStyle(Color(hex: 0x1D1603))
                            .padding(.horizontal, 16).frame(height: 40)
                            .glassEffect(.regular.tint(.sun).interactive(), in: Capsule())
                            .glassEffectID("now", in: glass)
                            .buttonStyle(.plain)
                    }
                    Button { sheet = .people } label: {
                        Image(systemName: "person.2.fill").font(sf(15, .semibold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID("people", in: glass)
                    .accessibilityLabel("People")
                }
            }
            .animation(reduceMotion ? .easeOutStrong(0.2) : .spring(response: 0.35, dampingFraction: 1), value: showNow)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
        .background { EdgeFade(edge: .top) }
    }

    private func dock(m: Double, now: Double, h: Local, when: String, hourKey: Int) -> some View {
        let ov = overlap(m, now: now)
        return VStack(spacing: 12) {
            if !coached { coach }
            HStack(spacing: 12) {
                Button {
                    if let t = ov.target { model.springTo(t, response: 0.5) }
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Color.mint).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 4) {
                            ov.text.font(sf(14, .regular))
                            if let note = ov.note {
                                Label(note, systemImage: "clock.arrow.2.circlepath")
                                    .font(sf(12, .medium)).foregroundStyle(Color.sun)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.98))

                if !people.everyone {
                    Button { people.picked = [] } label: {
                        Image(systemName: "xmark").font(sf(13, .bold)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Include everyone")
                }
                Button { sheet = .planner } label: {
                    Image(systemName: "calendar").font(sf(14, .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("This week")
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
            .glassEffect(.regular.tint(.mint.opacity(0.18)), in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 14)

            Tape(m: m, now: now, hourKey: hourKey, home: people.home, team: people.team, all: people.list)
                .frame(height: 68)
                .onTapGesture(count: 2, perform: model.goNow)
                .accessibilityElement()
                .accessibilityLabel("Scrub time")
                .accessibilityValue("\(people.home.city) \(clock(h)) \(ampm(h.h)), \(when)")
                .accessibilityAdjustableAction { $0 == .increment ? model.step(15) : model.step(-15) }
        }
        .foregroundStyle(.white)
        .padding(.top, 18).padding(.bottom, 6)
        .background { EdgeFade(edge: .bottom) }
    }

    // MARK: Coaching: learn by doing, once

    private var coach: some View {
        let stage = !model.hintGone ? 0 : people.picked.isEmpty ? 1 : 2
        let (icon, title, body): (String, String, String) = switch stage {
            case 0: ("hand.draw", "Drag the sky", dragHint)
            case 1: ("hand.tap", "Tap a city", "Pick who you want to talk to. You're always included.")
            default: ("checkmark.circle", "That's your overlap", "Green on the tape is when you're all free. Tap the pill to jump there.")
        }
        // Sits in the dock, above the pill, so it never covers the rows it's asking you to touch.
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(sf(26, .regular)).frame(width: 34)
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)), isActive: !reduceMotion && stage < 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(sf(17, .semibold))
                Text(body).font(sf(14, .regular)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if stage == 2 {
                Button("Got it") { coached = true }
                    .font(sf(15, .semibold)).padding(.horizontal, 16).frame(height: 36)
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.mint.opacity(0.5)).interactive(), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 14)
        .id(stage)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
        .animation(.easeOutStrong(0.25), value: stage)
        .allowsHitTesting(stage == 2)
    }

    private var dragHint: String {
        #if os(macOS)
        "Drag sideways, or swipe with two fingers, to move through time."
        #else
        "Slide sideways anywhere to move through time."
        #endif
    }

    // MARK: Overlap text

    private var who: String {
        if people.everyone { return "Everyone" }
        let others = people.team.filter { !$0.isHome }.map(\.city)
        return others.count == 1 ? "You and \(others[0])" : others.count == 2 ? "You, \(others[0]) and \(others[1])" : "You and \(others.count) others"
    }

    private func overlap(_ m: Double, now: Double) -> (text: Text, target: Double?, note: String?) {
        let home = people.home
        let runs = people.runs(from: dayStart(home.tz, m))
        let note = clockNote(people, after: max(m, now))
        func homeTime(_ x: Double) -> (String, String) { let l = Local(home.tz, x); return (clock(l), ampm(l.h)) }

        if let inside = runs.first(where: { $0.lowerBound <= m && m < $0.upperBound }) {
            let e = homeTime(inside.upperBound)
            return (Text("\(who) free now, until \(Text("\(e.0) \(e.1)").bold()) your time"), nil, note)
        }
        guard let r = runs.first(where: { $0.lowerBound > m }) else {
            return (Text("\(who): no shared free time in the next week"), nil, note)
        }
        let days = Local(home.tz, r.lowerBound).dn - Local(home.tz, m).dn
        let day = days == 0 ? "" : days == 1 ? "tomorrow " : Calendar.current.weekdaySymbols[Local(home.tz, r.lowerBound).wd] + " "
        return (Text("\(who) free \(day)\(Text(timeRange(r, home)).bold()) your time. Tap to jump."), r.lowerBound, note)
    }
}

func timeRange(_ r: ClosedRange<Double>, _ home: Person) -> String {
    let a = Local(home.tz, r.lowerBound), b = Local(home.tz, r.upperBound)
    return ampm(a.h) == ampm(b.h) ? "\(clock(a))–\(clock(b)) \(ampm(b.h))" : "\(clock(a)) \(ampm(a.h))–\(clock(b)) \(ampm(b.h))"
}

/// The first upcoming clock change in the next two weeks that actually changes the team's shared window.
@MainActor func clockNote(_ people: People, after m: Double) -> String? {
    let home = people.home, team = people.team
    func shared(_ x: Double) -> Double {
        freeRuns(team, from: dayStart(home.tz, x), slots: 96).reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }
    for c in clockChanges(team, in: m...(m + 14 * 1440)) {
        // Same weekday a week apart, so days off don't read as a clock-change effect.
        let before = shared(c.at + 1440 - 7 * 1440), after = shared(c.at + 1440)
        guard before != after else { continue }
        let date = Date(timeIntervalSince1970: c.at * 60)
            .formatted(Date.FormatStyle(timeZone: home.tz).weekday(.abbreviated).day().month(.abbreviated))
        let change = after == 0 ? "no shared time" : after < before ? "shrinks to \(dur(after))" : "grows to \(dur(after))"
        return "From \(date), \(c.person.city) clocks change: overlap \(change)"
    }
    return nil
}

/// Chrome that melts into the sky instead of sitting on it as a slab.
struct EdgeFade: View {
    let edge: VerticalEdge
    @Environment(\.accessibilityReduceTransparency) private var reduce

    var body: some View {
        let fade = LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                          .init(color: .clear, location: 1)],
                                  startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
        Group {
            if reduce { Color(hex: 0x0B0D1C) }
            else { Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(edge == .top ? 0.15 : 0.35)).mask(fade) }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sky band

struct SkyRow: View {
    let person: Person, minutes: Double, local: Local, home: Local
    var dimmed = false, picked = false, animateDigits = true

    var body: some View {
        let (label, dot) = status(person, local)
        ViewThatFits(in: .vertical) {
            content(label: label, dot: dot, compact: false)
            content(label: label, dot: dot, compact: true)
        }
        .foregroundStyle(.white)
        .skyLegible()
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { g in
                SkyBackground(person: person, minutes: minutes, insets: g.safeAreaInsets).ignoresSafeArea()
            }
        }
        .overlay { Color.black.opacity(dimmed ? 0.5 : 0).allowsHitTesting(false) }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func content(label: String, dot: RGB, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(person.city).font(sf(compact ? 18 : 22, .semibold))
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(sf(compact ? 15 : 17, .semibold))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                if !compact {
                    if !person.label.isEmpty {
                        Text(person.label).font(sf(14, .medium)).opacity(0.8).padding(.top, 2)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color(dot)).frame(width: 7, height: 7)
                        Text(label).font(sf(12, .semibold))
                    }
                    .padding(.vertical, 4).padding(.leading, 8).padding(.trailing, 10)
                    .background(.white.opacity(0.16), in: Capsule())
                    .padding(.top, 9)
                } else {
                    Text(label).font(sf(12, .medium)).opacity(0.8)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: compact ? 0 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(clock(local)).font(sf(compact ? 38 : 50, .light)).tracking(compact ? -0.6 : -1.2).monospacedDigit()
                        .contentTransition(.numericText(value: Double(local.h * 60 + local.m)))
                        .animation(animateDigits ? .easeOutStrong(0.25) : nil, value: local.m)
                    Text(ampm(local.h)).font(sf(compact ? 13 : 15, .medium))
                }
                Text(relative).font(sf(12, .medium)).opacity(0.8)
            }
            .lineLimit(1)
        }
        .padding(.vertical, compact ? 6 : 12)
    }

    private var relative: String {
        if person.isHome {
            return Date(timeIntervalSince1970: Double(local.dn) * 86400)
                .formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated))
        }
        let dd = local.dn - home.dn
        let day = dd == 0 ? "" : dd == 1 ? "Tomorrow, " : dd == -1 ? "Yesterday, " : Calendar.current.shortWeekdaySymbols[local.wd] + ", "
        let diff = Double(local.off - home.off)
        return day + (diff == 0 ? "same time" : "\(dur(diff)) \(diff < 0 ? "behind" : "ahead")")
    }
}

// MARK: - Tape

struct Tape: View {
    let m: Double, now: Double, hourKey: Int
    let home: Person, team: [Person], all: [Person]

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, bandH = size.height - 20
            let span = cx / pxPerMinute + 30
            var a = ((m - span) / 15).rounded(.down) * 15
            while a <= m + span {
                let xp = cx + (a - m) * pxPerMinute
                let free = team.filter { $0.free(Local($0.tz, a)) }.count
                if free > 0 {
                    let alpha = free == team.count ? 0.32 : 0.03 + 0.12 * Double(free) / Double(team.count)
                    ctx.fill(Path(CGRect(x: xp, y: 0, width: 15 * pxPerMinute + 0.6, height: bandH)), with: .color(.mint.opacity(alpha)))
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

            for c in clockChanges(all, in: (m - span)...(m + span)) {
                let xp = cx + (c.at - m) * pxPerMinute
                ctx.fill(Path(CGRect(x: xp - 0.75, y: 2, width: 1.5, height: bandH - 2)), with: .color(.sun.opacity(0.9)))
                let shift = c.shift > 0 ? "+\(dur(Double(c.shift)))" : "−\(dur(Double(c.shift)))"
                ctx.draw(Text("\(c.person.city) \(shift)").font(sf(10, .semibold)).foregroundStyle(Color.sun),
                         at: CGPoint(x: xp + 4, y: bandH / 2 + 8), anchor: .leading)
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
