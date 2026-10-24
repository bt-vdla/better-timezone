import SwiftUI
import EventKit
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

extension Font {
    /// SF Pro at a fixed size: for images, Canvas labels and glyphs inside fixed-size circles.
    static func sf(_ size: CGFloat, _ weight: Font.Weight) -> Font { .system(size: size, weight: weight) }
}

extension Font.TextStyle {
    /// The style whose default size is nearest, so each size grows at Apple's rate for it.
    /// Big numerals land on .largeTitle, which grows least, so clocks stay on screen.
    static func near(_ size: CGFloat) -> Self {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<19: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}

/// SF Pro that follows Dynamic Type: exactly `size` at the default text size.
struct ScaledSF: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(_ size: CGFloat, _ weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .near(size))
        self.weight = weight
    }

    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
}

extension DynamicTypeSize {
    /// Side by side, or stacked once text reaches accessibility sizes.
    func row(spacing: CGFloat? = nil, stackSpacing: CGFloat = 2) -> AnyLayout {
        isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: stackSpacing)) : AnyLayout(HStackLayout(spacing: spacing))
    }
}

extension View {
    func sf(_ size: CGFloat, _ weight: Font.Weight) -> some View { modifier(ScaledSF(size, weight)) }
}

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
    @State private var holidays = Holidays()
    @AppStorage("coached") private var coached = false
    @Environment(\.openURL) private var openURL
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Stars twinkle, so a night sky anywhere keeps the clock running at 60 fps; otherwise once a second.
        let twinkle = !reduceMotion && people.list.contains { sunPosition($0, nowMinutes()).elev < -6 }
        TimelineView(.animation(minimumInterval: model.isMoving ? nil : twinkle ? 1.0 / 60 : 1)) { ctx in
            screen(m: model.minutes(at: ctx.date), now: nowMinutes(ctx.date),
                   time: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate)
                // ponytail: the glance screen can't scroll, so like widgets its type stops at the largest standard size;
                // past that, six people's clocks stop fitting. Sheets, person pages and onboarding get the full range.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
            case .people: PeopleSheet(people: people, model: model, holidays: holidays)
            case .person(let id): PersonPage(people: people, model: model, holidays: holidays, id: id)
            case .planner: PlannerSheet(people: people, model: model)
            }
        }
        .task { await people.fillRegions() }
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

    private func screen(m: Double, now: Double, time: Double) -> some View {
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
                let l = p.isHome ? h : Local(p.tz, m)
                SkyRow(person: p, minutes: m, local: l, home: h,
                       dimmed: !people.everyone && !people.team.contains(p), picked: !people.picked.isEmpty && people.picked.contains(p.id),
                       animateDigits: !model.isMoving, occasion: occasion(p, l), time: time)
                    .contentShape(Rectangle())
                    .onTapGesture { people.toggle(p) }
                    .contextMenu {
                        Button("Open \(p.shortName)", systemImage: "arrow.up.left.and.arrow.down.right") { sheet = .person(p.id) }
                        if !p.isHome {
                            Button("Plan with \(p.shortName) only", systemImage: "person.crop.circle") { people.picked = [p.id] }
                        }
                        if let c = p.contact, let fav = c.preferred {
                            // The favourite first, like the Phone app; the other two everyday ways after it.
                            ForEach([fav] + [Channel.Method.call, .facetime].filter { $0 != fav.method }.map { Channel(method: $0, value: fav.value) },
                                    id: \.self) { ch in
                                Button("\(ch.method.title) \(c.firstName)", systemImage: ch.method.icon) { if let u = ch.url { openURL(u) } }
                            }
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
        // A soft knock as you scrub anyone's sky past sunrise or sunset.
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: people.list.map { sunPosition($0, m).elev > -0.833 }) { _, _ in
            model.isMoving
        }
    }

    /// A birthday beats a holiday; both are on their local day.
    private func occasion(_ p: Person, _ l: Local) -> (icon: String, text: String)? {
        if p.birthday(l) { return ("birthday.cake.fill", "Birthday") }
        return holidays.holiday(p, l).map { ("sparkles", $0) }
    }

    private func header(when: String, m: Double, home: Person, showNow: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(when)
                    .sf(34, .semibold).tracking(-0.5).monospacedDigit()
                    .accessibilityAddTraits(.updatesFrequently)
                // ponytail: String, not Text(_:format:), which swaps in the device time zone.
                Text(Date(timeIntervalSince1970: m * 60)
                    .formatted(Date.FormatStyle(timeZone: home.tz).weekday(.wide).day().month(.wide)))
                    .sf(15, .medium).opacity(0.8)
            }
            .skyLegible()
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if showNow {
                        Button("Now", action: model.goNow)
                            .sf(15, .semibold)
                            .foregroundStyle(Color(hex: 0x1D1603))
                            .padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 40)
                            .glassEffect(.regular.tint(.sun).interactive(), in: Capsule())
                            .glassEffectID("now", in: glass)
                            .buttonStyle(.plain)
                    }
                    Button { sheet = .people } label: {
                        Image(systemName: "person.2.fill").font(.sf(15, .semibold)).frame(width: 40, height: 40)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ov.title).sf(16, .semibold).monospacedDigit()
                            Text(ov.subtitle).sf(12, .medium).opacity(0.7)
                            if let note = ov.note {
                                Label(note, systemImage: "clock.arrow.2.circlepath")
                                    .sf(12, .medium).foregroundStyle(Color.sun).padding(.top, 2)
                            }
                        }
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        Spacer(minLength: 0)
                        if ov.target != nil {
                            Image(systemName: "arrow.right").sf(13, .semibold).opacity(0.6)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.98))
                .accessibilityHint(ov.target != nil ? "Jumps to that time" : "")

                if !people.everyone {
                    Button { people.picked = [] } label: {
                        Image(systemName: "xmark").font(.sf(13, .bold)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Include everyone")
                }
                Button { sheet = .planner } label: {
                    Image(systemName: "calendar").font(.sf(14, .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Plan this week")
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
            .glassEffect(.regular.tint(.mint.opacity(0.18)), in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 14)

            Tape(m: m, now: now, hourKey: hourKey, home: people.home, team: people.team, all: people.list, mode: people.mode)
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

    /// One quiet line that teaches by doing: drag, then tap a city. It finishes on its own.
    private var coach: some View {
        let dragged = model.hintGone
        return Label(dragged ? "Now tap a city to plan with them" : dragHint,
                     systemImage: dragged ? "hand.tap" : "hand.draw")
            .sf(14, .medium)
            .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)), isActive: !reduceMotion)
            .padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 36)
            .glassEffect(.regular, in: Capsule())
            .id(dragged)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeOutStrong(0.25), value: dragged)
            .allowsHitTesting(false)
            .onChange(of: people.picked) { if dragged && !people.picked.isEmpty { coached = true } }
    }

    private var dragHint: String {
        #if os(macOS)
        "Drag or swipe the sky to move through time"
        #else
        "Slide the sky to move through time"
        #endif
    }

    // MARK: Overlap text

    private var who: String {
        if people.everyone { return "Everyone" }
        let others = people.team.filter { !$0.isHome }.map(\.shortName)
        return others.count == 1 ? "You and \(others[0])" : others.count == 2 ? "You, \(others[0]) and \(others[1])" : "You and \(others.count) others"
    }

    /// The pill: when, big; who, small; and a clock-change warning only when one matters.
    private func overlap(_ m: Double, now: Double) -> (title: String, subtitle: String, target: Double?, note: String?) {
        let home = people.home
        let runs = people.runs(from: dayStart(home.tz, m))
        let note = clockNote(people, after: max(m, now))
        let verb = people.mode == .personal ? "can talk" : "free"

        if let inside = runs.first(where: { $0.lowerBound <= m && m < $0.upperBound }) {
            let e = Local(home.tz, inside.upperBound)
            return ("Now until \(clock(e)) \(ampm(e.h))", "\(who) \(verb)", nil, note)
        }
        guard let r = runs.first(where: { $0.lowerBound > m }) else {
            return ("No shared time this week", who, nil, note)
        }
        let days = Local(home.tz, r.lowerBound).dn - Local(home.tz, m).dn
        let day = days == 0 ? "" : days == 1 ? "Tomorrow " : Calendar.current.shortWeekdaySymbols[Local(home.tz, r.lowerBound).wd] + " "
        return ("\(day)\(timeRange(r, home))", "\(who) \(verb) · your time", r.lowerBound, note)
    }
}

func timeRange(_ r: ClosedRange<Double>, _ home: Person) -> String {
    let a = Local(home.tz, r.lowerBound), b = Local(home.tz, r.upperBound)
    return ampm(a.h) == ampm(b.h) ? "\(clock(a))–\(clock(b)) \(ampm(b.h))" : "\(clock(a)) \(ampm(a.h))–\(clock(b)) \(ampm(b.h))"
}

/// The first upcoming clock change in the next two weeks that actually changes the team's shared window.
@MainActor func clockNote(_ people: People, after m: Double) -> String? {
    let home = people.home
    // Read from the cached 8-day runs, clipped to the one day: this runs every frame while scrubbing.
    func shared(_ x: Double) -> Double {
        let d = dayStart(home.tz, x)
        return people.runs(from: d).reduce(0) { $0 + max(0, min($1.upperBound, d + 1440) - max($1.lowerBound, d)) }
    }
    for c in clockChanges(people.team, in: m...(m + 14 * 1440)) {
        // Same weekday a week apart, so days off don't read as a clock-change effect.
        let before = shared(c.at + 1440 - 7 * 1440), after = shared(c.at + 1440)
        guard before != after else { continue }
        let date = Date(timeIntervalSince1970: c.at * 60)
            .formatted(Date.FormatStyle(timeZone: home.tz).weekday(.abbreviated).day().month(.abbreviated))
        let change = after == 0 ? "no shared time" : after < before ? "overlap shrinks to \(dur(after))" : "overlap grows to \(dur(after))"
        return "\(date): \(c.person.shortName) clocks change, \(change)"
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
    var occasion: (icon: String, text: String)? = nil
    var time: Double = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let (label, dot) = status(person, local)
        // Every row keeps the same layout; at large sizes the city shrinks and the clock (fixed size) stays whole.
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
                SkyBackground(person: person, minutes: minutes, insets: g.safeAreaInsets, time: time).ignoresSafeArea()
            }
        }
        .overlay { Color.black.opacity(dimmed ? 0.5 : 0).allowsHitTesting(false) }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func content(label: String, dot: RGB, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
            // One circle size in both layouts, so names line up whichever layout a row picks.
            Avatar(person: person, size: 32).padding(.top, compact ? 0 : 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(person.city).sf(compact ? 18 : 22, .semibold).lineLimit(1).minimumScaleFactor(0.5)
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .sf(compact ? 15 : 17, .semibold)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                // One quiet line: who they are, then what they're doing. No pills, so the sky does the talking.
                // When a photo and a long city leave no room, the label goes first; the photo already says who.
                ViewThatFits(in: .horizontal) {
                    meta(label: label, dot: dot, compact: compact, withLabel: true)
                    meta(label: label, dot: dot, compact: compact, withLabel: false)
                }
                .padding(.top, compact ? 0 : 4)
            }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: compact ? 0 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // The clock is the point of the row: it never truncates; the city gives way instead.
                    Text(clock(local)).sf(compact ? 38 : 50, .light).tracking(compact ? -0.6 : -1.2).monospacedDigit()
                        .contentTransition(.numericText(value: Double(local.h * 60 + local.m)))
                        .animation(animateDigits ? .easeOutStrong(0.25) : nil, value: local.m)
                    Text(ampm(local.h)).sf(compact ? 13 : 15, .medium)
                }
                .fixedSize()
                if !person.isHome { Text(relative).sf(12, .medium).opacity(0.8).minimumScaleFactor(0.75) }
            }
            .lineLimit(1)
        }
        .padding(.vertical, compact ? 6 : 12)
    }

    private func meta(label: String, dot: RGB, compact: Bool, withLabel: Bool) -> some View {
        HStack(spacing: 6) {
            // The circle already says work or personal, so the label is plain text here.
            if withLabel && !compact && !person.label.isEmpty {
                Text(person.label)
                Text("·").opacity(0.6)
            }
            Circle().fill(Color(dot)).frame(width: 6, height: 6)
            Text(label)
            if let occasion {
                Text("·").opacity(0.6)
                Label(occasion.text, systemImage: occasion.icon).labelStyle(TightLabel()).foregroundStyle(Color.sun)
            }
        }
        .sf(compact ? 12 : 14, .medium).opacity(0.9).lineLimit(1).fixedSize()
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
    var mode: Person.Kind? = nil

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, bandH = size.height - 20
            let span = cx / pxPerMinute + 30
            var a = ((m - span) / 15).rounded(.down) * 15
            while a <= m + span {
                let xp = cx + (a - m) * pxPerMinute
                let free = team.filter { $0.free(Local($0.tz, a), with: mode) }.count
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
                    ctx.draw(Text(label).font(.sf(11, mid ? .bold : .medium)).foregroundStyle(.white.opacity(mid ? 1 : 0.6)),
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
                ctx.draw(Text("\(c.person.city) \(shift)").font(.sf(10, .semibold)).foregroundStyle(Color.sun),
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

/// Icon and title close together, for the small relationship label on each band.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}
