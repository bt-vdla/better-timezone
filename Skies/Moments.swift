import SwiftUI
import EventKit
import UniformTypeIdentifiers
#if os(iOS)
import EventKitUI
#endif

// MARK: - Holidays

/// Public holidays from the holiday calendars already in your Calendar app ("Holidays in India", "UK Holidays").
/// Opt-in, because reading them needs full calendar access.
@MainActor @Observable final class Holidays {
    private(set) var granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var events: [(day: String, title: String, calendar: String)] = []

    init() { if granted { load() } }

    func enable() async {
        granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { load() }
    }

    private func load() {
        let calendars = store.calendars(for: .event).filter {
            $0.type == .subscription || $0.title.localizedCaseInsensitiveContains("holiday")
        }
        guard !calendars.isEmpty else { events = []; return }
        let start = Date.now.addingTimeInterval(-2 * 86400), end = start.addingTimeInterval(400 * 86400)
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
            .filter(\.isAllDay)
            .map { (Self.key(Calendar.current.dateComponents([.year, .month, .day], from: $0.startDate)), $0.title, $0.calendar.title) }
    }

    /// Whether any of your holiday calendars covers their country.
    func covers(_ p: Person) -> Bool { events.contains { matches($0.calendar, p) } }

    /// The holiday on their local day, if their country has one in your calendars.
    func holiday(_ p: Person, _ l: Local) -> String? {
        let day = Self.key(gmtDay(l.dn))
        return events.first { $0.day == day && matches($0.calendar, p) }?.title
    }

    func upcoming(_ p: Person, from l: Local, limit: Int = 4) -> [(day: String, title: String)] {
        let today = Self.key(gmtDay(l.dn))
        return events.filter { $0.day >= today && matches($0.calendar, p) }.sorted { $0.day < $1.day }
            .prefix(limit).map { ($0.day, $0.title) }
    }

    // ponytail: matches calendar titles by country name plus a few common short forms; extend the aliases as needed.
    private func matches(_ calendar: String, _ p: Person) -> Bool {
        guard let region = p.region else { return false }
        let aliases = ["GB": ["UK", "British"], "US": ["US", "American"], "AE": ["UAE", "Emirati"]][region] ?? []
        let names = [Locale.current.localizedString(forRegionCode: region)].compactMap { $0 } + aliases
        return names.contains { calendar.localizedCaseInsensitiveContains($0) }
    }

    private static func key(_ d: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }
}

// MARK: - Add to Calendar

/// A 30-minute call or meeting at the scrubbed moment, with everyone's local time in the notes.
@MainActor func plannedEvent(_ store: EKEventStore, team: [Person], home: Person, at minutes: Double, talk: Bool) -> EKEvent {
    let others = team.filter { !$0.isHome }
    let names = others.map { $0.contact?.firstName ?? ($0.label.isEmpty ? $0.city : $0.label) }
    let event = EKEvent(eventStore: store)
    event.title = "\(talk ? "Call with" : "Meeting with") \(names.isEmpty ? "everyone" : ListFormatter.localizedString(byJoining: names))"
    // Their shared tag's calendar, when it has one and Skies can see it (that needs full calendar access).
    if let id = Tags.calendar(for: others), let cal = store.calendar(withIdentifier: id) { event.calendar = cal }
    event.startDate = Date(timeIntervalSince1970: snap(minutes) * 60)
    event.endDate = event.startDate.addingTimeInterval(30 * 60)
    event.timeZone = home.tz
    event.notes = team.map { p in
        let l = Local(p.tz, snap(minutes))
        return "\(p.isHome ? "You" : p.label.isEmpty ? p.city : p.label) (\(p.city)): \(hm(l)) \(Calendar.current.shortWeekdaySymbols[l.wd])"
    }.joined(separator: "\n") + "\n\nPlanned with Skies"
    return event
}

#if os(iOS)
/// Apple's own event editor. On iOS 17 and later it saves without the app asking for calendar access.
/// It runs out of process, so it has to be presented modally; embedded in a SwiftUI sheet it draws nothing.
struct EventPresenter: UIViewControllerRepresentable {
    @Binding var event: EKEvent?
    let store: EKEventStore

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let event, host.presentedViewController == nil else { return }
        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = context.coordinator
        DispatchQueue.main.async { host.present(editor, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var parent: EventPresenter
        init(parent: EventPresenter) { self.parent = parent }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            parent.event = nil
            controller.dismiss(animated: true)
        }
    }
}
#endif

/// The Mac has no event editor sheet, so it saves straight to the tag's calendar, or the default one.
@MainActor func saveEvent(_ event: EKEvent, in store: EKEventStore) async -> Bool {
    if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return false }
    }
    if event.calendar == nil { event.calendar = store.defaultCalendarForNewEvents }
    return (try? store.save(event, span: .thisEvent)) != nil
}

// MARK: - Share card

/// An image of everyone's sky at one moment, made when the share sheet asks for it.
struct MomentCard: Transferable {
    let team: [Person]
    let minutes: Double
    let talk: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in try await card.png() }
    }

    @MainActor func png() throws -> Data {
        let renderer = ImageRenderer(content: MomentCardView(team: team, minutes: minutes, talk: talk))
        renderer.scale = 3
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// The same moment as plain text, for apps that don't take images.
    var text: String {
        let m = snap(minutes)
        let lines = team.map { p in
            let l = Local(p.tz, m)
            return "\(p.cardName) \(hm(l)) \(Calendar.current.shortWeekdaySymbols[l.wd])"
        }
        return "\(talk ? "Let's talk" : "Let's meet"): " + lines.joined(separator: " · ")
    }
}

/// Gradient skies rather than the Metal shader: ImageRenderer can't run a colorEffect, and a card should be still anyway.
struct MomentCardView: View {
    let team: [Person], minutes: Double, talk: Bool

    var body: some View {
        let m = snap(minutes)
        VStack(alignment: .leading, spacing: 0) {
            Text(talk ? "Let's talk" : "Let's meet")
                .font(.sf(26, .bold)).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
            ForEach(team) { p in
                let l = Local(p.tz, m)
                let sky = skyColors(sunPosition(p, m).elev)
                HStack(spacing: 12) {
                    Avatar(person: p, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.cardName).font(.sf(18, .semibold))
                        Text(p.city).font(.sf(13, .medium)).opacity(0.8)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(hm(l))").font(.sf(26, .light)).monospacedDigit()
                        Text(Calendar.current.weekdaySymbols[l.wd]).font(.sf(13, .medium)).opacity(0.8)
                    }
                }
                .padding(.horizontal, 20).frame(height: 76)
                .background(LinearGradient(colors: [Color(sky.zenith), Color(sky.horizon)], startPoint: .top, endPoint: .bottom))
            }
            Text("Planned with Skies").font(.sf(12, .medium)).opacity(0.6).padding(20)
        }
        .foregroundStyle(.white)
        .frame(width: 360)
        .background(Color(hex: 0x0A0C1A))
    }
}

extension Person {
    /// Who they are on a shared card: you, their first name, their label, or (last resort) the city.
    var cardName: String { isHome ? "Me" : contact?.firstName ?? label.nonEmpty ?? city }
}

// MARK: - Your calendar

/// Your meetings, so free windows skip them, and the calendars other people share with you, so theirs do too.
/// Both need full calendar access, like holidays.
@MainActor @Observable final class Calendars {
    static let shared = Calendars()
    static let key = "useCalendar"
    private(set) var on = UserDefaults.skies.bool(forKey: key)
    /// Every event calendar on this device, for picking the one a person shares.
    private(set) var all: [Info] = []
    /// Someone waiting for a link to finish subscribing in Calendar, and the calendars that existed before it.
    private(set) var waiting: (person: UUID, known: Set<String>, since: Date)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var watching: Any?

    struct Info: Identifiable, Hashable {
        let id: String, title: String, source: String
    }

    var granted: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func allow() async -> Bool {
        if !granted { _ = try? await store.requestFullAccessToEvents() }
        load()
        return granted
    }

    func turn(_ on: Bool) async {
        if on, !(await allow()) { self.on = false; return }
        self.on = on
        UserDefaults.skies.set(on, forKey: Self.key)
        load()
    }

    enum Refusal: Error { case notALink, noAccess }

    /// The webcal:// feed behind a shared link. Google's share and embed links ("…/calendar/u/0?cid=…",
    /// "…/embed?src=…") name the calendar rather than its feed, so they become its public iCal address.
    nonisolated static func feed(from link: String) -> URL? {
        guard var c = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https", "webcal", "webcals"].contains(c.scheme?.lowercased() ?? ""), let host = c.host else { return nil }
        if host.hasSuffix("calendar.google.com"), !c.path.contains("/ical/"),
           let raw = c.queryItems?.first(where: { $0.name == "cid" || $0.name == "src" })?.value {
            guard let id = raw.contains("@") ? raw : googleID(raw),
                  let escaped = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-_"))) else { return nil }
            return URL(string: "webcal://calendar.google.com/calendar/ical/\(escaped)/public/basic.ics")
        }
        c.scheme = "webcal"   // an https link would open in the browser instead
        return c.url
    }

    /// `cid` is the calendar's id in URL-safe base64, usually without padding.
    nonisolated private static func googleID(_ cid: String) -> String? {
        var b = cid.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        guard let data = Data(base64Encoded: b), let id = String(data: data, encoding: .utf8), id.contains("@") else { return nil }
        return id
    }

    /// Hands a shared link ("https://…/basic.ics", "webcal://…", a Google share link) to Calendar's own Subscribe
    /// prompt, which keeps it fresh. The next new calendar to appear is linked to `person`.
    func subscribe(_ link: String, for person: UUID) async throws(Refusal) {
        guard let url = Self.feed(from: link) else { throw .notALink }
        guard await allow() else { throw .noAccess }
        waiting = (person, Set(store.calendars(for: .event).map(\.calendarIdentifier)), .now)
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        await UIApplication.shared.open(url)
        #endif
    }

    func cancelWaiting() { waiting = nil }

    /// Busy events for the next eight days: not all-day, not marked free, not cancelled or declined.
    /// Calendars linked to people count for them, never for you.
    func load() {
        defer { People.shared.refreshRuns() }
        guard granted else { BusyTimes.current = []; BusyTimes.theirs = [:]; all = []; return }
        let calendars = store.calendars(for: .event)
        all = calendars.map { Info(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        // A prompt closed without subscribing shouldn't claim some unrelated calendar added later.
        if let w = waiting, Date.now.timeIntervalSince(w.since) > 600 { waiting = nil }
        if let w = waiting, let new = calendars.first(where: { !w.known.contains($0.calendarIdentifier) }),
           let i = People.shared.list.firstIndex(where: { $0.id == w.person }) {
            People.shared.list[i].calendarID = new.calendarIdentifier
            waiting = nil
        }

        let start = Date.now.addingTimeInterval(-86400), end = start.addingTimeInterval(9 * 86400)
        func busy(_ in: [EKCalendar]) -> [ClosedRange<Double>] {
            guard !`in`.isEmpty else { return [] }
            return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: `in`))
                .filter { !$0.isAllDay && $0.availability != .free && $0.status != .canceled
                    && $0.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined }
                .map { ($0.startDate.timeIntervalSince1970 / 60)...($0.endDate.timeIntervalSince1970 / 60) }
        }
        let linked = Set(People.shared.list.compactMap(\.calendarID))
        BusyTimes.current = on ? busy(calendars.filter { !linked.contains($0.calendarIdentifier) }) : []
        var theirs: [UUID: [ClosedRange<Double>]] = [:]
        for p in People.shared.list {
            if let id = p.calendarID, let c = calendars.first(where: { $0.calendarIdentifier == id }) { theirs[p.id] = busy([c]) }
        }
        BusyTimes.theirs = theirs
        if watching == nil {
            watching = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated { Calendars.shared.load() }
            }
        }
    }
}
