#if os(macOS)
import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey

/// One global shortcut through Carbon's hot keys: works sandboxed, needs no Accessibility or Input Monitoring.
@MainActor final class HotKey {
    static let shared = HotKey()
    var action: () -> Void = {}
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    static let defaultCode = UInt32(kVK_ANSI_S)
    static let defaultMods = UInt32(controlKey | optionKey)

    /// Registers the saved shortcut (⌃⌥S unless changed in Settings).
    func registerSaved() {
        let d = UserDefaults.standard
        let code = d.object(forKey: "hotkey.code") as? Int
        let mods = d.object(forKey: "hotkey.mods") as? Int
        register(code: code.map(UInt32.init) ?? Self.defaultCode, mods: mods.map(UInt32.init) ?? Self.defaultMods)
    }

    func register(code: UInt32, mods: UInt32) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.shared.action() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x534B_4945), id: 1),  // "SKIE"
                            GetApplicationEventTarget(), 0, &ref)
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }
}

// MARK: - Panel

/// Borderless, never activates the app, can still take Esc and arrow keys while open.
final class NotchPanel: NSPanel {
    var onKey: (UInt16) -> Bool = { _ in false }
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { if !onKey(event.keyCode) { super.keyDown(with: event) } }
}

/// What the notch view draws. The shape and its content open separately, so the shape can lead.
@MainActor @Observable final class NotchState {
    var shapeOpen = false
    var contentShown = false
    /// True while the shape springs open or shut: the content's clock holds still so every frame goes to the motion.
    var moving = false
    /// Fully closed with nothing to say: Skies draws nothing and the hardware notch is left as it is.
    var resting = true
    /// The hardware notch: its width (0 on displays without one) and the menu bar's height beside it.
    var notch = CGSize(width: 0, height: 24)
    let model = Scrubber()
}

/// Owns the panel over the notch, the hotkey, and the open/close choreography.
@MainActor final class NotchController {
    static let shared = NotchController()
    let state = NotchState()
    private(set) var panel: NotchPanel?
    private var monitors: [Any] = []
    private var closing: Task<Void, Never>?

    static let size = CGSize(width: 780, height: 280)

    /// One place for the notch's motion: a bouncy open, a quicker settle on close.
    /// The one knob for how lively it feels: higher bounce, more overshoot (0.35 ≈ 7% past and back).
    static let openSpring = Animation.spring(duration: 0.55, bounce: 0.35)
    static let closeSpring = Animation.spring(duration: 0.38, bounce: 0.2)
    static let earSpring = Animation.spring(duration: 0.4, bounce: 0.25)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func start() {
        let panel = NotchPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.onKey = { [weak self] code in self?.key(code) ?? false }
        let host = NSHostingView(rootView: NotchView(state: state, people: People.shared))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        place()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.place() }
        }
        HotKey.shared.action = { NotchController.shared.toggle() }
        HotKey.shared.registerSaved()
    }

    /// Top centre of the display with the notch (or the main display), flush with the top edge.
    func place() {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0, right = screen.auxiliaryTopRightArea?.width ?? 0
        let hasNotch = screen.safeAreaInsets.top > 0 && left > 0
        state.notch = CGSize(width: hasNotch ? screen.frame.width - left - right : 0,
                             height: hasNotch ? screen.safeAreaInsets.top : NSStatusBar.system.thickness)
        let f = screen.frame
        panel.setFrame(CGRect(x: f.midX - Self.size.width / 2, y: f.maxY - Self.size.height,
                              width: Self.size.width, height: Self.size.height), display: true)
    }

    func toggle() { state.shapeOpen ? close() : open() }

    func open() {
        guard let panel, !state.shapeOpen else { return }
        closing?.cancel()
        state.model.jumpNow()
        place()
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        let reduce = Self.reduceMotion
        // The shape leads, like the notch growing; the content follows a beat later on the same spring.
        settle(after: 0.7)
        state.resting = false
        withAnimation(reduce ? .easeOutStrong(0.2) : Self.openSpring) { state.shapeOpen = true }
        withAnimation(reduce ? .easeOutStrong(0.2) : Self.openSpring.delay(0.06)) { state.contentShown = true }
        watchOutside()
    }

    func close() {
        guard let panel, state.shapeOpen else { return }
        // Closing is quicker: content out first, then the shape tucks back into the notch.
        let reduce = Self.reduceMotion
        settle(after: 0.45)
        withAnimation(.easeOutStrong(reduce ? 0.2 : 0.12)) { state.contentShown = false }
        withAnimation(reduce ? .easeOutStrong(0.2) : Self.closeSpring.delay(0.04)) { state.shapeOpen = false }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        closing = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, !state.shapeOpen else { return }
            state.resting = true
            panel.ignoresMouseEvents = true
            panel.resignKey()
        }
    }

    private var settling: Task<Void, Never>?

    /// Holds the content's clock still until the spring has settled.
    private func settle(after seconds: Double) {
        state.moving = true
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            state.moving = false
        }
    }

    /// Clicks anywhere else close it; two-finger swipes over it scrub time.
    private func watchOutside() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { NotchController.shared.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { e in
            let ours = e.window === NotchController.shared.panel
            let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY, precise = e.hasPreciseScrollingDeltas
            let used = MainActor.assumeIsolated { () -> Bool in
                let c = NotchController.shared
                guard ours, c.state.shapeOpen else { return false }
                if precise { c.state.model.scroll(by: abs(dx) >= abs(dy) ? dx : dy, width: Self.size.width) }
                else if dy != 0 { c.state.model.step(dy > 0 ? -15 : 15) }
                return true
            }
            return used ? nil : e
        }) { monitors.append(m) }
    }

    private func key(_ code: UInt16) -> Bool {
        switch Int(code) {
        case kVK_Escape: close()
        case kVK_LeftArrow: state.model.step(-15)
        case kVK_RightArrow: state.model.step(15)
        case kVK_Space: state.model.goNow()
        default: return false
        }
        return true
    }
}

// MARK: - Main window on demand

/// The full skies window, opened from the notch or the menu bar; Skies has no Dock icon.
@MainActor final class MainWindow {
    static let shared = MainWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 390, height: 800),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentMinSize = CGSize(width: 340, height: 640)
            w.contentView = NSHostingView(rootView: RootView())
            w.setFrameAutosaveName("SkiesMain")
            if !w.setFrameUsingName("SkiesMain") { w.center() }
            window = w
        }
        NotchController.shared.close()
        // Skies has no Dock icon, so macOS may decline a plain activate() when it comes from the notch;
        // ordering the window front regardless keeps "Open" and "Edit…" from landing behind other apps.
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }
}

final class MacDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NotchController.shared.start()
            Task { await Nudges.schedule(People.shared.list) }
            if !UserDefaults.standard.bool(forKey: "onboarded") { MainWindow.shared.show() }
            #if DEBUG
            // `-SkiesOpenNotch YES` opens the notch at launch, for screenshots without touching the keyboard.
            // `-SkiesEditPerson N` opens the Nth person's page in the main window, the same route as the notch's Edit.
            if let n = UserDefaults.standard.string(forKey: "SkiesEditPerson").flatMap(Int.init), People.shared.list.indices.contains(n) {
                People.shared.focus = People.shared.list[n].id
                MainWindow.shared.show()
            }
            if UserDefaults.standard.bool(forKey: "SkiesOpenNotch") {
                Task { try? await Task.sleep(for: .seconds(1)); NotchController.shared.open() }
            }
            #endif
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { MainWindow.shared.show() }
        return false
    }
}

// MARK: - The view

/// The notch's own silhouette: concave shoulders that flare into the screen's top edge, rounded
/// bottom corners. It is `2 × top` wider than its body; the extra width is the flare.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let t = min(top, w / 4, h), b = min(bottom, (w - 2 * t) / 2, h - t)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - b))
        p.addQuadCurve(to: CGPoint(x: t + b, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - b), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct NotchView: View {
    let state: NotchState
    let people: People
    @Environment(\.openURL) private var openURL

    /// Up to five people as side-by-side skies; more than that become a two-column list of one-line rows.
    private var listed: Bool { people.visible.count > 5 }
    private var openWidth: CGFloat {
        listed ? 640 : min(NotchController.size.width - 40, max(560, CGFloat(people.visible.count) * 140 + 36))
    }
    /// Strip beside the notch, the skies, the tape. A list grows a row per two people.
    private var openHeight: CGFloat {
        let skies = listed ? CGFloat((people.visible.count + 1) / 2) * 34 - 6 : 64
        return max(state.notch.height, 24) + 6 + skies + 6 + 34 + 6
    }

    var body: some View {
        let model = state.model
        TimelineView(.animation(minimumInterval: state.shapeOpen ? (model.isMoving ? nil : 1.0 / 30) : 30, paused: state.moving)) { ctx in
            let m = model.minutes(at: ctx.date), now = nowMinutes(ctx.date)
            let soon = state.shapeOpen ? nil : countdown(now)
            let earW: CGFloat = soon == nil ? 0 : 74
            let closed = CGSize(width: state.notch.width == 0 && soon == nil ? 0 : state.notch.width + earW * 2,
                                height: state.notch.width == 0 && soon == nil ? 0 : state.notch.height)
            let panelBody = state.shapeOpen ? CGSize(width: openWidth, height: openHeight) : closed
            // Resting exactly on the hardware notch (its own ~6 pt flare and ~10 pt corners) so the open starts
            // seamlessly, then growing into soft shoulders; the countdown ears sit in between.
            let flare: CGFloat = state.shapeOpen ? 18 : soon != nil ? 10 : 6
            let size = CGSize(width: panelBody.width + (panelBody.width == 0 ? 0 : 2 * flare), height: panelBody.height)
            let radius: CGFloat = state.shapeOpen ? 32 : soon != nil ? min(14, closed.height * 0.45) : min(10, closed.height / 2)
            let shape = NotchShape(top: closed.height == 0 && !state.shapeOpen ? 0 : flare, bottom: radius)
            let hidden = state.resting && soon == nil

            ZStack(alignment: .top) {
                shape
                    .fill(.black)
                    .frame(width: size.width, height: size.height)
                    .opacity(hidden ? 0 : 1)
                    .animation(NotchController.reduceMotion ? .easeOutStrong(0.2) : NotchController.earSpring, value: soon != nil)
                    .overlay(alignment: .top) {
                        if let soon, !state.shapeOpen { ears(soon) }
                    }
                    .overlay(alignment: .top) {
                        content(m: m, now: now, time: ctx.date.timeIntervalSinceReferenceDate)
                            .frame(width: openWidth, height: openHeight)
                            .scaleEffect(state.contentShown || NotchController.reduceMotion ? 1 : 0.9, anchor: .top)
                            .animation(NotchController.reduceMotion ? nil : NotchController.openSpring.delay(0.06), value: state.contentShown)
                            .opacity(state.contentShown ? 1 : 0)
                            .blur(radius: state.contentShown ? 0 : 6)
                            .animation(.easeOutStrong(state.contentShown ? 0.2 : 0.12).delay(state.contentShown ? 0.06 : 0), value: state.contentShown)
                            .allowsHitTesting(state.contentShown)
                    }
                    .clipShape(shape)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    // MARK: Closed: only when it matters

    /// Minutes until the selected team's next shared window opens, when that's within the hour.
    private func countdown(_ now: Double) -> Double? {
        let next = people.runs(from: dayStart(people.home.tz, now)).first { $0.lowerBound > now }
        guard let start = next?.lowerBound, start - now <= 60 else { return nil }
        return start - now
    }

    private func ears(_ minutes: Double) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(Color.mint).frame(width: 7, height: 7)
                Text(people.mode == .personal ? "Talk" : "Free").font(.sf(12, .semibold))
            }
            .frame(width: 64)
            Spacer(minLength: state.notch.width)
            Text("in \(dur(max(1, minutes)))").font(.sf(12, .semibold)).monospacedDigit().foregroundStyle(Color.mint)
                .frame(width: 64)
        }
        .padding(.horizontal, 6)
        .frame(height: state.notch.height)
        .transition(.opacity)
    }

    // MARK: Open

    private func content(m: Double, now: Double, time: Double) -> some View {
        let home = people.home
        let h = Local(home.tz, m)
        let delta = (m - now).rounded()
        let when = abs(delta) < 1 ? "Right now" : delta > 0 ? "In \(dur(delta))" : "\(dur(delta)) ago"
        let date = Date(timeIntervalSince1970: m * 60).formatted(Date.FormatStyle(timeZone: home.tz).weekday(.abbreviated).day())
        return VStack(spacing: 6) {
            // The strip beside the notch carries what used to be two rows: when on the left, the overlap on the right.
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(when).font(.sf(13, .semibold)).monospacedDigit()
                    Text(date).font(.sf(12, .medium)).opacity(0.6)
                    if abs(delta) >= 1 {
                        Button("Now") { state.model.goNow() }
                            .font(.sf(11, .semibold)).foregroundStyle(Color(hex: 0x1D1603))
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Color.sun, in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: state.notch.width + 24)
                overlap(m: m)
            }
            .padding(.horizontal, 20)
            .frame(height: max(state.notch.height, 24))

            Group {
                if listed {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) { skies(m: m, time: time) }
                } else {
                    HStack(spacing: 8) { skies(m: m, time: time) }
                }
            }
            .padding(.horizontal, 14)

            Tape(m: m, now: now, hourKey: Int(((m + Double(h.off)) / 60).rounded(.down)),
                 home: home, team: people.team, all: people.list, mode: people.mode)
                .frame(height: 34)
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { state.model.dragChanged($0, width: openWidth) }
                    .onEnded { state.model.dragEnded($0) })
        }
        .padding(.bottom, 6)
    }

    private func skies(m: Double, time: Double) -> some View {
        ForEach(people.visible) { p in
            NotchTile(person: p, minutes: m, time: time, row: listed,
                      dimmed: !people.everyone && !people.team.contains(p),
                      picked: !people.picked.isEmpty && people.picked.contains(p.id)) { reach(p) }
                .contextMenu { menu(p) }
        }
    }

    /// Just the time: who's included is already shown by which tiles are lit.
    private func overlap(m: Double) -> some View {
        let home = people.home
        let runs = people.runs(from: dayStart(home.tz, m))
        let verb = (people.scopeTag.map { "\($0.name): " } ?? "") + (people.mode == .personal ? "Talk" : "Free")
        let text: String, target: Double?
        if let inside = runs.first(where: { $0.lowerBound <= m && m < $0.upperBound }) {
            let e = Local(home.tz, inside.upperBound)
            (text, target) = ("\(verb) now, until \(clock(e)) \(ampm(e.h))", nil)
        } else if let r = runs.first(where: { $0.lowerBound > m }) {
            let days = Local(home.tz, r.lowerBound).dn - Local(home.tz, m).dn
            let day = days == 0 ? "" : days == 1 ? "tomorrow " : Calendar.current.shortWeekdaySymbols[Local(home.tz, r.lowerBound).wd] + " "
            (text, target) = ("\(verb) \(day)\(timeRange(r, home))", r.lowerBound)
        } else {
            (text, target) = ("No shared time this week", nil)
        }
        return Button { if let target { state.model.springTo(target, response: 0.5) } } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.mint).frame(width: 6, height: 6)
                Text(text).font(.sf(12, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if target != nil { Image(systemName: "arrow.right").font(.sf(10, .bold)).opacity(0.6) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(target != nil ? "Jump to that time" : "")
    }

    // MARK: Actions

    /// A tile click reaches them by their favourite way; without a contact it picks them for the overlap.
    private func reach(_ p: Person) {
        if let ch = p.contact?.preferred, let url = ch.url {
            openURL(url)
            NotchController.shared.close()
        } else {
            people.toggle(p)
        }
    }

    @ViewBuilder private func menu(_ p: Person) -> some View {
        if let c = p.contact {
            ForEach(c.numbers.isEmpty ? [] : [Channel.Method.call, .facetime, .facetimeAudio, .message, .whatsapp], id: \.self) { m in
                Button("\(m.title) \(c.firstName)", systemImage: m.icon) {
                    if let url = Channel(method: m, value: c.numbers[0].value).url { openURL(url) }
                }
            }
            Divider()
        }
        if !p.isHome {
            Button(people.picked.contains(p.id) ? "Leave out of the plan" : "Include in the plan", systemImage: "person.crop.circle.badge.checkmark") {
                people.toggle(p)
            }
        }
        if !people.usedTags.isEmpty {
            Picker("Show", selection: Binding(get: { people.scope }, set: { people.setScope($0) })) {
                Text("Everyone").tag(nil as String?)
                ForEach(people.usedTags) { t in Text(t.name).tag(t.id as String?) }
            }
        }
        Button("Edit \(p.name)…", systemImage: "pencil") {
            people.focus = p.id
            MainWindow.shared.show()
        }
        Button("Open Skies", systemImage: "macwindow") { MainWindow.shared.show() }
    }
}

/// One person as a small live sky. As a tile: who (name, code, status dot), then their time, big.
/// As a row (when there are more than five people): all on one line, status in words. The status words
/// otherwise live in the tooltip and VoiceOver; the dot's colour carries them at a glance.
struct NotchTile: View {
    let person: Person, minutes: Double, time: Double
    var row = false
    var dimmed = false, picked = false
    let action: () -> Void
    @AppStorage(ShowBy.key, store: .skies) private var showBy: ShowBy = .name

    var body: some View {
        let l = Local(person.tz, minutes)
        let (label, dot) = status(person, l)
        Button(action: action) {
            Group {
                if row {
                    HStack(spacing: 6) {
                        Avatar(person: person, size: 16)
                        who
                        Text("·").opacity(0.5)
                        Text(label).font(.sf(11, .medium)).opacity(0.8).lineLimit(1).layoutPriority(-1)
                        Spacer(minLength: 4)
                        time(l, size: 15)
                    }
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Avatar(person: person, size: 16)
                            who
                            Spacer(minLength: 2)
                            if picked { Image(systemName: "checkmark.circle.fill").font(.sf(11, .semibold)) }
                            else { Circle().fill(Color(dot)).frame(width: 6, height: 6) }
                        }
                        time(l, size: 22)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
                }
            }
            .skyLegible()
            .background { SkyBackground(person: person, minutes: minutes, time: time, flare: 0, discs: false) }
            .overlay { Color.black.opacity(dimmed ? 0.5 : 0) }
            .clipShape(RoundedRectangle(cornerRadius: row ? 9 : 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: row ? 9 : 14, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.97))
        .help("\(person.city) · \(label)\(person.contact?.preferred.map { " · click to \($0.method.title.lowercased()) \(person.name)" } ?? "")")
        .accessibilityLabel("\(person.name), \(person.city), \(clock(l)) \(ampm(l.h)), \(label)")
    }

    /// The big label and its quiet tag: "Mom VTZ" by default, or "VTZ Mom" when codes lead.
    private var who: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(person.title(showBy)).font(.sf(11, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            TagDots(person: person, size: 5)
            Text(person.tag(showBy)).font(.system(size: 10, weight: .medium, design: showBy == .code ? .default : .monospaced))
                .opacity(0.7).lineLimit(1).fixedSize()
        }
    }

    private func time(_ l: Local, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(clock(l)).font(.sf(size, .light)).monospacedDigit()
            Text(ampm(l.h)).font(.sf(size * 0.45, .medium))
        }
        .fixedSize()
    }
}

// MARK: - Settings

struct SkiesSettings: View {
    @AppStorage(ShowBy.key, store: .skies) private var showBy: ShowBy = .name
    var body: some View {
        Form {
            LabeledContent("Open Skies in the notch") { ShortcutRecorder() }
            Picker("Show people by", selection: $showBy) {
                ForEach(ShowBy.allCases) { Text($0.title).tag($0) }
            }
            Text("Skies only opens with this shortcut, so it never clashes with other notch apps that use hover or swipes.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}

/// Click, then press the new shortcut. It needs ⌘, ⌥ or ⌃; Esc cancels.
struct ShortcutRecorder: View {
    @AppStorage("hotkey.label") private var label = "⌃⌥S"
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(recording ? "Type a shortcut…" : label) { recording ? stop() : start() }
                .monospaced(!recording)
            if label != "⌃⌥S" && !recording {
                Button("Reset") { save(code: HotKey.defaultCode, mods: HotKey.defaultMods, label: "⌃⌥S") }
            }
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let code = e.keyCode, key = e.charactersIgnoringModifiers?.uppercased() ?? ""
            MainActor.assumeIsolated {
                if Int(code) == kVK_Escape { stop(); return }
                guard !mods.intersection([.command, .option, .control]).isEmpty, !key.isEmpty else { NSSound.beep(); return }
                save(code: UInt32(code), mods: HotKey.carbon(mods), label: HotKey.symbols(mods) + key)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func save(code: UInt32, mods: UInt32, label: String) {
        UserDefaults.standard.set(Int(code), forKey: "hotkey.code")
        UserDefaults.standard.set(Int(mods), forKey: "hotkey.mods")
        self.label = label
        HotKey.shared.register(code: code, mods: mods)
    }
}
#endif
