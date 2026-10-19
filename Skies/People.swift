import Foundation

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

    var tz: TimeZone { TimeZone(identifier: tzID) ?? .current }

    func inHours(_ f: Double) -> Bool { end > start ? f >= start && f < end : f >= start || f < end }
    // ponytail: an overnight window (22–6) counts its after-midnight half on the next weekday; per-shift days if anyone needs it.
    func free(_ l: Local) -> Bool { days.contains(l.wd) && inHours(l.f) }

    static let defaults: [Person] = [
        Person(city: "Hyderabad", label: "You", tzID: "Asia/Kolkata", lat: 17.385, lon: 78.487, isHome: true),
        Person(city: "Georgetown", label: "Site team", tzID: "America/Guyana", lat: 6.801, lon: -58.155),
        Person(city: "London", label: "Partners", tzID: "Europe/London", lat: 51.507, lon: -0.128),
        Person(city: "Dubai", label: "Investor", tzID: "Asia/Dubai", lat: 25.205, lon: 55.271),
        Person(city: "San Francisco", label: "Design review", tzID: "America/Los_Angeles", lat: 37.775, lon: -122.419),
    ]
}

/// The people list plus who's picked for the overlap. Saved locally; iCloud sync comes later.
@MainActor @Observable final class People {
    var list: [Person] { didSet { save() } }
    /// Empty means everyone. You are always included.
    var picked: Set<UUID> = [] { didSet { runsCache.removeAll() } }
    @ObservationIgnored private var runsCache: [String: [ClosedRange<Double>]] = [:]
    private static let key = "people.v1"

    init() {
        list = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Person].self, from: $0) } ?? Person.defaults
    }

    var home: Person { list.first(where: \.isHome) ?? list[0] }
    var team: [Person] { picked.isEmpty ? list : list.filter { $0.isHome || picked.contains($0.id) } }
    var everyone: Bool { team.count == list.count }

    func toggle(_ p: Person) {
        guard !p.isHome else { return }
        if picked.contains(p.id) { picked.remove(p.id) } else { picked.insert(p.id) }
        if picked.count == list.count - 1 { picked = [] }
    }

    /// Free runs for the team over the 8 days from `dayStart`, cached per day and selection.
    func runs(from dayStart: Double) -> [ClosedRange<Double>] {
        let k = "\(Int(dayStart))|\(picked.sorted { $0.uuidString < $1.uuidString })"
        if let hit = runsCache[k] { return hit }
        let r = freeRuns(team, from: dayStart, slots: 96 * 8)
        runsCache[k] = r
        return r
    }

    private func save() {
        runsCache.removeAll()
        picked = picked.filter { id in list.contains { $0.id == id } }
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: Self.key)
    }
}
