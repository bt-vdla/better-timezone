import SwiftUI
import Synchronization

// MARK: - Places anywhere

/// A clock to read a time on: one of your people, or any city, country or time zone.
struct Zone: Equatable {
    let name: String
    let tz: TimeZone
    var person: Person? = nil
    /// What it's typed as, when that isn't its name ("kzn" for "Kazan (KZN)").
    var key: String? = nil
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
        // Time-zone abbreviations: the system's, then the ones it lacks ("GYT"), named in full ("Guyana Time").
        for (abbr, id) in TimeZone.abbreviationDictionary.merging(extraAbbreviations, uniquingKeysWith: { _, extra in extra }) {
            let name = TimeZone(identifier: id)?.localizedName(for: .generic, locale: en) ?? abbr
            add(abbr, name, id)
        }
        // Airport codes ("sfo 3pm", "7am bom to lhr"), after every name so "Paris" stays Paris; shown with their city.
        for (code, a) in Airports.byCode where !Airports.words.contains(code.lowercased()) {
            if let tz = a.tz, t[code.lowercased()] == nil { t[code.lowercased()] = Zone(name: a.label, tz: tz, key: code.lowercased()) }
        }
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

    /// The table, for the corrector's vocabulary.
    static var spacedTable: [String: Zone] { table }

    /// Abbreviations people use that the system doesn't list (or lists wrongly: WIT is eastern Indonesia).
    private static let extraAbbreviations: [String: String] = [
        "GYT": "America/Guyana", "VET": "America/Caracas", "BOT": "America/La_Paz", "ECT": "America/Guayaquil",
        "UYT": "America/Montevideo", "PYT": "America/Asuncion", "SRT": "America/Paramaribo", "GFT": "America/Cayenne",
        "AWST": "Australia/Perth", "ACST": "Australia/Adelaide", "ACDT": "Australia/Adelaide", "AEST": "Australia/Sydney",
        "AEDT": "Australia/Sydney", "NPT": "Asia/Kathmandu", "MYT": "Asia/Kuala_Lumpur", "WIB": "Asia/Jakarta",
        "WITA": "Asia/Makassar", "WIT": "Asia/Jayapura", "SAST": "Africa/Johannesburg", "AFT": "Asia/Kabul",
        "AZT": "Asia/Baku", "UZT": "Asia/Tashkent", "ALMT": "Asia/Almaty", "BTT": "Asia/Thimphu", "MMT": "Asia/Yangon",
        "KGT": "Asia/Bishkek", "TJT": "Asia/Dushanbe", "TMT": "Asia/Ashgabat", "YEKT": "Asia/Yekaterinburg",
        "NOVT": "Asia/Novosibirsk", "KRAT": "Asia/Krasnoyarsk", "IRKT": "Asia/Irkutsk", "YAKT": "Asia/Yakutsk",
        "VLAT": "Asia/Vladivostok", "MAGT": "Asia/Magadan", "PETT": "Asia/Kamchatka", "SAMT": "Europe/Samara",
        "FJT": "Pacific/Fiji", "CHST": "Pacific/Guam", "SST": "Pacific/Pago_Pago", "TOT": "Pacific/Tongatapu",
        "MVT": "Indian/Maldives", "MUT": "Indian/Mauritius", "SCT": "Indian/Mahe", "CHAST": "Pacific/Chatham",
        "BDT": "Asia/Dhaka", "IST": "Asia/Kolkata", "GST": "Asia/Dubai",
        // Short forms people type, and the rest of the world's usual ones.
        "CT": "America/Chicago", "MT": "America/Denver", "AKT": "America/Anchorage", "HAST": "Pacific/Honolulu",
        "BJT": "Asia/Shanghai", "ULAT": "Asia/Ulaanbaatar", "TLT": "Asia/Dili", "BNT": "Asia/Brunei", "OMST": "Asia/Omsk",
        "IDT": "Asia/Jerusalem", "LHST": "Australia/Lord_Howe", "NZT": "Pacific/Auckland", "TAHT": "Pacific/Tahiti",
        "MART": "Pacific/Marquesas", "GAMT": "Pacific/Gambier", "NCT": "Pacific/Noumea", "VUT": "Pacific/Efate",
        "SBT": "Pacific/Guadalcanal", "PGT": "Pacific/Port_Moresby", "GILT": "Pacific/Tarawa", "PWT": "Pacific/Palau",
        "CKT": "Pacific/Rarotonga", "TKT": "Pacific/Fakaofo", "WSST": "Pacific/Apia", "NFT": "Pacific/Norfolk",
        "CXT": "Indian/Christmas", "CCT": "Indian/Cocos", "RET": "Indian/Reunion", "IOT": "Indian/Chagos",
        "AZOT": "Atlantic/Azores", "CVT": "Atlantic/Cape_Verde", "FKST": "Atlantic/Stanley",
    ]

    static func zone(named name: String) -> Zone? {
        table[name.lowercased().folding(options: .diacriticInsensitive, locale: nil)]
    }

    /// Every place named in a padded, folded query, with where it sits. Overlaps are sorted out by the caller.
    static func all(in q: String) -> [(zone: Zone, key: String, range: Range<String.Index>)] {
        let words = Set(q.split(separator: " ").map(String.init))
        return words.flatMap { byFirstWord[$0] ?? [] }.flatMap { key, zone in
            q.ranges(of: " \(key) ").map { (zone, key, inner($0, in: q)) }
        }
    }

    /// Names by their first word ("new" → "new york", "new delhi"…), so a lookup only checks names that could be there.
    private static let byFirstWord: [String: [(key: String, zone: Zone)]] = Dictionary(
        grouping: table.map { (key: $0.key, zone: $0.value) },
        by: { String($0.key.split(separator: " ").first ?? "") })

    /// A " key " match without its padding spaces, so neighbouring words don't overlap.
    static func inner(_ r: Range<String.Index>, in q: String) -> Range<String.Index> {
        q.index(after: r.lowerBound)..<q.index(before: r.upperBound)
    }

    /// The longest place named in a padded query (" india 3pm "), and the words it used.
    static func find(in padded: String) -> (zone: Zone, key: String)? {
        let q = padded.folding(options: .diacriticInsensitive, locale: nil)
        var best: (Zone, String)?
        for (zone, key, _) in all(in: q) where key.count > (best?.1.count ?? 1) { best = (zone, key) }
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
    /// The clock to convert it to: "7am Guyana to India".
    var to: Zone? = nil
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
        if let z = extra.first(where: { padded.contains(" \($0.key ?? $0.name.lowercased()) ") }) { return (z, [z.key ?? z.name.lowercased()]) }
        return nil
    }

    /// Words that mean your own clock, when a question converts between two.
    private static let mine = ["my time", "your time", "local time", "my", "me", "mine", "here", "local"]

    /// Every person, place and "my time" named in the question, longest first where they overlap, in reading order.
    /// A person beats a place on the same words; matched by their city, the clock is labelled with the city.
    static func zones(in q: String, people: [Person], extra: [Zone], home: Person) -> [(zone: Zone, range: Range<String.Index>)] {
        func fold(_ s: String) -> String { s.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        var found: [(zone: Zone, length: Int, rank: Int, range: Range<String.Index>)] = []
        for p in people {
            let keys = [(p.name, p.name), (p.city, p.city), (p.code, p.name), (p.contact?.name ?? "", p.name), (p.contact?.firstName ?? "", p.name)]
            for (key, label) in keys where key.count >= 2 {
                for r in q.ranges(of: " \(fold(key)) ") {
                    found.append((Zone(name: label, tz: p.tz, person: p), key.count, 2, Places.inner(r, in: q)))
                }
            }
        }
        for key in mine { for r in q.ranges(of: " \(key) ") { found.append((home.zone, key.count, 1, Places.inner(r, in: q))) } }
        for (zone, key, range) in Places.all(in: q) { found.append((zone, key.count, 0, range)) }
        for z in extra {
            let k = z.key ?? fold(z.name)
            for r in q.ranges(of: " \(k) ") { found.append((z, k.count, 0, Places.inner(r, in: q))) }
        }
        var kept: [(zone: Zone, range: Range<String.Index>)] = []
        for f in found.sorted(by: { ($0.length, $0.rank) > ($1.length, $1.rank) })
        where !kept.contains(where: { $0.range.overlaps(f.range) }) {
            kept.append((f.zone, f.range))
        }
        return kept.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func parse(_ query: String, people: [Person], now: Double, extra: [Zone] = []) -> Jump? {
        var q = " " + query.lowercased().folding(options: .diacriticInsensitive, locale: nil) + " "
        for (a, b) in [("→", " to "), ("->", " to "), ("=", " to "), ("a.m.", "am"), ("p.m.", "pm"), ("?", " "), (",", " "), ("!", " ")] {
            q = q.replacingOccurrences(of: a, with: b)
        }
        q = " " + q.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + " "
        guard q.count > 2, let home = people.first(where: \.isHome) ?? people.first else { return nil }
        // A code typed in capitals counts even when it's also a word ("SEA", "CAN").
        let extra = extra + query.split(whereSeparator: { !$0.isLetter }).compactMap { w -> Zone? in
            guard w.count == 3, w == w.uppercased(), let a = Airports.byCode[String(w)], let tz = a.tz else { return nil }
            return Zone(name: a.label, tz: tz, key: w.lowercased())
        }

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

        // Whose clock, and which clock to convert to. With two named, the one beside the time is where the time is
        // ("7am guyana to india", "india time for 7am guyana", "in india when it's 9am in new york").
        q = q.replacing(/(\d)\s+(am|pm|a|p)\b/) { "\($0.1)\($0.2)" }
        let named = zones(in: q, people: people, extra: extra, home: home)
        let timeAt = q.firstMatch(of: /\s\d{1,2}(?::\d{2})?(?:am|pm|a|p)?\s/)?.range
            ?? q.range(of: " noon ") ?? q.range(of: " midnight ")
        var from: Zone?, to: Zone?
        if named.count >= 2 {
            var (a, b) = (named[0], named[1])
            if let t = timeAt {
                func gap(_ r: Range<String.Index>) -> Int {
                    r.lowerBound >= t.upperBound ? q.distance(from: t.upperBound, to: r.lowerBound) : q.distance(from: r.upperBound, to: t.lowerBound)
                }
                if gap(b.range) < gap(a.range) { (a, b) = (b, a) }
            }
            (from, to) = (a.zone, b.zone)
        } else if let only = named.first {
            // "3pm to tokyo": your 3pm, in Tokyo. "3pm in tokyo" stays Tokyo's 3pm.
            let before = q[..<only.range.lowerBound].trimmingCharacters(in: .whitespaces)
            let converting = before.hasSuffix(" to") || before.hasSuffix(" into") || before == "to" || before == "into"
            if converting, let t = timeAt, t.upperBound <= only.range.lowerBound, only.zone.person?.isHome != true {
                (from, to) = (home.zone, only.zone)
            } else {
                from = only.zone
            }
        }
        for n in named.reversed() { q.replaceSubrange(n.range, with: " ") }

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
        if q.contains(" noon ") { hour = 12; suffix = "pm" }
        if q.contains(" midnight ") { hour = 0; suffix = "am" }
        if hour == nil, let m = q.firstMatch(of: /\s(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?\s/) {
            hour = Int(m.1)
            minute = m.2.flatMap { Int($0) } ?? 0
            suffix = m.3.map { $0.hasPrefix("a") ? "am" : "pm" }
        }
        guard hour != nil || dayWord != nil || weekday != nil else { return nil }
        guard (hour ?? 0) < 24, minute < 60 else { return nil }

        let tz = from?.tz ?? home.tz
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
        return Jump(minutes: m, zone: from, to: to.flatMap { $0.tz.identifier == tz.identifier && $0.name == from?.name ? nil : $0 })
    }
}

// MARK: - Answers

/// One line of a search result: an answer, a time, a person or a tag, and what tapping it does.
struct Hit: Identifiable, Sendable {
    enum Action: Sendable { case jump(Double, pick: Set<UUID>), open(UUID), scope(String), fair(Fair.Slot, pick: Set<UUID>) }
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
    /// How far the second clock is from the first: "+9h 30m".
    var gap: String? = nil
    /// A clock change worth knowing about: "London's clocks went back 1h yesterday: 5h 30m apart now, was 4h 30m".
    var cue: String? = nil
}

struct HitClock: Hashable, Sendable {
    let place: String
    let time: String
    let day: String
}

/// Plain questions about your people, answered from their clocks: "is amma awake", "when can I speak to family",
/// "what time is it in tokyo". No model; patterns and the same maths as the rest of Skies.
enum Ask {
    /// The last answer: the notch asks every frame while it's open, but answers only change with the text or the minute.
    private static let last = Mutex<(key: String, hits: [Hit], readAs: String?)?>(nil)

    static func hits(_ query: String, people: [Person], now: Double, extra: [Zone] = []) -> [Hit] {
        resolve(query, people: people, now: now, extra: extra).hits
    }

    /// The question as Skies read it, when it corrected a typo ("7am est to ist" for "7am est toi ist").
    static func readAs(_ query: String, people: [Person], now: Double, extra: [Zone] = []) -> String? {
        resolve(query, people: people, now: now, extra: extra).readAs
    }

    private static func resolve(_ query: String, people: [Person], now: Double, extra: [Zone]) -> (hits: [Hit], readAs: String?) {
        let key = "\(query)|\(Int(now))|\(extra.map(\.name))|" + people.map { "\($0.id)\($0.label)\($0.tagList)\($0.tzID)" }.joined()
        if let hit = last.withLock({ $0?.key == key ? $0 : nil }) { return (hit.hits, hit.readAs) }
        // Every likely reading goes through Ask itself; the one it understands best wins. Each word left unknown
        // and each correction made cost a little, so the original wins whenever it already makes sense.
        var best: (hits: [Hit], text: String, score: Double)?
        for r in Typos.readings(query, people: people) {
            // Cheapest first: once even a perfect answer couldn't beat the best so far, nothing later can.
            if let b = best, 4 - 0.5 * r.cost <= b.score { break }
            let hits = answer(r.text, people: people, now: now, extra: extra)
            let score = understanding(hits) - 0.5 * r.cost - 0.6 * Double(r.unknown)
            if best == nil || score > best!.score + 0.001 { best = (hits, r.text, score) }
        }
        let hits = best?.hits ?? [], text = best?.text ?? query
        let readAs = text.lowercased() == query.lowercased().trimmingCharacters(in: .whitespaces) || hits.isEmpty ? nil : text
        last.withLock { $0 = (key, hits, readAs) }
        return (hits, readAs)
    }

    /// How well Ask understood a reading: an answer beats a time beats a list of names.
    private static func understanding(_ hits: [Hit]) -> Double {
        guard let top = hits.first else { return 0 }
        if top.id == "convert" || top.id == "when" || top.id.hasPrefix("ask-") || top.id.hasPrefix("dst-") || top.id.hasPrefix("after-")
            || top.id.hasPrefix("fair-") { return 4 }
        if top.id == "jump" || top.id.hasPrefix("time-") { return 3 }
        return 1 + min(1, Double(hits.count) * 0.1)
    }

    private static func answer(_ query: String, people: [Person], now: Double, extra: [Zone]) -> [Hit] {
        let q = query.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "?!.,")))
            // Possessives name the person ("sharru's clocks", "partners' clocks"); "what's" and "it's" stay.
            .replacing(/\b(?!(?:what|it|that|who|where|when|how|let|here|there)'s)(\w+)'s\b/) { $0.output.1 }
            .replacing(/(\w+s)'(?=\s|$)/) { $0.output.1 }
        guard !q.isEmpty, let home = people.first(where: \.isHome) ?? people.first else { return [] }
        var out: [Hit] = []
        let jump = JumpParser.parse(q, people: people, now: now, extra: extra)

        // Clock-change questions ("when do clocks change in london", "does india have dst") first; then a conversion
        // ("7am guyana to india", "time in india when it's 9am in new york").
        if let f = fairTimes(q, people: people, now: now, home: home) {
            out += f
        } else if let a = afterChange(q, people: people, extra: extra, now: now, home: home) {
            out.append(a)
        } else if let d = daylight(q, people: people, extra: extra, now: now) {
            out.append(d)
        } else if let jump, jump.to != nil {
            out.append(jumpHit(jump, home: home, now: now))
        } else if let m = q.firstMatch(of: /^(?:is|are)\s+(.+?)\s+(awake|up|asleep|sleeping|free|available|around|busy|working|at work|online)$/),
           let who = target(String(m.1), people) {
            out += who.members.prefix(6).map { awake($0, home: home, now: now, asked: String(m.2)) }
        } else if let phrase = nowPhrase(q), let who = target(phrase, people) {
            out += who.members.prefix(6).map { awake($0, home: home, now: now, asked: "free") }
        } else if let phrase = whenPhrase(q), let who = target(phrase, people) {
            out.append(when(who, home: home, now: now))
        } else if let m = q.firstMatch(of: /^(?:what(?:'s| is)?\s+)?(?:the\s+)?time\s+(?:is it\s+)?(?:in|for|at)\s+(.+)$/) {
            let padded = " \(m.1) "
            if let z = JumpParser.zone(in: padded, people: people, extra: extra)?.zone { out.append(timeIn(z, home: home, now: now)) }
        }

        if let jump, jump.to == nil {
            out.append(jumpHit(jump, home: home, now: now))
        } else if jump == nil, out.isEmpty, let z = JumpParser.zone(in: " \(q) ", people: people, extra: extra)?.zone, z.person == nil {
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
        for p in people where !named.contains(p.id) && !p.isHome {
            let fields = [p.name, p.city, p.code, p.contact?.name ?? ""].map { $0.lowercased() }
            guard fields.contains(where: { f in f.hasPrefix(q) || words.contains { f.hasPrefix($0) } }) else { continue }
            let l = Local(p.tz, now)
            out.append(Hit(id: "person-\(p.id)", icon: "person.crop.circle", title: p.name,
                           detail: "\(hm(l)) · \(p.city) · \(status(p, l).0)", action: .open(p.id), person: p))
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

    private static let verbs = "(?:speak|talk|call|meet|chat|ring|reach|catch|see|phone|facetime|video call|catch up)"

    /// The who in "can I call … now", "is it a good time to call …", "ok to ring … right now": asked about this minute.
    private static func nowPhrase(_ q: String) -> String? {
        let now = "(?:\\s+(?:now|right now|rn|at the moment|atm))?"
        let patterns = [
            "^(?:can|could|should|shall|may)\\s+(?:i|we)\\s+\(verbs)(?:\\s+(?:to|with|up with))?\\s+(.+?)\(now)$",
            "^(?:is\\s+(?:it|now|this)\\s+)?(?:a\\s+)?(?:good|ok|okay|fine|alright)\\s+(?:time\\s+)?to\\s+\(verbs)(?:\\s+(?:to|with))?\\s+(.+?)\(now)$",
        ]
        for p in patterns {
            if let r = try? Regex(p), let m = q.firstMatch(of: r), let cap = m.output[1].substring { return String(cap) }
        }
        return nil
    }

    /// The who in "when can I speak to …", "when is … free", "best time to call …", "call …".
    private static func whenPhrase(_ q: String) -> String? {
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
            let meeting = BusyTimes.covers(now)
            let free = p.free(l, with: p.relation) && home.free(Local(home.tz, now), with: p.relation) && !meeting
            if free {
                return Hit(id: "ask-\(p.id)", icon: "checkmark.circle.fill", title: "Yes, \(p.name)'s free",
                           detail: label, action: .open(p.id), color: [110, 231, 183], person: p,
                           clocks: pair(p.name, p.tz, home, now), at: now, note: label)
            }
            let next = nextWindow([home, p], mode: p.relation, after: now)
            return Hit(id: "ask-\(p.id)", icon: "clock.fill", title: meeting ? "Not now: you're in a meeting" : "Not now: \(label.lowercased())",
                       detail: next.map { "\(p.name)'s free \(dayText($0.start, home.tz, now: now).lowercased()) at \(time($0.start, home.tz)) your time" }
                        ?? "\(hm(l)) there",
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
                   detail: "Up around \(hm(w)), your \(time(wake, home.tz))",
                   action: .jump(wake, pick: [p.id]), color: [170, 170, 210], person: p,
                   clocks: pair(p.name, p.tz, home, now), at: now, note: "Up around \(hm(w)), your \(time(wake, home.tz))")
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
        return Hit(id: "time-\(z.name)", icon: "globe", title: "\(hm(l)) in \(z.name)",
                   detail: rel, action: nil, color: [133, 183, 235], clocks: pair(z.name, z.tz, home, now), at: now,
                   headline: "Right now · \(rel.prefix(1).lowercased() + rel.dropFirst())",
                   gap: Clocks.signed(Clocks.gap(z.tz, home.tz, now)),
                   cue: Clocks.cue((z.name, z.tz), ("your", home.tz), at: now, now: now))
    }

    private static func jumpHit(_ j: Jump, home: Person, now: Double) -> Hit {
        let mine = Local(home.tz, j.minutes)
        // How far from now: "In 5h", "2h ago", "Now". It's what the question was really about.
        let gap = (j.minutes - now).rounded()
        let when = abs(gap) < 1 ? "Now" : gap > 0 ? "In \(dur(gap))" : "\(dur(-gap)) ago"
        // "Tue 27", and "· summer time" when that clock is on it then.
        let day = { (tz: TimeZone) in
            Date(timeIntervalSince1970: j.minutes * 60).formatted(Date.FormatStyle(timeZone: tz).weekday(.abbreviated).day())
                + (Clocks.season(tz, j.minutes).map { " · \($0)" } ?? "")
        }
        if let to = j.to, let from = j.zone {
            let a = Local(from.tz, j.minutes), b = Local(to.tz, j.minutes)
            let isYou = { (z: Zone) in z.person?.isHome == true && z.name == z.person?.name }
            /// "your 7:00 AM", "Kate's 9:00 AM", "7:00 AM in Guyana".
            func say(_ z: Zone, _ l: Local) -> String {
                let t = "\(hm(l))"
                if isYou(z) { return "your \(t)" }
                if let p = z.person, p.name == z.name { return "\(p.name)\(p.name.hasSuffix("s") ? "'" : "'s") \(t)" }
                return "\(t) in \(z.name)"
            }
            let line = "\(say(from, a)) is \(say(to, b))"
            let yoursToo = !isYou(from) && !isYou(to) && from.tz.identifier != home.tz.identifier && to.tz.identifier != home.tz.identifier
            let people = Set([from.person, to.person].compactMap { $0 }.filter { !$0.isHome }.map(\.id))
            return Hit(id: "convert", icon: "arrow.left.arrow.right",
                       title: line.prefix(1).uppercased() + line.dropFirst(),
                       detail: yoursToo ? "\(when) · your \(hm(mine)), \(day(home.tz))" : when,
                       action: .jump(j.minutes, pick: people), color: [255, 214, 74], person: from.person ?? to.person,
                       clocks: [HitClock(place: isYou(from) ? "You" : from.name, time: "\(hm(a))", day: day(from.tz)),
                                HitClock(place: isYou(to) ? "You" : to.name, time: "\(hm(b))", day: day(to.tz))],
                       at: j.minutes,
                       headline: yoursToo ? "\(when) · your \(hm(mine)), \(day(home.tz))" : when,
                       gap: Clocks.signed(Clocks.gap(from.tz, to.tz, j.minutes)),
                       cue: Clocks.cue((isYou(from) ? "your" : from.name, from.tz), (isYou(to) ? "your" : to.name, to.tz), at: j.minutes, now: now))
        }
        if let z = j.zone, z.person?.isHome != true {
            let theirs = Local(z.tz, j.minutes)
            let whose = z.person.map { "\($0.name)'s" } ?? z.name
            return Hit(id: "jump", icon: "clock.arrow.circlepath",
                       title: z.person != nil ? "\(whose) \(hm(theirs)) is your \(hm(mine))"
                                              : "\(hm(theirs)) in \(whose) is \(hm(mine)) yours",
                       detail: when, action: .jump(j.minutes, pick: z.person.map { [$0.id] } ?? []),
                       color: [255, 214, 74], person: z.person,
                       clocks: [HitClock(place: z.person?.name ?? z.name, time: "\(hm(theirs))", day: day(z.tz)),
                                HitClock(place: "You", time: "\(hm(mine))", day: day(home.tz))],
                       at: j.minutes, headline: when,
                       gap: Clocks.signed(Clocks.gap(z.tz, home.tz, j.minutes)),
                       cue: Clocks.cue((z.person?.name ?? z.name, z.tz), ("your", home.tz), at: j.minutes, now: now))
        }
        return Hit(id: "jump", icon: "clock.arrow.circlepath", title: "\(hm(mine)) your time",
                   detail: when, action: .jump(j.minutes, pick: []), color: [255, 214, 74],
                   clocks: [HitClock(place: "You", time: "\(hm(mine))", day: day(home.tz))], at: j.minutes,
                   headline: when)
    }

    /// "Find 30 min for team this week", "best time for a 1h call with kate and om", "schedule a call with family
    /// tomorrow": the fairest few slots where everyone's free for the whole meeting.
    private static func fairTimes(_ q: String, people: [Person], now: Double, home: Person) -> [Hit]? {
        let r = /^(?:can you\s+)?(?:(find|book|schedule|plan|suggest|pick|set up|arrange)\s+(?:me\s+|us\s+)?|(?:the\s+)?(?:best|fairest|good)\s+time\s+(?:for\s+)?)?(?:(?:a|an)\s+)?(?:(\d+(?:\.\d+)?|an|a|one|half an)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)\s+)?(?:(slot|time|call|meeting|chat|catch ?up|sync)\s+)?(?:for|with)\s+(.+?)(?:\s+(this week|next week|tomorrow|today|this weekend|over the weekend))?$/
        guard let m = q.firstMatch(of: r) else { return nil }
        // Plain "time for tokyo" or "call with kate" belong elsewhere: it needs a verb, a length, a "meeting" or a range.
        let meetingWord = m.output.4.map { ["slot", "meeting", "sync"].contains(String($0)) } ?? false
        guard m.output.1 != nil || m.output.2 != nil || meetingWord || m.output.6 != nil
                || q.hasPrefix("best time") || q.hasPrefix("fairest") else { return nil }
        guard let who = target(String(m.output.5), people) else { return nil }
        var minutes = 30.0
        if let n = m.output.2 {
            let amount = Double(n) ?? (n == "half an" ? 0.5 : 1)
            minutes = (m.output.3?.hasPrefix("h") == true ? amount * 60 : amount)
        }
        let today = dayStart(home.tz, now), wd = Local(home.tz, now).wd
        let toMonday = Double((8 - wd) % 7 == 0 ? 7 : (8 - wd) % 7), toSaturday = Double((6 - wd + 7) % 7)
        let range: ClosedRange<Double>
        switch m.output.6.map(String.init) {
        case "today": range = now...(today + 1440)
        case "tomorrow": range = (today + 1440)...(today + 2880)
        case "next week": range = (today + toMonday * 1440)...(today + (toMonday + 7) * 1440)
        case "this weekend", "over the weekend": range = (today + toSaturday * 1440)...(today + (toSaturday + 2) * 1440)
        default: range = now...(now + 7 * 1440)
        }
        let kinds = Set(who.members.map(\.relation))
        let mode = kinds.count == 1 ? kinds.first : nil
        let team = [home] + who.members
        let slots = Fair.find(team, minutes: minutes, in: max(now, range.lowerBound)...range.upperBound, mode: mode)
        let length = dur(minutes)
        guard !slots.isEmpty else {
            return [Hit(id: "fair-none", icon: "calendar.badge.exclamationmark", title: "No \(length) when everyone's free",
                        detail: "Try a shorter call, fewer people, or a different week", action: nil)]
        }
        let pick = Set(who.members.map(\.id))
        return slots.enumerated().map { i, slot in
            let day = Clocks.day(slot.start, home.tz, now: now)
            let range = timeRange(slot.start...slot.end, home)
            let theirs = who.members.map { p in
                let s = slot.stretch[p.id] ?? 0
                let (lo, _) = band(p, mode)
                let early = Local(p.tz, slot.start).f < lo
                return "\(p.name) \(hm(Local(p.tz, slot.start)))" + (s > 0 ? " (\(early ? "early" : "late"))" : "")
            }
            let stretched = team.filter { (slot.stretch[$0.id] ?? 0) > 0 }
            let headline = stretched.isEmpty ? "Inside everyone's day"
                : stretched.count == 1 ? "\(stretched[0].isHome ? "You stretch" : "\(stretched[0].name) stretches") \(dur((slot.stretch[stretched[0].id] ?? 0) * 60))"
                : "\(stretched.count) people stretch a little"
            return Hit(id: "fair-\(i)", icon: i == 0 ? "sparkles" : "calendar",
                       title: "\(day.prefix(1).uppercased() + day.dropFirst()) \(range)",
                       detail: theirs.joined(separator: " · "),
                       action: .fair(slot, pick: pick), color: [110, 231, 183],
                       person: who.members.count == 1 ? who.members.first : nil,
                       clocks: i == 0 ? [HitClock(place: "You", time: hm(Local(home.tz, slot.start)), day: day)]
                            + who.members.prefix(2).map { HitClock(place: $0.name, time: hm(Local($0.tz, slot.start)), day: Clocks.day(slot.start, $0.tz, now: now)) } : [],
                       at: slot.start,
                       headline: i == 0 ? "\(length) · \(headline)" : nil,
                       note: who.members.count > 2 ? theirs.joined(separator: " · ") : nil)
        }
    }

    private static func band(_ p: Person, _ mode: Person.Kind?) -> (Double, Double) { Fair.band(p, mode: mode) }

    /// "After DST, what's my time vs IST", "when dst ends, gap to new york", "after the clocks go back, 9am new york in
    /// india", "once summer time starts in london": the gap after the next change, or a time read after it.
    private static func afterChange(_ q: String, people: [Person], extra: [Zone], now: Double, home: Person) -> Hit? {
        let change = "(?:dst|daylight savings?(?: time)?|daylight time|summer time|winter time|standard time|the clocks?|clocks?|the time change|time change)"
        let ends = "(?:ends?|stops?|is over|finishes|go(?:es)? back|fall back|falls back|change|changes)"
        let starts = "(?:starts?|begins?|kicks in|go(?:es)? forward|spring forward|springs forward)"
        let pattern = "\\b(?:after|once|when|post|from|following)\\s+(?:(?:(.+?)(?:'s|s')?\\s+)?\(change)(?:\\s+(\(ends)|\(starts)))?|\(change)\\s+(\(ends)|\(starts)))\\b"
        // "When do clocks change…" asks when, not what happens after: that's `daylight`'s.
        guard q.firstMatch(of: /^when\s+(?:do|does|did|will|is|are)\b/) == nil,
              let r = try? Regex(pattern), let m = q.firstMatch(of: r) else { return nil }
        let phrase = String(q[m.range]).lowercased()
        let direction: Int? = phrase.firstMatch(of: try! Regex(starts)) != nil || phrase.contains("summer time start") ? 1
            : phrase.firstMatch(of: try! Regex("(?:ends?|stops?|is over|finishes|back)")) != nil ? -1 : nil
        // The rest names the clocks: "my time", "ist", "kate", "new york".
        // Whose clocks, when the phrase named them ("after kate's clocks go back") stays in.
        let owner = m.output[1].substring.map { " " + String($0) } ?? ""
        var rest = " " + q.replacingCharacters(in: m.range, with: owner + " ").replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "?", with: " ") + " "
        for filler in ["what will", "what's", "whats", "what is", "will be", "be", "in relation to", "relative to", "compared to",
                       "compared with", "versus", "vs", "the gap", "gap", "difference", "between", "and", "with", "to", "how far",
                       "ahead", "behind", "of", "the"] {
            rest = rest.replacingOccurrences(of: " \(filler) ", with: " ")
        }
        let named = JumpParser.zones(in: " " + rest.trimmingCharacters(in: .whitespaces) + " ", people: people, extra: extra, home: home)
        var clocks: [Zone] = []
        for z in named.map(\.zone) + [home.zone] where !clocks.contains(where: { $0.tz.identifier == z.tz.identifier }) { clocks.append(z) }
        // The change meant: the soonest, in the asked direction, on any clock in the question.
        let next = clocks.compactMap { z in
            Clocks.changes(z.tz, from: now, to: now + 400 * 1440).first { direction == nil || ($0.shift > 0) == (direction! > 0) }.map { (z, $0) }
        }.min { $0.1.at < $1.1.at }
        let isYou = { (z: Zone) in z.person?.isHome == true }
        let label = { (z: Zone) in isYou(z) ? "You" : z.name }
        guard let (who, c) = next else {
            // Named even when it shares your clock (IST when you're in India).
            var others: [String] = []
            for z in named.map(\.zone) where !isYou(z) && !others.contains(z.name) { others.append(z.name) }
            return Hit(id: "after-none", icon: "clock.badge.checkmark",
                       title: others.isEmpty ? "Your clock doesn't change" : "No clock change ahead for you or \(ListFormatter.localizedString(byJoining: others))",
                       detail: others.isEmpty ? "Always \(Clocks.utc(Clocks.offset(home.tz, now)))" : "The gap stays as it is", action: nil, color: [133, 183, 235])
        }
        let when = Clocks.day(c.at, who.tz, now: now)
        let whose = isYou(who) ? "Your" : Clocks.owner(who.name)
        let reason = "\(whose) clocks \(Clocks.move(c.shift)) \(when)"
        // With a time, read it on the first day after the change.
        if let j = JumpParser.parse(rest, people: people, now: c.at + 1, extra: extra), j.zone != nil || j.to != nil {
            var hit = jumpHit(j, home: home, now: now)
            hit.cue = reason
            return hit
        }
        // Otherwise the gap after, against the gap now.
        guard let other = clocks.first(where: { $0.tz.identifier != home.tz.identifier }) ?? (isYou(who) ? nil : who) else {
            let off = Clocks.offset(home.tz, c.at + 1)
            return Hit(id: "after-you", icon: "clock.arrow.2.circlepath", title: "\(reason.prefix(1).uppercased() + reason.dropFirst())",
                       detail: "You'll be \(Clocks.utc(off)), from \(Clocks.utc(Clocks.offset(home.tz, now)))",
                       action: .jump(c.at + 1, pick: []), color: [255, 214, 74],
                       clocks: [HitClock(place: "You now", time: Clocks.utc(Clocks.offset(home.tz, now)), day: Clocks.season(home.tz, now) ?? "standard"),
                                HitClock(place: "From \(when)", time: Clocks.utc(off), day: Clocks.season(home.tz, c.at + 1) ?? "standard")],
                       at: c.at + 1, headline: reason, gap: Clocks.signed(c.shift))
        }
        // Against the gap just before that change: "once summer time starts" means compared with winter, not today.
        let after = Clocks.gap(home.tz, other.tz, c.at + 1), before = Clocks.gap(home.tz, other.tz, c.at - 1)
        let today = Clocks.gap(home.tz, other.tz, now)
        let side = { (g: Int) in g == 0 ? "on your time" : "\(dur(Double(abs(g)))) \(g > 0 ? "ahead of" : "behind") you" }
        let title = after == before ? "Still \(side(after)) after \(when)" : "After \(when), \(other.name) is \(side(after))"
        let then = c.at + 1
        return Hit(id: "after-\(other.name)", icon: "clock.arrow.2.circlepath", title: title,
                   detail: "\(today == before ? "Now" : "Before then") \(side(before)). \(reason.prefix(1).uppercased() + reason.dropFirst())",
                   action: .jump(then, pick: other.person.map { [$0.id] } ?? []), color: [255, 214, 74], person: other.person,
                   clocks: [HitClock(place: "You", time: Clocks.utc(Clocks.offset(home.tz, then)), day: Clocks.season(home.tz, then) ?? "standard"),
                            HitClock(place: label(other), time: Clocks.utc(Clocks.offset(other.tz, then)), day: Clocks.season(other.tz, then) ?? "standard")],
                   at: then, headline: title, gap: Clocks.signed(after),
                   cue: after == before ? reason : "\(reason): \(Clocks.apart(after)) then, \(dur(Double(abs(before)))) \(today == before ? "now" : "before")")
    }

    /// "When do clocks change in London", "does India have DST", "is New York on daylight time", "dst sydney".
    private static func daylight(_ q: String, people: [Person], extra: [Zone], now: Double) -> Hit? {
        let dst = "(?:dst|daylight savings?(?: time)?|daylight time|summer time|winter time|standard time|clock changes?|time changes?)"
        let verbs = "(?:change(?: (?:its|their|the))? (?:clocks?|time)|go (?:back|forward)|spring forward|fall back|switch(?: to .+)?)"
        let asking: [(String, Bool)] = [   // pattern, and whether it's a yes/no "is it on daylight time now"
            ("^when (?:do|does|will|did) (?:the )?clocks? (?:change|go (?:back|forward)|spring forward|fall back)(?: in| for)? (.+)$", false),
            ("^when (?:do|does|will|did) (.+?) \(verbs)$", false),
            ("^(?:does|do|did) (.+?) (?:have|use|observe|do|has|change for) \(dst)$", false),
            ("^is there \(dst) in (.+)$", false),
            ("^(?:is|are) (.+?) (?:on|in|using) \(dst)(?: now| right now| yet)?$", true),
            ("^(?:when is |next )?\(dst)(?: in| for)? (.+)$", false),
            ("^(.+?) \(dst)$", false),
        ]
        for (pattern, yesNo) in asking {
            guard let r = try? Regex(pattern), let m = q.firstMatch(of: r), let phrase = m.output[1].substring,
                  let z = JumpParser.zone(in: " \(phrase) ", people: people, extra: extra)?.zone else { continue }
            // Named by their city ("london" for Partners), the answer says the city.
            let byCity = z.person.map { phrase.contains($0.city.lowercased()) } ?? false
            let base = byCity ? z.person!.city : z.name
            let name = z.person?.isHome == true && !byCity ? "Your clock" : base
            let off = Clocks.offset(z.tz, now)
            let next = Clocks.changes(z.tz, from: now, to: now + 400 * 1440).first
            guard let next else {
                let last = Clocks.last(z.tz, before: now)
                return Hit(id: "dst-\(z.name)", icon: "clock.badge.checkmark",
                           title: yesNo ? "No: \(name) doesn't change its clocks" : "\(name) doesn't change its clocks",
                           detail: "Always \(Clocks.utc(off))" + (last.map { " since \(Date(timeIntervalSince1970: $0.at * 60).formatted(.dateTime.year()))" } ?? ""),
                           action: nil, color: [133, 183, 235], person: z.person,
                           clocks: [HitClock(place: name, time: Clocks.utc(off), day: "all year")], at: now)
            }
            let season = Clocks.season(z.tz, now)
            let after = Clocks.offset(z.tz, next.at + 1)
            let when = Clocks.day(next.at, z.tz, now: now)
            let local = Local(z.tz, next.at - 1)
            let title = yesNo
                ? (season != nil ? "Yes: \(name) is on \(season!) (\(Clocks.utc(off)))" : "No: \(name) is on standard time (\(Clocks.utc(off)))")
                : "\(Clocks.owner(name)) clocks \(Clocks.move(next.shift)) \(when)"
            // Someone else's change: what it does to the gap between you, rather than to UTC.
            var clocks = [HitClock(place: "Now", time: Clocks.utc(off), day: season ?? "standard"),
                          HitClock(place: "From \(when)", time: Clocks.utc(after), day: Clocks.season(z.tz, next.at + 1) ?? "standard")]
            var detail = "At \(hm(local)) their time, \(Clocks.utc(off)) becomes \(Clocks.utc(after))"
            if let home = people.first(where: \.isHome), z.person?.isHome != true {
                let now = Clocks.gap(home.tz, z.tz, next.at - 1), then = Clocks.gap(home.tz, z.tz, next.at + 1)
                let side = { (g: Int) in g == 0 ? "with you" : g > 0 ? "ahead of you" : "behind you" }
                clocks = [HitClock(place: "Now", time: dur(Double(abs(now))), day: side(now)),
                          HitClock(place: "From \(when)", time: dur(Double(abs(then))), day: side(then))]
                detail = "At \(hm(local)) their time: \(Clocks.apart(now)) now, \(Clocks.apart(then)) after"
            }
            return Hit(id: "dst-\(z.name)", icon: "clock.arrow.2.circlepath", title: title,
                       detail: detail,
                       action: .jump(next.at, pick: z.person.map { $0.isHome ? [] : [$0.id] } ?? []), color: [255, 214, 74], person: z.person,
                       clocks: clocks,
                       at: next.at,
                       headline: yesNo ? title : "\(Clocks.owner(name)) clocks \(Clocks.move(next.shift)) \(when)",
                       gap: Clocks.signed(next.shift))
        }
        return nil
    }

    private static func time(_ m: Double, _ tz: TimeZone) -> String { let l = Local(tz, m); return "\(hm(l))" }

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
    case .fair(let slot, let pick):
        // Choosing a slot is what counts towards rotation, so whoever stretched now is spared next time.
        Fair.record(slot)
        people.picked = pick
        model.springTo(slot.start, response: 0.6)
    }
}

/// Places from Apple Maps for words the offline table doesn't know ("Visakhapatnam 3pm", "Bend Oregon").
@MainActor @Observable final class PlaceLookup {
    private(set) var zones: [Zone] = []
    private var asked: Set<String> = []

    func look(for query: String, people: [Person]) async {
        // Airport codes whose zone isn't certain offline ("KZN", "GIG"): from the airport's city on Apple Maps.
        for w in query.split(whereSeparator: { !$0.isLetter }) where w.count == 3 {
            let code = w.uppercased()
            guard let a = Airports.byCode[code], a.tz == nil, !asked.contains(code),
                  !Airports.words.contains(code.lowercased()) || w == w.uppercased() else { continue }
            asked.insert(code)
            let country = Locale(identifier: "en").localizedString(forRegionCode: a.country) ?? a.country
            if let tz = await findPlace("\(a.city), \(country)")?.timeZone { zones.append(Zone(name: a.label, tz: tz, key: code.lowercased())) }
        }
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

