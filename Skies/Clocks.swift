import Foundation

/// Daylight saving and other clock changes, put into words for Ask's answers.
enum Clocks {
    static func offset(_ tz: TimeZone, _ m: Double) -> Int { tz.secondsFromGMT(for: Date(timeIntervalSince1970: m * 60)) / 60 }

    /// Minutes clock `b` is ahead of clock `a` at that moment.
    static func gap(_ a: TimeZone, _ b: TimeZone, _ m: Double) -> Int { offset(b, m) - offset(a, m) }

    /// "+9h 30m", "−3h", "same time": how far the second clock is from the first.
    static func signed(_ g: Int) -> String { g == 0 ? "same time" : "\(g > 0 ? "+" : "−")\(dur(Double(abs(g))))" }

    /// "5h 30m apart", "same time".
    static func apart(_ g: Int) -> String { g == 0 ? "same time" : "\(dur(Double(abs(g)))) apart" }

    /// "UTC+5:30".
    static func utc(_ off: Int) -> String {
        let h = abs(off) / 60, m = abs(off) % 60
        return "UTC\(off < 0 ? "−" : "+")\(h)\(m == 0 ? "" : String(format: ":%02d", m))"
    }

    /// What the zone calls its changed clocks: the Americas say daylight time, most of the world summer time.
    static func season(_ tz: TimeZone, _ m: Double) -> String? {
        guard tz.isDaylightSavingTime(for: Date(timeIntervalSince1970: m * 60)) else { return nil }
        return tz.identifier.hasPrefix("America/") ? "daylight time" : "summer time"
    }

    struct Change { let at: Double; let shift: Int }

    /// Clock changes in a span, in order.
    static func changes(_ tz: TimeZone, from: Double, to: Double) -> [Change] {
        var out: [Change] = [], after = Date(timeIntervalSince1970: from * 60)
        while let t = tz.nextDaylightSavingTimeTransition(after: after), t.timeIntervalSince1970 / 60 <= to {
            out.append(Change(at: t.timeIntervalSince1970 / 60, shift: (tz.secondsFromGMT(for: t + 60) - tz.secondsFromGMT(for: t - 60)) / 60))
            after = t + 1
        }
        return out
    }

    /// The last change before a moment, looking back up to a year.
    static func last(_ tz: TimeZone, before m: Double) -> Change? { changes(tz, from: m - 366 * 1440, to: m).last }

    static func move(_ shift: Int, past: Bool = false) -> String {
        let d = dur(Double(abs(shift)))
        return shift > 0 ? (past ? "went forward \(d)" : "go forward \(d)") : (past ? "went back \(d)" : "go back \(d)")
    }

    /// "today", "yesterday", "tomorrow", "Sun 1 Nov".
    static func day(_ m: Double, _ tz: TimeZone, now: Double) -> String {
        switch Local(tz, m).dn - Local(tz, now).dn {
        case 0: "today"
        case -1: "yesterday"
        case 1: "tomorrow"
        default: Date(timeIntervalSince1970: m * 60).formatted(Date.FormatStyle(timeZone: tz).weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    /// "Kate's", "your", "Paris'".
    static func owner(_ who: String) -> String {
        who == "your" ? "your" : who == "Your clock" ? "Your" : who.hasSuffix("s") ? "\(who)'" : "\(who)'s"
    }

    /// The one clock-change cue worth showing when reading a time on clock `a` against clock `b`, if any:
    /// a change between now and then, one in the past week, or one in the fortnight after.
    static func cue(_ a: (name: String, tz: TimeZone), _ b: (name: String, tz: TimeZone), at m: Double, now: Double) -> String? {
        rawCue(a, b, at: m, now: now).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    private static func rawCue(_ a: (name: String, tz: TimeZone), _ b: (name: String, tz: TimeZone), at m: Double, now: Double) -> String? {
        let gapNow = gap(a.tz, b.tz, now), gapThen = gap(a.tz, b.tz, m)
        func first(_ from: Double, _ to: Double) -> (who: String, tz: TimeZone, change: Change)? {
            [(a.name, a.tz), (b.name, b.tz)]
                .compactMap { who, tz in changes(tz, from: from, to: to).first.map { (who, tz, $0) } }
                .min { $0.change.at < $1.change.at }
        }
        // Between now and then: the gap then isn't today's gap.
        if gapThen != gapNow, let c = first(min(now, m), max(now, m)) {
            let ahead = m > now
            return "\(owner(c.who)) clocks \(move(c.change.shift, past: !ahead)) \(day(c.change.at, c.tz, now: now)): "
                + (ahead ? "\(apart(gapThen)) then, \(apart(gapNow).replacingOccurrences(of: " apart", with: "")) now"
                         : "\(apart(gapThen)) then")
        }
        // In the past week: today's gap is new.
        if let c = first(now - 7 * 1440, now), gap(a.tz, b.tz, c.change.at - 1) != gapNow {
            let before = gap(a.tz, b.tz, c.change.at - 1)
            return "\(owner(c.who)) clocks \(move(c.change.shift, past: true)) \(day(c.change.at, c.tz, now: now)): "
                + "\(apart(gapNow)) now, was \(dur(Double(abs(before))))"
        }
        // In the fortnight after: worth knowing before making it a habit.
        if let c = first(max(now, m), max(now, m) + 14 * 1440), gap(a.tz, b.tz, c.change.at + 1) != gapThen {
            return "From \(day(c.change.at, c.tz, now: now)), \(apart(gap(a.tz, b.tz, c.change.at + 1))): "
                + "\(owner(c.who)) clocks \(move(c.change.shift))"
        }
        return nil
    }

    /// The clock change to mention before anyone asks: one in the next fortnight (or the last two days) on your clock
    /// or someone's, that moves the gap between you. `short` fits beside the notch; `ask` is the question it answers.
    static func headsUp(_ list: [Person], now: Double) -> (text: String, short: String, ask: String)? {
        guard let home = list.first(where: \.isHome) ?? list.first else { return nil }
        var best: (names: [String], change: Change, tz: TimeZone, you: Bool)?
        var byZone: [String: [Person]] = [:]
        for p in list { byZone[p.tz.identifier, default: []].append(p) }
        for (_, group) in byZone {
            let tz = group[0].tz, you = group.contains(where: \.isHome)
            for c in changes(tz, from: now - 2 * 1440, to: now + 14 * 1440) {
                // Someone else's change only matters if it moves their gap to you.
                guard you || gap(home.tz, tz, c.at - 1) != gap(home.tz, tz, c.at + 1) else { continue }
                if best == nil || abs(c.at - now) < abs(best!.change.at - now) {
                    best = (group.filter { !$0.isHome }.map(\.name), c, tz, you)
                }
                break
            }
        }
        guard let b = best else { return nil }
        let who = b.you ? "Your" : owner(ListFormatter.localizedString(byJoining: b.names))
        let days = Local(b.tz, b.change.at).dn - Local(b.tz, now).dn
        let past = b.change.at < now
        let move = b.change.shift > 0 ? (past ? "went forward" : "go forward") : (past ? "went back" : "go back")
        let when = days == 0 ? "today" : days == 1 ? "tomorrow" : days == -1 ? "yesterday" : past ? "\(-days) days ago" : "in \(days) days"
        let short = days == 0 ? "today" : days == 1 ? "tomorrow" : days == -1 ? "yesterday" : past ? "\(-days)d ago" : "in \(days)d"
        let named = b.you ? "my" : (b.names.first ?? "")
        return ("\(who) clocks \(move) \(when)", "Clocks \(move) \(short)",
                // Already changed: their time now carries the "went back" cue. Coming up: the gap after it.
                past ? "time in \(b.you ? (list.first { !$0.isHome }?.name ?? "london") : named)"
                     : "\(b.you ? "my" : owner(named)) clock change")
    }
}
