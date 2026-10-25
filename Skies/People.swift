import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import Synchronization

struct Person: Codable, Identifiable, Hashable {
    var id = UUID()
    var city: String
    var label: String
    var tzID: String
    var lat: Double
    var lon: Double
    var start = 8.0                          // free from, local hour
    var end = 22.0                           // free until, local hour
    var days: Set<Int> = [1, 2, 3, 4, 5]     // 0 = Sunday
    var isHome = false
    /// Work or personal. Nil means "read it from the label", so older saved people need no migration.
    var kind: Kind?
    /// ISO country code ("IN"), for their local working week and public holidays.
    var region: String?
    var contact: Contact?
    /// Your own shortening for where they are ("VIZ"); nil uses the nearest airport's code.
    var codeOverride: String?
    /// Tag ids ("family"), in the order chosen; the first says work or personal. Nil for people saved before tags.
    var tags: [String]?

    /// The bits of a contact card Skies keeps: enough to show a face, reach them, and know their birthday.
    struct Contact: Codable, Hashable {
        var id: String
        var name: String
        /// The first number only, from before every number was kept. Read `numbers` instead.
        var phone: String?
        var phones: [Number]?
        var email: String?
        var birthday: DateComponents?
        // ponytail: the thumbnail lives in the saved list; move photos to files if lists ever get long.
        var photo: Data?
        /// The way you usually reach them, pinned like a Phone favourite.
        var favourite: Channel?
        /// Their company, which suggests a work tag.
        var organization: String?

        struct Number: Codable, Hashable {
            var label: String
            var value: String
        }

        var numbers: [Number] { phones ?? phone.map { [Number(label: "phone", value: $0)] } ?? [] }
    }

    enum Kind: String, Codable, CaseIterable {
        case work, personal

        var title: String { self == .work ? "Work" : "Personal" }
        var symbol: String { self == .work ? "briefcase.fill" : "house.fill" }
        /// Usual hours to reach them: office hours on their country's working days, or waking hours every day.
        func preset(_ region: String?) -> (start: Double, end: Double, days: Set<Int>) {
            self == .work ? (9, 18, Person.workdays(region)) : (8, 22, Set(0..<7))
        }

        /// "Design team" reads as work; "Mom", "Friends" or a first name as personal. Your own row defaults to work.
        // ponytail: keyword match; let people override it in the editor rather than growing this list forever.
        static func infer(_ label: String, isHome: Bool) -> Kind {
            keyword(label) ?? (isHome ? .work : .personal)
        }

        private static let keywords = Mutex<[String: Kind?]>([:])

        /// Memoized: availability asks every 15-minute slot, and lowercasing plus matching costs microseconds each time.
        private static func keyword(_ label: String) -> Kind? {
            if let hit = keywords.withLock({ $0[label] }) { return hit }
            let l = label.lowercased()
            let work = ["team", "client", "work", "office", "colleague", "investor", "review", "partners", "site",
                        "manager", "boss", "company", "vendor", "customer", "project", "design", "board", "studio"]
            let personal = ["family", "friend", "partner", "mom", "mum", "dad", "brother", "sister", "wife", "husband",
                            "kids", "home", "love", "grand", "cousin", "aunt", "uncle", "bae"]
            let k: Kind? = work.contains(where: l.contains) ? .work : personal.contains(where: l.contains) ? .personal : nil
            keywords.withLock { $0[label] = k }
            return k
        }
    }

    /// Set by hand, else their first tag's, else read from the name.
    var relation: Kind { kind ?? tagList.lazy.compactMap { Tags.named($0)?.kind }.first ?? .infer(label, isHome: isHome) }
    /// What to call them in menus and sentences: the same as `name`.
    var shortName: String { name }
    var tz: TimeZone { TimeZone(identifier: tzID) ?? .current }

    func inHours(_ f: Double) -> Bool { end > start ? f >= start && f < end : f >= start || f < end }
    // ponytail: an overnight window (22–6) counts its after-midnight half on the next weekday; per-shift days if anyone needs it.

    /// Free to talk at this local moment. `mode` is the kind of people you're planning with: with personal people,
    /// your own row switches to free-time hours, and weekday working hours (bar lunch) don't count for anyone personal.
    func free(_ l: Local, with mode: Kind? = nil) -> Bool {
        let offDuty = isHome && mode == .personal
        // ponytail: your free-time hours are fixed at 8 AM–10 PM every day; a setting if anyone keeps odd hours.
        let open = offDuty ? l.f >= 8 && l.f < 22 : days.contains(l.wd) && inHours(l.f)
        guard open else { return false }
        for id in tagList where !isHome {
            if let t = Tags.named(id), !t.allows(l, workdays: workdays) { return false }
        }
        return !(relation == .personal || offDuty) || !busyDay(l)
    }

    /// Working hours outside lunch, on their country's working days: when friends and family are probably at work.
    func busyDay(_ l: Local) -> Bool {
        weekdays.contains(l.wd) && l.f >= 9 && l.f < 17 && !(12.5..<13.5).contains(l.f)
    }

    /// The days friends and family are probably at work. Where the official week runs six days (India, for one),
    /// the last of them is often a half day or off, so it doesn't count against talking time.
    var weekdays: Set<Int> {
        let key = region ?? ""
        if let known = Self.shortWeeks.withLock({ $0[key] }) { return known }
        let w = workdays
        let days = w.count > 5 ? (0..<7).first(where: { w.contains($0) && !w.contains(($0 + 1) % 7) }).map { w.subtracting([$0]) } ?? w : w
        Self.shortWeeks.withLock { $0[key] = days }
        return days
    }

    private static let shortWeeks = Mutex<[String: Set<Int>]>([:])

    var workdays: Set<Int> { Person.workdays(region) }

    private static let weeks = Mutex<[String: Set<Int>]>([:])

    /// The working week where they live, from the locale's weekend (Sun–Thu in Saudi Arabia, Mon–Fri in most places).
    static func workdays(_ region: String?) -> Set<Int> {
        guard let region else { return [1, 2, 3, 4, 5] }
        if let known = weeks.withLock({ $0[region] }) { return known }
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_\(region)")
        let monday = Date(timeIntervalSince1970: 1_792_411_200)
        let days = Set((0..<7).filter { !c.isDateInWeekend(monday + Double($0) * 86400) }.map { ($0 + 1) % 7 })
        weeks.withLock { $0[region] = days }
        return days
    }

    func hasPreset(_ k: Kind) -> Bool { let p = k.preset(region); return (start, end, days) == (p.start, p.end, p.days) }
    mutating func applyPreset(_ k: Kind) { let p = k.preset(region); (start, end, days) = (p.start, p.end, p.days) }

    /// True on their birthday, in their own time zone.
    func birthday(_ l: Local) -> Bool {
        guard let b = contact?.birthday, let month = b.month, let day = b.day else { return false }
        let d = gmtDay(l.dn)
        return d.month == month && d.day == day
    }

    /// After the relationship changes, move to its usual hours, unless the hours were customised.
    mutating func follow(from old: Kind) {
        if relation != old && hasPreset(old) { applyPreset(relation) }
    }

    static let defaults: [Person] = [
        Person(city: "Hyderabad", label: "You", tzID: "Asia/Kolkata", lat: 17.385, lon: 78.487, isHome: true, region: "IN"),
        Person(city: "Georgetown", label: "Site team", tzID: "America/Guyana", lat: 6.801, lon: -58.155, region: "GY"),
        Person(city: "London", label: "Partners", tzID: "Europe/London", lat: 51.507, lon: -0.128, region: "GB"),
        Person(city: "Dubai", label: "Investor", tzID: "Asia/Dubai", lat: 25.205, lon: 55.271, region: "AE"),
        Person(city: "San Francisco", label: "Design review", tzID: "America/Los_Angeles", lat: 37.775, lon: -122.419, region: "US"),
    ]
}

/// The people list plus who's picked for the overlap. Saved locally; iCloud sync comes later.
@MainActor @Observable final class People {
    var list: [Person] { didSet { save() } }
    /// Empty means everyone. You are always included.
    var picked: Set<UUID> = [] { didSet { runsCache.removeAll() } }
    /// A person to open in the main window, asked for from elsewhere (the Mac notch's "Edit…").
    var focus: UUID?
    /// A tag being looked at: only you and its people show, and they're the ones planned with.
    private(set) var scope: String?
    @ObservationIgnored private var runsCache: [String: [ClosedRange<Double>]] = [:]
    private static let key = Person.storeKey

    /// One store for the window and the notch, so both always show the same people.
    static let shared = People()

    /// False for the debug demo list, which must never overwrite the people you saved.
    @ObservationIgnored private var persists = true

    init() {
        // Saved people moved into the App Group so widgets can read them; bring over anything saved before that.
        // On the Mac the newest copy is in the old group name, which only ever worked as the app's private store.
        var sources = [UserDefaults.standard]
        #if os(macOS)
        if let old = UserDefaults(suiteName: UserDefaults.oldMacGroupID) { sources.insert(old, at: 0) }
        #endif
        if UserDefaults.skies.data(forKey: Self.key) == nil {
            for key in [Self.key, Tags.key, ShowBy.key] {
                if let value = sources.lazy.compactMap({ $0.object(forKey: key) }).first { UserDefaults.skies.set(value, forKey: key) }
            }
            Tags.reload()
        }
        list = Person.saved()
        // Before tags, a group's name went in the name field ("Family"); make it a tag too, once. Names stay as they are.
        if list.contains(where: { $0.tags == nil }) {
            list = list.map { p in
                var p = p
                if p.tags == nil { p.tags = p.isHome ? [] : Tags.match(p.label).map { [$0.id] } ?? [] }
                return p
            }
            save()
        }
        applyFocus()
        // After an update, widgets otherwise keep drawing with the old code until their timeline runs out.
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        #if os(iOS)
        ControlCenter.shared.reloadAllControls()
        #endif
        #if DEBUG
        // `-SkiesDemoPeople YES`: eight people (in memory only) to see layouts that kick in past five.
        if UserDefaults.standard.bool(forKey: "SkiesDemoPeople") {
            persists = false
            list = Person.defaults + [
                Person(city: "Visakhapatnam", label: "Mom", tzID: "Asia/Kolkata", lat: 17.69, lon: 83.22, region: "IN"),
                Person(city: "Tokyo", label: "Ken", tzID: "Asia/Tokyo", lat: 35.68, lon: 139.65, region: "JP"),
                Person(city: "São Paulo", label: "Bia", tzID: "America/Sao_Paulo", lat: -23.55, lon: -46.63, region: "BR"),
            ]
        }
        #endif
    }

    var home: Person { list.first(where: \.isHome) ?? list[0] }
    var team: [Person] { picked.isEmpty ? list : list.filter { $0.isHome || picked.contains($0.id) } }
    /// Work or personal when everyone you're planning with is the same kind; nil for a mix.
    var mode: Person.Kind? {
        let kinds = Set(team.filter { !$0.isHome }.map(\.relation))
        return kinds.count == 1 ? kinds.first : nil
    }
    var everyone: Bool { team.count == list.count }

    /// Who's shown: everyone, or you and the people in the tag being looked at.
    var visible: [Person] { scope.map { s in list.filter { $0.isHome || $0.has(s) } } ?? list }
    var scopeTag: PersonTag? { scope.flatMap(Tags.named) }
    /// Tags someone has, in catalogue order, for the scope menus.
    var usedTags: [PersonTag] { Tags.all.filter { t in list.contains { $0.has(t.id) } } }

    /// Follow the tag a Focus asked for (Work focus → Team), or everyone when that Focus ends.
    func applyFocus() { setScope(Tags.focused.flatMap { Tags.named($0)?.id }) }

    /// Look at one tag: show its people and plan with exactly them. Nil goes back to everyone.
    func setScope(_ tag: String?) {
        scope = tag
        picked = tag.map { t in Set(list.filter { $0.has(t) }.map(\.id)) } ?? []
    }

    func toggle(_ p: Person) {
        guard !p.isHome else { return }
        if picked.contains(p.id) { picked.remove(p.id) } else { picked.insert(p.id) }
        if picked.count == list.count - 1 { picked = [] }
    }

    /// Free runs for the team over the 8 days from `dayStart`, cached per day and selection.
    func runs(from dayStart: Double) -> [ClosedRange<Double>] {
        let k = "\(Int(dayStart))|\(picked.sorted { $0.uuidString < $1.uuidString })"
        if let hit = runsCache[k] { return hit }
        let r = freeRuns(team, from: dayStart, slots: 96 * 8, mode: mode)
        runsCache[k] = r
        return r
    }

    private func save() {
        runsCache.removeAll()
        picked = picked.filter { id in list.contains { $0.id == id } }
        guard persists else { return }
        UserDefaults.skies.set(try? JSONEncoder().encode(list), forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
