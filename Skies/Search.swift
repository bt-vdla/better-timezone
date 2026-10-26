import SwiftUI

// MARK: - Places anywhere

/// A clock to read a time on: one of your people, or any city, country or time zone.
struct Zone: Equatable {
    let name: String
    let tz: TimeZone
    var person: Person? = nil
}

/// Countries (bundled table), every time zone's city, common cities and abbreviations. Offline and instant;
/// anything else is looked up on Apple Maps by the search UI.
enum Places {
    private static let table: [String: Zone] = {
        var t: [String: Zone] = [:]
        func add(_ key: String, _ name: String, _ id: String) {
            guard let tz = TimeZone(identifier: id) else { return }
            let k = key.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            if t[k] == nil { t[k] = Zone(name: name, tz: tz) }
        }
        for id in TimeZone.knownTimeZoneIdentifiers where id.contains("/") && !id.hasPrefix("Etc/") {
            let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
            add(city, city, id)
        }
        let en = Locale(identifier: "en")
        if let url = Bundle.main.url(forResource: "countries", withExtension: "csv"), let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let f = line.split(separator: ",")
                guard f.count == 2 else { continue }
                let cc = String(f[0]), id = String(f[1])
                for name in Set([en.localizedString(forRegionCode: cc), Locale.current.localizedString(forRegionCode: cc)].compactMap { $0 }) {
                    add(name, en.localizedString(forRegionCode: cc) ?? name, id)
                }
            }
        }
        for (keys, name, id) in aliases { for k in keys { add(k, name, id) } }
        return t
    }()

    private static let aliases: [([String], String, String)] = [
        (["usa", "america", "united states", "the us", "east coast", "new york city", "nyc", "boston", "miami", "atlanta", "washington", "dc", "philadelphia"], "New York", "America/New_York"),
        (["sf", "west coast", "la", "san francisco", "seattle", "las vegas", "vegas", "portland", "san diego", "san jose", "bay area", "silicon valley"], "California", "America/Los_Angeles"),
        (["texas", "dallas", "houston", "austin"], "Texas", "America/Chicago"),
        (["uk", "britain", "great britain", "england", "scotland", "wales", "manchester", "edinburgh"], "UK", "Europe/London"),
        (["uae", "emirates", "abu dhabi"], "UAE", "Asia/Dubai"),
        (["mumbai", "bombay", "delhi", "new delhi", "bangalore", "bengaluru", "hyderabad", "chennai", "pune", "calcutta", "vizag", "visakhapatnam", "goa"], "India", "Asia/Kolkata"),
        (["beijing", "shenzhen", "guangzhou"], "China", "Asia/Shanghai"),
        (["osaka", "kyoto"], "Japan", "Asia/Tokyo"),
        (["korea", "south korea"], "Seoul", "Asia/Seoul"),
        (["bali"], "Bali", "Asia/Makassar"),
        (["munich", "frankfurt", "hamburg", "cologne"], "Germany", "Europe/Berlin"),
        (["milan", "florence", "venice", "naples"], "Italy", "Europe/Rome"),
        (["barcelona", "seville"], "Spain", "Europe/Madrid"),
        (["geneva"], "Switzerland", "Europe/Zurich"),
        (["holland", "the netherlands"], "Netherlands", "Europe/Amsterdam"),
        (["perth"], "Perth", "Australia/Perth"),
        (["montreal", "ottawa"], "Canada", "America/Toronto"),
        (["vancouver"], "Vancouver", "America/Vancouver"),
        (["turkey", "türkiye"], "Türkiye", "Europe/Istanbul"),
        (["czech republic", "czechia"], "Czechia", "Europe/Prague"),
        (["pst", "pdt", "pt", "pacific", "pacific time"], "Pacific Time", "America/Los_Angeles"),
        (["est", "edt", "et", "eastern", "eastern time"], "Eastern Time", "America/New_York"),
        (["cst", "cdt", "central time"], "Central Time", "America/Chicago"),
        (["mst", "mdt", "mountain time"], "Mountain Time", "America/Denver"),
        (["ist", "india time"], "India", "Asia/Kolkata"),
        (["gmt", "utc", "zulu"], "UTC", "GMT"),
        (["bst"], "UK", "Europe/London"),
        (["cet", "cest"], "Central Europe", "Europe/Paris"),
        (["jst"], "Japan", "Asia/Tokyo"),
        (["aest", "aedt"], "Sydney", "Australia/Sydney"),
        (["sgt"], "Singapore", "Asia/Singapore"),
        (["hkt"], "Hong Kong", "Asia/Hong_Kong"),
        (["gst"], "Gulf", "Asia/Dubai"),
    ]

    static func zone(named name: String) -> Zone? {
        table[name.lowercased().folding(options: .diacriticInsensitive, locale: nil)]
    }

    /// The longest place named in a padded query (" india 3pm "), and the words it used.
    static func find(in padded: String) -> (zone: Zone, key: String)? {
        let q = padded.folding(options: .diacriticInsensitive, locale: nil)
        var best: (Zone, String)?
        for (key, zone) in table where key.count > (best?.1.count ?? 1) && q.contains(" \(key) ") { best = (zone, key) }
        return best
    }
}

// MARK: - Reading a typed time

/// A moment typed in words: "india 3pm", "Kate 3pm", "fri 9 tokyo", "tomorrow 8pm Amma", "in 2h", "3pm pst".
/// A person or place in the query means their clock; otherwise yours.
struct Jump: Equatable {
    let minutes: Double
    /// Whose clock the time was read on, when one was named.
    let zone: Zone?
    var person: Person? { zone?.person }
}

extension Person {
    /// Their clock as a Zone.
    var zone: Zone { Zone(name: name, tz: tz, person: self) }
}

enum JumpParser {
    private static let days: [(String, Int)] = [
        ("sunday", 0), ("monday", 1), ("tuesday", 2), ("wednesday", 3), ("thursday", 4), ("friday", 5), ("saturday", 6),
        ("tues", 2), ("thur", 4), ("thurs", 4), ("sun", 0), ("mon", 1), ("tue", 2), ("wed", 3), ("thu", 4), ("fri", 5), ("sat", 6),
    ]

    /// Your person first ("Amma"), then anywhere in the world ("India"), then places looked up online (`extra`).
    static func zone(in padded: String, people: [Person], extra: [Zone] = []) -> (zone: Zone, keys: [String])? {
        var best: (Person, String)?
        for p in people {
            for key in [p.name, p.city, p.code, p.contact?.name ?? "", p.contact?.firstName ?? ""].map({ $0.lowercased() })
            where key.count >= 2 && key.count > (best?.1.count ?? 0) && padded.contains(" \(key) ") {
                best = (p, key)
            }
        }
        if let (p, _) = best {
            return (p.zone, [p.name, p.city, p.code, p.contact?.name ?? ""].map { $0.lowercased() }.filter { !$0.isEmpty })
        }
        if let (z, key) = Places.find(in: padded) { return (z, [key]) }
        if let z = extra.first(where: { padded.contains(" \($0.name.lowercased()) ") }) { return (z, [z.name.lowercased()]) }
        return nil
    }

    static func parse(_ query: String, people: [Person], now: Double, extra: [Zone] = []) -> Jump? {
        var q = " " + query.lowercased().trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + " "
        guard q.count > 2, let home = people.first(where: \.isHome) ?? people.first else { return nil }

        // "in 2h", "+90m", "india 3 hours from now", "kate in an hour", "2h ago": a span from now, anywhere in the
        // question; whatever's left names whose clock to show it on.
        q = q.replacing(/\bhalf an hour\b/) { _ in "30 min" }.replacing(/\b(?:an|one)\s+hour\b/) { _ in "1 hour" }
        if let m = q.firstMatch(of: /\s(?:in\s+|\+|-)?(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)(?:\s+(from now|later|ahead|from here|ago|back|before))?(?=\s)/) {
            let n = Double(m.1) ?? 0
            let span = m.2.hasPrefix("h") ? n * 60 : n
            let back = m.0.contains("-") || ["ago", "back", "before"].contains(m.3.map(String.init) ?? "")
            let rest = q.replacingCharacters(in: m.range, with: " ")
            let who = zone(in: rest, people: people, extra: extra)?.zone
            return Jump(minutes: now + (back ? -span : span), zone: who)
        }

        let found = zone(in: q, people: people, extra: extra)
        for key in found?.keys ?? [] { q = q.replacingOccurrences(of: " \(key) ", with: " ") }

        // Which day.
        var dayWord: Int?
        var weekday: Int?
        var evening = false
        if q.contains(" today ") { dayWord = 0 }
        if q.contains(" tonight ") { dayWord = 0; evening = true }
        if q.contains(" tomorrow ") || q.contains(" tmrw ") || q.contains(" tmr ") { dayWord = 1 }
        for (word, wd) in days where q.contains(" \(word) ") { weekday = wd; break }

        // What time: "3pm", "3 pm", "15:30", "9", "noon", "midnight".
        var hour: Int?, minute = 0, suffix: String?
        q = q.replacing(/(\d)\s+(am|pm|a|p)\b/) { "\($0.1)\($0.2)" }
        if q.contains(" noon ") { hour = 12; suffix = "pm" }
        if q.contains(" midnight ") { hour = 0; suffix = "am" }
        if hour == nil, let m = q.firstMatch(of: /\s(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?\s/) {
            hour = Int(m.1)
            minute = m.2.flatMap { Int($0) } ?? 0
            suffix = m.3.map { $0.hasPrefix("a") ? "am" : "pm" }
        }
        guard hour != nil || dayWord != nil || weekday != nil else { return nil }
        guard (hour ?? 0) < 24, minute < 60 else { return nil }

        let tz = found?.zone.tz ?? home.tz
        let today = Local(tz, now)
        let offset = dayWord ?? weekday.map { ($0 - today.wd + 7) % 7 } ?? 0
        let dayNamed = dayWord != nil || weekday != nil

        // Turn 1–12 with no am/pm into a real hour.
        var h = hour ?? 9
        if let suffix {
            h = h % 12 + (suffix == "pm" ? 12 : 0)
        } else if hour != nil && h <= 12 {
            if evening { h = h % 12 + 12 }
            else if dayNamed && offset > 0 { h = h == 12 ? 12 : h < 7 ? h + 12 : h }   // "fri 3" means the afternoon
            else {
                // Today with no am/pm: whichever of the two comes next.
                let am = h % 12, at = Double(minute) / 60
                h = Double(am) + at > today.f ? am : Double(am + 12) + at > today.f ? am + 12 : am
            }
        }

        // Mid-day of the target day keeps clock changes from shifting which day we land on.
        let start = dayStart(tz, dayStart(tz, now) + Double(offset) * 1440 + 720)
        var m = start + Double(h * 60 + minute)
        // A time already gone today, with no day named, means tomorrow.
        if !dayNamed && m <= now - 1 { m = dayStart(tz, start + 1440 + 720) + Double(h * 60 + minute) }
        return Jump(minutes: m, zone: found?.zone)
    }
}

// MARK: - Answers

/// One line of a search result: an answer, a time, a person or a tag, and what tapping it does.
struct Hit: Identifiable {
    enum Action { case jump(Double, pick: Set<UUID>), open(UUID), scope(String) }
    let id: String
    let icon: String
    let title: String
    let detail: String
    let action: Action?
    var color: RGB? = nil
    var person: Person? = nil
    /// Clocks side by side on the answer card: theirs, then yours.
    var clocks: [HitClock] = []
    /// The moment the card shows, for its sky.
    var at: Double? = nil
    /// A shorter line for the answer card, where the clocks already say the rest.
    var headline: String? = nil
    /// The card's second line, only where the clocks don't already say it.
    var note: String? = nil
}

struct HitClock: Hashable {
    let place: String
    let time: String
    let day: String
}

/// Plain questions about your people, answered from their clocks: "is amma awake", "when can I speak to family",
/// "what time is it in tokyo". No model; patterns and the same maths as the rest of Skies.
enum Ask {
    static func hits(_ query: String, people: [Person], now: Double, extra: [Zone] = []) -> [Hit] {
        let q = query.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "?!.,")))
        guard !q.isEmpty, let home = people.first(where: \.isHome) ?? people.first else { return [] }
        var out: [Hit] = []

        if let m = q.firstMatch(of: /^(?:is|are)\s+(.+?)\s+(awake|up|asleep|sleeping|free|available|around|busy|working|at work|online)$/),
           let who = target(String(m.1), people) {
            out += who.members.prefix(6).map { awake($0, home: home, now: now, asked: String(m.2)) }
        } else if let phrase = whenPhrase(q), let who = target(phrase, people) {
            out.append(when(who, home: home, now: now))
        } else if let m = q.firstMatch(of: /^(?:what(?:'s| is)?\s+)?(?:the\s+)?time\s+(?:is it\s+)?(?:in|for|at)\s+(.+)$/) {
            let padded = " \(m.1) "
            if let z = JumpParser.zone(in: padded, people: people, extra: extra)?.zone { out.append(timeIn(z, home: home, now: now)) }
        }

        if let jump = JumpParser.parse(q, people: people, now: now, extra: extra) {
            out.append(jumpHit(jump, home: home))
        } else if out.isEmpty, let z = JumpParser.zone(in: " \(q) ", people: people, extra: extra)?.zone, z.person == nil {
            // A bare place ("tokyo"): its time now.
            out.append(timeIn(z, home: home, now: now))
        }

        // Tags and people that the words name.
        let words = q.split(separator: " ").map(String.init).filter { $0.count >= 2 && $0.first?.isLetter == true }
        for t in Tags.all where people.contains(where: { $0.has(t.id) }) && words.contains(where: { matches(t.name, $0) }) {
            out.append(Hit(id: "tag-\(t.id)", icon: "tag.fill", title: "Show \(t.name)",
                           detail: "\(people.filter { $0.has(t.id) }.map(\.name).formatted())", action: .scope(t.id), color: t.rgb))
        }
        let named = Set(out.compactMap { $0.person?.id })
        for p in people where !named.contains(p.id) {
            let fields = [p.name, p.city, p.code, p.contact?.name ?? ""].map { $0.lowercased() }
            guard fields.contains(where: { f in f.hasPrefix(q) || words.contains { f.hasPrefix($0) } }) else { continue }
            let l = Local(p.tz, now)
            out.append(Hit(id: "person-\(p.id)", icon: "person.crop.circle", title: p.name,
                           detail: "\(clock(l)) \(ampm(l.h)) · \(p.city) · \(status(p, l).0)", action: .open(p.id), person: p))
        }
        return out
    }

    /// "family" matches the Family tag, "friend" matches Friends, "fam" its start.
    private static func matches(_ name: String, _ word: String) -> Bool {
        let n = name.lowercased()
        return n == word || n.hasPrefix(word) || n == word + "s" || n + "s" == word
    }

    /// Everyone a phrase names: "amma", "my family", "the team", "everyone", "kate and om".
    static func target(_ phrase: String, _ people: [Person]) -> (name: String, members: [Person], tag: PersonTag?)? {
        var p = " \(phrase) "
        for filler in [" my ", " the ", " our ", " all of ", " all my "] { p = p.replacingOccurrences(of: filler, with: " ") }
        p = p.trimmingCharacters(in: .whitespaces)
        let others = people.filter { !$0.isHome }
        if ["everyone", "everybody", "all", "them", "people", "anyone", "anybody", "all of them"].contains(p) { return ("everyone", others, nil) }
        let parts = p.components(separatedBy: " and ").flatMap { $0.components(separatedBy: ", ") }.map { $0.trimmingCharacters(in: .whitespaces) }
        var members: [Person] = [], tag: PersonTag?
        for part in parts where !part.isEmpty {
            if let t = Tags.all.first(where: { t in matches(t.name, part) && part.count >= 3 && others.contains { $0.has(t.id) } }) {
                tag = t
                members += others.filter { $0.has(t.id) }
            } else if let person = others.first(where: { person in
                [person.name, person.city, person.code, person.contact?.name ?? "", person.contact?.firstName ?? ""]
                    .map { $0.lowercased() }.contains { !$0.isEmpty && ($0 == part || (part.count >= 3 && $0.hasPrefix(part))) }
            }) {
                members.append(person)
            }
        }
        var seen = Set<UUID>()
        members = members.filter { seen.insert($0.id).inserted }
        guard !members.isEmpty else { return nil }
        let name = parts.count == 1 && tag != nil ? tag!.name : members.map(\.name).formatted()
        return (name, members, parts.count == 1 ? tag : nil)
    }

    /// The who in "when can I speak to …", "when is … free", "best time to call …", "call …".
    private static func whenPhrase(_ q: String) -> String? {
        let verbs = "(?:speak|talk|call|meet|chat|ring|reach|catch|see|phone|facetime|video call|catch up)"
        let patterns = [
            "^(?:when|what time)\\s+(?:can|could|should|shall|do|will|would)\\s+(?:i|we)\\s+\(verbs)(?:\\s+(?:to|with|up with))?\\s+(.+)$",
            "^when\\s+(?:is|are)\\s+(.+?)\\s+(?:free|available|around|awake|up)$",
            "^(?:next|best)\\s+time\\s+(?:to\\s+\(verbs)\\s+)?(?:with|for|to)?\\s*(.+)$",
            "^(?:when|time)\\s+(?:to\\s+)?\(verbs)(?:\\s+(?:to|with))?\\s+(.+)$",
            "^\(verbs)(?:\\s+(?:to|with))?\\s+(.+)$",
        ]
        for p in patterns {
            if let r = try? Regex(p), let m = q.firstMatch(of: r), let cap = m.output[1].substring { return String(cap) }
        }
        return nil
    }

    private static func dayText(_ m: Double, _ tz: TimeZone, now: Double) -> String {
        let days = Local(tz, m).dn - Local(tz, now).dn
        return days == 0 ? "Today" : days == 1 ? "Tomorrow" : Calendar.current.shortWeekdaySymbols[Local(tz, m).wd]
    }

    /// "Yes, Amma's up" / "No, Kate's asleep" with when they'll be up, and a jump there.
    private static func awake(_ p: Person, home: Person, now: Double, asked: String) -> Hit {
        let l = Local(p.tz, now), label = status(p, l).0
        let aboutFree = ["free", "available", "busy", "working", "at work"].contains(asked)
        if aboutFree {
            let free = p.free(l, with: p.relation) && home.free(Local(home.tz, now), with: p.relation)
            if free {
                return Hit(id: "ask-\(p.id)", icon: "checkmark.circle.fill", title: "Yes, \(p.name)'s free",
                           detail: label, action: .open(p.id), color: [110, 231, 183], person: p,
                           clocks: pair(p.name, p.tz, home, now), at: now, note: label)
            }
            let next = nextWindow([home, p], mode: p.relation, after: now)
            return Hit(id: "ask-\(p.id)", icon: "clock.fill", title: "Not now: \(label.lowercased())",
                       detail: next.map { "\(p.name)'s free \(dayText($0.start, home.tz, now: now).lowercased()) at \(time($0.start, home.tz)) your time" }
                        ?? "\(clock(l)) \(ampm(l.h)) there",
                       action: next.map { .jump($0.start, pick: [p.id]) }, person: p,
                       clocks: pair(p.name, p.tz, home, now), at: now)
        }
        guard label == "Asleep" else {
            return Hit(id: "ask-\(p.id)", icon: "sun.max.fill", title: "Yes, \(p.name)'s up",
                       detail: label, action: .open(p.id), color: [255, 214, 74], person: p,
                       clocks: pair(p.name, p.tz, home, now), at: now, note: label)
        }
        var wake = now
        while wake < now + 1440 && status(p, Local(p.tz, wake)).0 == "Asleep" { wake += 15 }
        let w = Local(p.tz, wake)
        return Hit(id: "ask-\(p.id)", icon: "moon.zzz.fill", title: "No, \(p.name)'s asleep",
                   detail: "Up around \(clock(w)) \(ampm(w.h)), your \(time(wake, home.tz))",
                   action: .jump(wake, pick: [p.id]), color: [170, 170, 210], person: p,
                   clocks: pair(p.name, p.tz, home, now), at: now, note: "Up around \(clock(w)) \(ampm(w.h)), your \(time(wake, home.tz))")
    }

    /// The next time you and all of them are free together.
    private static func when(_ who: (name: String, members: [Person], tag: PersonTag?), home: Person, now: Double) -> Hit {
        let kinds = Set(who.members.map(\.relation))
        let mode = kinds.count == 1 ? kinds.first : nil
        let verb = mode == .personal ? "Talk" : "Free"
        let ids = Set(who.members.map(\.id))
        guard let w = nextWindow([home] + who.members, mode: mode, after: now) else {
            return Hit(id: "when", icon: "calendar.badge.exclamationmark", title: "No shared time with \(who.name) this week",
                       detail: "Try fewer people, or widen someone's hours", action: nil)
        }
        let open = w.start <= now
        let range = "\(time(w.start, home.tz))–\(time(w.end, home.tz))"
        var detail = open ? "Now until \(time(w.end, home.tz)) your time" : "\(dayText(w.start, home.tz, now: now)) \(range) your time"
        if who.members.count == 1, let p = who.members.first {
            detail += " · \(p.name)'s \(time(open ? now : w.start, p.tz))"
        }
        let at = open ? now : w.start
        var clocks = [HitClock(place: "You", time: open ? "Now" : time(w.start, home.tz),
                               day: open ? "until \(time(w.end, home.tz))" : dayText(w.start, home.tz, now: now))]
        if who.members.count == 1, let p = who.members.first {
            clocks.insert(HitClock(place: p.name, time: time(at, p.tz), day: dayText(at, p.tz, now: now)), at: 0)
        }
        return Hit(id: "when", icon: "calendar.badge.clock",
                   title: open ? "\(verb) with \(who.name) now" : "\(verb) with \(who.name) \(dayText(w.start, home.tz, now: now).lowercased()) at \(time(w.start, home.tz))",
                   detail: detail, action: .jump(at, pick: ids), color: [110, 231, 183],
                   person: who.members.count == 1 ? who.members.first : nil, clocks: clocks, at: at)
    }

    private static func timeIn(_ z: Zone, home: Person, now: Double) -> Hit {
        let l = Local(z.tz, now), h = Local(home.tz, now)
        let diff = Double(l.off - h.off)
        let rel = diff == 0 ? "Same time as you" : "\(dur(abs(diff))) \(diff < 0 ? "behind" : "ahead of") you"
        return Hit(id: "time-\(z.name)", icon: "globe", title: "\(clock(l)) \(ampm(l.h)) in \(z.name)",
                   detail: rel, action: nil, color: [133, 183, 235], clocks: pair(z.name, z.tz, home, now), at: now,
                   headline: "Right now · \(rel.prefix(1).lowercased() + rel.dropFirst())")
    }

    private static func jumpHit(_ j: Jump, home: Person) -> Hit {
        let mine = Local(home.tz, j.minutes)
        let day = { (tz: TimeZone) in Date(timeIntervalSince1970: j.minutes * 60).formatted(Date.FormatStyle(timeZone: tz).weekday(.abbreviated).day()) }
        if let z = j.zone, z.person?.isHome != true {
            let theirs = Local(z.tz, j.minutes)
            let whose = z.person.map { "\($0.name)'s" } ?? z.name
            return Hit(id: "jump", icon: "clock.arrow.circlepath",
                       title: z.person != nil ? "\(whose) \(clock(theirs)) \(ampm(theirs.h)) is your \(clock(mine)) \(ampm(mine.h))"
                                              : "\(clock(theirs)) \(ampm(theirs.h)) in \(whose) is \(clock(mine)) \(ampm(mine.h)) yours",
                       detail: "See everyone's sky then", action: .jump(j.minutes, pick: z.person.map { [$0.id] } ?? []),
                       color: [255, 214, 74], person: z.person,
                       clocks: [HitClock(place: z.person?.name ?? z.name, time: "\(clock(theirs)) \(ampm(theirs.h))", day: day(z.tz)),
                                HitClock(place: "You", time: "\(clock(mine)) \(ampm(mine.h))", day: day(home.tz))],
                       at: j.minutes, headline: "See everyone's sky then")
        }
        return Hit(id: "jump", icon: "clock.arrow.circlepath", title: "\(clock(mine)) \(ampm(mine.h)) your time",
                   detail: "See everyone's sky then", action: .jump(j.minutes, pick: []), color: [255, 214, 74],
                   clocks: [HitClock(place: "You", time: "\(clock(mine)) \(ampm(mine.h))", day: day(home.tz))], at: j.minutes,
                   headline: "See everyone's sky then")
    }

    private static func time(_ m: Double, _ tz: TimeZone) -> String { let l = Local(tz, m); return "\(clock(l)) \(ampm(l.h))" }

    /// Their clock and yours, right now.
    private static func pair(_ name: String, _ tz: TimeZone, _ home: Person, _ now: Double) -> [HitClock] {
        let wd = { (tz: TimeZone) in Calendar.current.shortWeekdaySymbols[Local(tz, now).wd] }
        return [HitClock(place: name, time: time(now, tz), day: wd(tz)), HitClock(place: "You", time: time(now, home.tz), day: wd(home.tz))]
    }

    /// The words left once times, days and question words are taken out: a place to look up online.
    static func placeWords(_ query: String) -> String? {
        var q = " " + query.lowercased().trimmingCharacters(in: .punctuationCharacters) + " "
        q = q.replacing(/\d{1,2}(?::\d{2})?\s*(?:am|pm|a|p)?/) { _ in " " }
        for w in ["what", "what's", "whats", "is", "it", "the", "time", "in", "at", "for", "today", "tonight", "tomorrow", "noon", "midnight",
                  "mon", "tue", "wed", "thu", "fri", "sat", "sun", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] {
            q = q.replacingOccurrences(of: " \(w) ", with: " ")
        }
        let rest = q.split(separator: " ").joined(separator: " ")
        return rest.count >= 3 ? rest : nil
    }
}

// MARK: - Shared UI

/// Does what a result says: springs the sky (planning with whoever it named), opens a page, or shows a tag.
@MainActor func perform(_ action: Hit.Action, people: People, model: Scrubber, open: (UUID) -> Void) {
    switch action {
    case .jump(let m, let pick):
        if !pick.isEmpty { people.picked = pick.count == people.list.count - 1 ? [] : pick }
        model.springTo(m, response: 0.6)
    case .open(let id): open(id)
    case .scope(let id): people.setScope(id)
    }
}

/// Places from Apple Maps for words the offline table doesn't know ("Visakhapatnam 3pm", "Bend Oregon").
@MainActor @Observable final class PlaceLookup {
    private(set) var zones: [Zone] = []
    private var asked: Set<String> = []

    func look(for query: String, people: [Person]) async {
        guard let words = Ask.placeWords(query), !asked.contains(words),
              JumpParser.zone(in: " \(words) ", people: people, extra: zones) == nil else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        asked.insert(words)
        if let item = await findPlace(words), let tz = item.timeZone {
            zones.append(Zone(name: cityName(item), tz: tz))
            // Its own words find it too, so "vizag 3pm" works after "Visakhapatnam" was found as "vizag".
            if words.lowercased() != cityName(item).lowercased() { zones.append(Zone(name: words, tz: tz)) }
        }
    }
}

