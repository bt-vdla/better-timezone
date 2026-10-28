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

extension View {
    /// One line that shrinks to fit its width but always keeps its full-size height: a hidden copy sets the size.
    func steadyLine(minimumScale: CGFloat, alignment: Alignment = .leading) -> some View {
        lineLimit(1).hidden().overlay(alignment: alignment) { lineLimit(1).minimumScaleFactor(minimumScale) }
    }
}

/// Weather-style legibility for white type over a live sky.
extension View {
    func skyLegible() -> some View { compositingGroup().shadow(color: .black.opacity(0.25), radius: 8, y: 1) }
}

/// `.plain`, but the whole label is the target, padding and glass included, not just its text and icons.
struct WholeButton: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) { configuration.label.contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == WholeButton {
    static var whole: WholeButton { WholeButton() }
}

struct PressScale: ButtonStyle {
    var scale = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOutStrong(0.12), value: configuration.isPressed)
    }
}

enum Sheet: Identifiable {
    case people, person(UUID), planner, search
    var id: String {
        switch self {
        case .people: "people"
        case .search: "search"
        case .planner: "planner"
        case .person(let id): id.uuidString
        }
    }
}

struct SkiesView: View {
    let people: People
    @State private var model = Scrubber()
    @State private var sheet: Sheet?
    /// What Ask opens with, when something asked for it (the clock-change heads-up).
    @State private var askFirst = ""
    @State private var width = 390.0
    @State private var holidays = Holidays()
    @AppStorage("coached") private var coached = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Every frame while the sky moves, otherwise on the minute; night skies twinkle on their own clocks.
        SkyClock(moving: model.isMoving) { date in
            screen(m: model.minutes(at: date), now: nowMinutes(date))
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
            case .search:
                SearchSheet(people: people, model: model, query: $askFirst) { id in
                    // Let the search sheet close before the person's page opens in its place.
                    Task { try? await Task.sleep(for: .milliseconds(350)); sheet = .person(id) }
                }
            }
        }
        .task { await people.fillRegions() }
        .onChange(of: scenePhase, initial: true) { if scenePhase == .active { Calendars.shared.load() } }
        .task(id: people.list) { await Nudges.schedule(people.list) }
        #if os(iOS)
        .task { LiveWindow.tidy() }
        #endif
        .onChange(of: people.focus, initial: true) {
            guard let id = people.focus else { return }
            people.focus = nil
            sheet = .person(id)
        }
    }

    #if os(macOS)
    private func watchScrollWheel() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            MainActor.assumeIsolated {
                guard sheet == nil, e.window?.isKeyWindow == true, e.window !== NotchController.shared.panel else { return }
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

        // Color.clear answers the header and dock's size questions without asking the rows, so while the header ticks
        // every frame the rows are laid out once, at one size, instead of re-measured for every probe.
        return Color.clear.overlay { VStack(spacing: 0) {
            ForEach(people.visible) { p in
                let l = p.isHome ? h : Local(p.tz, m)
                // Worked out here, not in the row: a calendar loading changes it without changing the row's inputs.
                SkyRow(person: p, minutes: m, local: l, home: h, status: status(p, l),
                       dimmed: !people.everyone && !people.team.contains(p), picked: !people.picked.isEmpty && people.picked.contains(p.id),
                       animateDigits: !model.isMoving, occasion: occasion(p, l))
                    .contentShape(Rectangle())
                    .onTapGesture { people.toggle(p) }
                    .contextMenu {
                        Button("Open \(p.shortName)", systemImage: "arrow.up.left.and.arrow.down.right") { sheet = .person(p.id) }
                        if !p.isHome {
                            Button("Plan with \(p.shortName) only", systemImage: "person.crop.circle") { people.picked = [p.id] }
                        }
                        ForEach(p.tagObjects) { t in
                            Button("Show \(t.name)", systemImage: "tag") { people.setScope(t.id) }
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
        } }
        .animation(.easeOutStrong(0.2), value: people.picked)
        .animation(reduceMotion ? .easeOutStrong(0.2) : .spring(response: 0.4, dampingFraction: 1), value: people.scope)
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
        // Nothing here changes height while scrubbing (the Now button, longer times and dates), or the rows below jump.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(when)
                        .sf(34, .semibold).tracking(-0.5).monospacedDigit()
                        .steadyLine(minimumScale: 0.5)
                        .accessibilityAddTraits(.updatesFrequently)
                    // ponytail: String, not Text(_:format:), which swaps in the device time zone.
                    // Short names while the Now button narrows the column: "Wed, 28 Oct".
                    Text(Date(timeIntervalSince1970: m * 60)
                        .formatted(Date.FormatStyle(timeZone: home.tz).weekday(showNow ? .abbreviated : .wide).day()
                            .month(showNow ? .abbreviated : .wide)))
                        .sf(15, .medium).opacity(0.8)
                        .steadyLine(minimumScale: 0.7)
                }
                .skyLegible()
                // Before the Spacer gets any: otherwise they split the free width and "In 16h 25m" truncates.
                .layoutPriority(1)
                Spacer()
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        if showNow {
                            Button(action: model.goNow) {
                                Text("Now").sf(15, .semibold).fixedSize()
                                    .padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 40)
                            }
                            .foregroundStyle(Color(hex: 0x1D1603))
                                .glassEffect(.regular.tint(.sun).interactive(), in: Capsule())
                                .glassEffectID("now", in: glass)
                                .buttonStyle(.whole)
                        }
                        Button { askFirst = ""; sheet = .search } label: {
                            Image(systemName: "magnifyingglass").font(.sf(15, .semibold)).frame(width: 40, height: 40)
                        }
                        .buttonStyle(.whole)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .glassEffectID("search", in: glass)
                        .keyboardShortcut("f", modifiers: .command)
                        .accessibilityLabel("Search people, or type a time")
                        ScopeMenu(people: people)
                            .glassEffectID("scope", in: glass)
                        Button { sheet = .people } label: {
                            Image(systemName: "person.2.fill").font(.sf(15, .semibold)).frame(width: 40, height: 40)
                        }
                        .buttonStyle(.whole)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .glassEffectID("people", in: glass)
                        .accessibilityLabel("People")
                    }
                }
                .animation(reduceMotion ? .easeOutStrong(0.2) : .spring(response: 0.35, dampingFraction: 1), value: showNow)
            }
            // A clock change in the next fortnight that moves someone's gap to you: tap to see what it does.
            // Full width, so the Now button never rewraps it.
            if let heads = Clocks.headsUp(people.list, now: nowMinutes()) {
                Button {
                    askFirst = heads.ask
                    sheet = .search
                } label: {
                    Label(heads.text, systemImage: "clock.arrow.2.circlepath").labelStyle(TightLabel())
                        .sf(13, .semibold).foregroundStyle(Color.sun).lineLimit(2).multilineTextAlignment(.leading)
                }
                .buttonStyle(.whole)
                .skyLegible()
                .accessibilityHint("Shows how it changes the time between you")
            }
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
                #if os(iOS)
                .contextMenu {
                    if let w = people.runs(from: dayStart(people.home.tz, now)).first(where: { $0.upperBound > now }) {
                        Button("Count down on Lock Screen", systemImage: "timer") {
                            LiveWindow.start(who: liveWho, talk: people.mode == .personal, window: w)
                        }
                    }
                }
                #endif

                if !people.everyone {
                    Button { people.setScope(nil) } label: {
                        Image(systemName: "xmark").font(.sf(13, .bold)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.whole)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Include everyone")
                }
                Button { sheet = .planner } label: {
                    Image(systemName: "calendar").font(.sf(14, .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.whole)
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
                .accessibilityValue("\(people.home.city) \(hm(h)), \(when)")
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

    /// Who a Live Activity names: the tag, everyone, or the people picked.
    private var liveWho: String {
        if let t = people.scopeTag, people.team.count == people.visible.count { return t.name }
        if people.everyone { return "everyone" }
        return ListFormatter.localizedString(byJoining: people.team.filter { !$0.isHome }.map(\.shortName))
    }

    private var who: String {
        if people.everyone { return "Everyone" }
        if let t = people.scopeTag, people.team.count == people.visible.count { return "You and \(t.name)" }
        let others = people.team.filter { !$0.isHome }.map(\.shortName)
        return others.count == 1 ? "You and \(others[0])" : others.count == 2 ? "You, \(others[0]) and \(others[1])" : "You and \(others.count) others"
    }

    /// The pill: when, big; who, small; and a clock-change warning only when one matters.
    private func overlap(_ m: Double, now: Double) -> (title: String, subtitle: String, target: Double?, note: String?) {
        let home = people.home
        let runs = people.runs(from: dayStart(home.tz, m))
        // From the real time, not the scrubbed one: a note appearing mid-scrub would resize the dock and move the rows.
        let note = clockNote(people, after: now)
        let verb = people.mode == .personal ? "can talk" : "free"

        if let inside = runs.first(where: { $0.lowerBound <= m && m < $0.upperBound }) {
            let e = Local(home.tz, inside.upperBound)
            return ("Now until \(hm(e))", "\(who) \(verb)", nil, note)
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
    return ampm(a.h) == ampm(b.h) ? "\(clock(a))–\(hm(b))" : "\(hm(a))–\(hm(b))"
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
    let status: (String, RGB)
    var dimmed = false, picked = false, animateDigits = true
    var occasion: (icon: String, text: String)? = nil

    var body: some View {
        let (label, dot) = status
        // The digits ride on top of a same-width stand-in in RowLabels, which is Equatable: scrubbing changes one
        // Text per row instead of re-running ViewThatFits (both layouts, three meta lines each) every frame.
        RowLabels(person: person, label: label, dot: dot, picked: picked, occasion: occasion.map { [$0.icon, $0.text] },
                  relative: person.isHome ? nil : relative, ampm: TimeFormat.twentyFour ? nil : ampm(local.h),
                  placeholder: clock(local).replacing(/\d/, with: "0"))
        .equatable()
        .overlayPreferenceValue(ClockSlot.self) { slot in
            if let slot {
                GeometryReader { g in
                    let r = g[slot.bounds]
                    Text(clock(local)).clockFont(compact: slot.compact)
                        .contentTransition(.numericText(value: Double(local.h * 60 + local.m)))
                        .animation(animateDigits ? .easeOutStrong(0.25) : nil, value: local.m)
                        .frame(width: r.width, height: r.height, alignment: .trailing)
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
        .foregroundStyle(.white)
        .skyLegible()
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { g in
                SkyBackground(person: person, minutes: minutes, insets: g.safeAreaInsets, twinkle: true).ignoresSafeArea()
            }
        }
        .overlay { Color.black.opacity(dimmed ? 0.5 : 0).allowsHitTesting(false) }
        .clipped()
        .accessibilityElement(children: .combine)
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

/// A row's name, status and clock layout: everything that holds still while the clock ticks.
private struct RowLabels: View, Equatable {
    let person: Person, label: String, dot: RGB, picked: Bool
    let occasion: [String]?
    let relative: String?, ampm: String?, placeholder: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(ShowBy.key, store: .skies) private var showBy: ShowBy = .name
    /// The full layout's natural height, measured once off-screen, and the row's height.
    @State private var full: CGFloat?
    @State private var room = CGFloat.infinity

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.person == b.person && a.label == b.label && a.dot == b.dot && a.picked == b.picked && a.occasion == b.occasion
            && a.relative == b.relative && a.ampm == b.ampm && a.placeholder == b.placeholder
    }

    var body: some View {
        // Every row keeps the same layout; at large sizes the city shrinks and the clock (fixed size) stays whole.
        // ViewThatFits's rule, decided once instead of re-measuring both layouts on every frame of a scrub.
        let compact = full.map { $0 > room } ?? false
        // minHeight 0: the row takes its share of the screen whatever its content, so `room` is what's offered.
        content(compact: compact)
            .frame(minHeight: 0, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
            .background {
                if full == nil {
                    content(compact: false, measuring: true).fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0 }
                }
            }
            .onChange(of: typeSize) { full = nil }
    }

    private func content(compact: Bool, measuring: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
            // One circle size in both layouts, so names line up whichever layout a row picks.
            Avatar(person: person, size: 32).padding(.top, compact ? 0 : 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(person.title(showBy)).sf(compact ? 18 : 22, .semibold).lineLimit(1).minimumScaleFactor(0.5)
                    TagDots(person: person, size: compact ? 6 : 7)
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .sf(compact ? 15 : 17, .semibold)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                // One quiet line: who they are, then what they're doing. No pills, so the sky does the talking.
                // When a photo and a long city leave no room, the label goes first; the photo already says who.
                // Drop the code first, then let a long holiday name trail off: the row never grows past the screen.
                ViewThatFits(in: .horizontal) {
                    meta(compact: compact, withLabel: true)
                    meta(compact: compact, withLabel: false)
                    meta(compact: compact, withLabel: false, squeeze: true)
                }
                .padding(.top, compact ? 0 : 4)
            }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: compact ? 0 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // The clock is the point of the row: it never truncates; the city gives way instead.
                    Text(placeholder).clockFont(compact: compact)
                        .hidden()
                        .anchorPreference(key: ClockSlot.self, value: .bounds) { measuring ? nil : ClockSlot.Slot(bounds: $0, compact: compact) }
                    if let ampm { Text(ampm).sf(compact ? 13 : 15, .medium) }
                }
                .fixedSize()
                // Measured as if every row had this line, so all rows pick the same layout.
                if let relative = measuring ? relative ?? " " : relative {
                    Text(relative).sf(12, .medium).opacity(0.8).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, compact ? 6 : 12)
    }

    private func meta(compact: Bool, withLabel: Bool, squeeze: Bool = false) -> some View {
        HStack(spacing: 6) {
            // The secondary label (the airport code, or the name when codes lead), then what they're doing.
            if withLabel {
                Text(person.tag(showBy)).monospaced(showBy != .code)
                Text("·").opacity(0.6)
            }
            Circle().fill(Color(dot)).frame(width: 6, height: 6)
            Text(label).fixedSize()
            if let occasion {
                Text("·").opacity(0.6)
                Label(occasion[1], systemImage: occasion[0]).labelStyle(TightLabel()).foregroundStyle(Color.sun)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: !squeeze, vertical: false)
            }
        }
        .sf(compact ? 12 : 14, .medium).opacity(0.9).lineLimit(1)
        .fixedSize(horizontal: !squeeze, vertical: false)
    }
}

extension Text {
    /// Digits are all one width, so "0:00" holds the place of "4:28" exactly.
    func clockFont(compact: Bool) -> some View {
        sf(compact ? 38 : 50, .light).tracking(compact ? -0.6 : -1.2).monospacedDigit().fixedSize()
    }
}

/// Where the row's chosen layout put its clock, and at which size.
private struct ClockSlot: PreferenceKey {
    struct Slot { let bounds: Anchor<CGRect>, compact: Bool }
    static var defaultValue: Slot? { nil }
    static func reduce(value: inout Slot?, nextValue: () -> Slot?) { value = value ?? nextValue() }
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
                    let label = mid ? Calendar.current.shortWeekdaySymbols[l.wd] : "\(hourText(l.h))"
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

#if os(iOS)
import ActivityKit

/// The next shared window on the Lock Screen and in the Dynamic Island: one at a time, gone once it closes.
enum LiveWindow {
    static func start(who: String, talk: Bool, window: ClosedRange<Double>) {
        let state = WindowActivity.ContentState(start: Date(timeIntervalSince1970: window.lowerBound * 60),
                                                end: Date(timeIntervalSince1970: window.upperBound * 60))
        Task {
            for a in Activity<WindowActivity>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            _ = try? Activity.request(attributes: WindowActivity(who: who, talk: talk),
                                      content: ActivityContent(state: state, staleDate: state.end))
        }
    }

    /// Ends any whose window has closed (they can't end themselves without a server).
    static func tidy() {
        Task {
            for a in Activity<WindowActivity>.activities where a.content.state.end < .now {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
