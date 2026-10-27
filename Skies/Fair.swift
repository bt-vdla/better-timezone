import Foundation

/// Fair meeting times: everyone free for the whole meeting, ranked by who has to stretch outside their comfortable
/// hours, weighted so nobody carries it alone, and rotated so whoever stretched last time is spared this time.
enum Fair {
    struct Slot: Sendable {
        let start: Double, end: Double
        /// Hours each person is outside their comfortable band, by id.
        let stretch: [UUID: Double]
        let score: Double
    }

    /// Hours inside someone's free time that suit them best: work from an hour after they start to two before they
    /// finish; friends and family from two hours into their day to one before it ends.
    static func band(_ p: Person, mode: Person.Kind?) -> (Double, Double) {
        let (start, end) = p.isHome && mode == .personal ? (8.0, 22.0) : (p.start, p.end <= p.start ? p.end + 24 : p.end)
        let work = (p.isHome ? (mode ?? .work) : p.relation) == .work
        return work ? (start + 1, max(start + 1, end - 2)) : (start + 2, max(start + 2, end - 1))
    }

    /// How far (hours) a stretch of their local day falls outside their band.
    static func stretch(_ p: Person, from a: Double, to b: Double, mode: Person.Kind?) -> Double {
        let (lo, hi) = band(p, mode: mode)
        let s = Local(p.tz, a).f, e = s + (b - a) / 60
        return max(0, lo - s) + max(0, e - hi)
    }

    // MARK: Rotation

    private static let key = "fair.v1"

    /// How much each person has stretched for meetings you chose, fading by a fifth with each new one.
    static var history: [String: Double] { UserDefaults.skies.dictionary(forKey: key) as? [String: Double] ?? [:] }

    static func record(_ slot: Slot) {
        var h = history.mapValues { $0 * 0.8 }
        for (id, s) in slot.stretch { h[id.uuidString, default: 0] += s }
        UserDefaults.skies.set(h, forKey: key)
    }

    // MARK: Finding

    /// The best few slots of `minutes` in `range`, at least two hours apart, fairest first.
    static func find(_ team: [Person], minutes: Double, in range: ClosedRange<Double>, mode: Person.Kind?,
                     busy: [ClosedRange<Double>] = BusyTimes.current, history: [String: Double] = Fair.history) -> [Slot] {
        guard let home = team.first(where: \.isHome) else { return [] }
        let start = (range.lowerBound / 15).rounded(.up) * 15
        let slots = Int((range.upperBound - start) / 15)
        guard slots > 0 else { return [] }
        let runs = freeRuns(team, from: start, slots: slots, mode: mode, busy: busy)
        var options: [Slot] = []
        for run in runs {
            var a = run.lowerBound
            while a + minutes <= run.upperBound {
                var stretch: [UUID: Double] = [:]
                for p in team { stretch[p.id] = Fair.stretch(p, from: a, to: a + minutes, mode: mode) }
                // The worst stretch counts double, past stretching makes another one cost more, and on-the-hour
                // and half-hour starts are what people actually book.
                let weighted = team.map { p in stretch[p.id]! * (1 + 0.5 * min(2, history[p.id.uuidString] ?? 0)) }
                let even = Int(Local(home.tz, a).m) % 30 == 0 ? 0 : 0.2
                options.append(Slot(start: a, end: a + minutes, stretch: stretch,
                                    score: weighted.reduce(0, +) + (weighted.max() ?? 0) + even + (a - range.lowerBound) / 1440 * 0.05))
                a += 15
            }
        }
        var picked: [Slot] = []
        for o in options.sorted(by: { $0.score < $1.score }) where !picked.contains(where: { abs($0.start - o.start) < 120 }) {
            picked.append(o)
            if picked.count == 3 { break }
        }
        return picked
    }
}
