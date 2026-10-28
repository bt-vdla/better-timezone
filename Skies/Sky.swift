import Foundation

/// Wall-clock reading of an absolute moment (minutes since 1970) in one zone.
struct Local {
    let h: Int, m: Int
    let off: Int      // minutes from UTC
    let dn: Int       // local day number
    let wd: Int       // 0 = Sunday
    let f: Double     // fractional hour of day

    init(_ tz: TimeZone, _ minutes: Double) {
        off = tz.secondsFromGMT(for: Date(timeIntervalSince1970: minutes * 60)) / 60
        let lm = minutes + Double(off)
        dn = Int((lm / 1440).rounded(.down))
        let dayMin = lm - Double(dn) * 1440
        f = dayMin / 60
        h = Int(f)
        m = Int(dayMin) % 60
        wd = ((dn + 4) % 7 + 7) % 7
    }

    /// The moment back again, in minutes since 1970.
    var at: Double { Double(dn) * 1440 + f * 60 - Double(off) }
}

/// 12- or 24-hour clocks: the system's choice unless Settings overrides it ("system", "12", "24" in `timeFormat`).
enum TimeFormat {
    static let key = "timeFormat"
    nonisolated(unsafe) static var twentyFour = read()

    static func read() -> Bool {
        switch UserDefaults.skies.string(forKey: key) {
        case "12": false
        case "24": true
        default: Locale.current.hourCycle == .zeroToTwentyThree || Locale.current.hourCycle == .oneToTwentyFour
        }
    }
}

/// The hour as shown on a clock face: 3 (or 15 on a 24-hour clock).
func h12(_ h: Int) -> Int { TimeFormat.twentyFour ? h : (h + 11) % 12 + 1 }
/// "AM"/"PM", or nothing on a 24-hour clock.
func ampm(_ h: Int) -> String { TimeFormat.twentyFour ? "" : h < 12 ? "AM" : "PM" }
/// "3:05", or "15:05".
func clock(_ l: Local, twentyFour: Bool = TimeFormat.twentyFour) -> String {
    twentyFour ? String(format: "%02d:%02d", l.h, l.m) : "\((l.h + 11) % 12 + 1):" + String(format: "%02d", l.m)
}
/// "3:05 PM", or "15:05": the whole time, for sentences.
func hm(_ l: Local, twentyFour: Bool = TimeFormat.twentyFour) -> String {
    twentyFour ? clock(l, twentyFour: true) : "\(clock(l, twentyFour: false)) \(l.h < 12 ? "AM" : "PM")"
}
/// "3 PM", or "15:00": an hour on its own.
func hourText(_ h: Int, twentyFour: Bool = TimeFormat.twentyFour) -> String {
    twentyFour ? String(format: "%02d:00", h) : "\((h + 11) % 12 + 1) \(h < 12 ? "AM" : "PM")"
}

func dur(_ minutes: Double) -> String {
    let mins = Int(abs(minutes).rounded())
    let d = mins / 1440, h = mins % 1440 / 60, m = mins % 60
    if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    return h > 0 ? "\(h)h" : "\(m)m"
}

/// Merged 15-minute runs from `start` where every person in `team` is free.
/// Your calendar's busy times (minutes since 1970), when you've let Skies read it. Empty in widgets.
enum BusyTimes {
    nonisolated(unsafe) static var current: [ClosedRange<Double>] = []
    /// Meetings on the calendar each person shares with you, by person id. Empty in widgets.
    nonisolated(unsafe) static var theirs: [UUID: [ClosedRange<Double>]] = [:]

    /// True if the quarter hour starting at `a` overlaps a meeting.
    static func covers(_ a: Double, _ busy: [ClosedRange<Double>] = current) -> Bool {
        busy.contains { $0.lowerBound < a + 15 && $0.upperBound > a }
    }
}

func freeRuns(_ team: [Person], from start: Double, slots: Int, mode: Person.Kind? = nil,
              busy: [ClosedRange<Double>] = BusyTimes.current) -> [ClosedRange<Double>] {
    var runs: [ClosedRange<Double>] = []
    var cur: (Double, Double)?
    let checksYou = team.contains(where: \.isHome) && !busy.isEmpty
    for k in 0..<slots {
        let a = start + Double(k) * 15
        if team.allSatisfy({ $0.free(Local($0.tz, a), with: mode) }) && !(checksYou && BusyTimes.covers(a, busy)) {
            cur = (cur?.0 ?? a, a + 15)
        } else if let c = cur {
            runs.append(c.0...c.1)
            cur = nil
        }
    }
    if let c = cur { runs.append(c.0...c.1) }
    return runs
}

/// Start of the local day containing `minutes`.
func dayStart(_ tz: TimeZone, _ minutes: Double) -> Double { minutes - Local(tz, minutes).f * 60 }

/// Clock changes (minutes since 1970, shift in minutes) for each person within the range.
func clockChanges(_ people: [Person], in range: ClosedRange<Double>) -> [(at: Double, shift: Int, person: Person)] {
    people.compactMap { p in
        guard let t = p.tz.nextDaylightSavingTimeTransition(after: Date(timeIntervalSince1970: range.lowerBound * 60)),
              t.timeIntervalSince1970 / 60 <= range.upperBound else { return nil }
        let shift = (p.tz.secondsFromGMT(for: t + 60) - p.tz.secondsFromGMT(for: t - 60)) / 60
        return (t.timeIntervalSince1970 / 60, shift, p)
    }
    .sorted { $0.at < $1.at }
}

// MARK: - Sun

struct Sun { let rise: Double, noon: Double, set: Double }   // local hours, may sit outside 0..<24

let gmtCalendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }()

/// Year, month and day of a local day number.
func gmtDay(_ dn: Int) -> DateComponents {
    gmtCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(dn) * 86400))
}

/// NOAA-style approximation, good to a few minutes away from the poles.
func sun(_ p: Person, _ l: Local) -> Sun {
    let n = Double(gmtCalendar.ordinality(of: .day, in: .year, for: Date(timeIntervalSince1970: Double(l.dn) * 86400)) ?? 1)
    let decl = solarDeclination(j2000(Double(l.dn) * 1440 + 720 - Double(l.off)))
    let b = 2 * .pi * (n - 81) / 364
    let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
    let noon = 12 - p.lon / 15 - eot / 60 + Double(l.off) / 60
    let cosH = (sin(-0.833 * rad) - sin(p.lat * rad) * sin(decl)) / (cos(p.lat * rad) * cos(decl))
    // ponytail: polar day/night clamped to a 1.5h–22.5h day so there is always a dawn and dusk.
    let half = min(11.25, max(0.75, acos(min(1, max(-1, cosH))) / rad / 15))
    return Sun(rise: noon - half, noon: noon, set: noon + half)
}

/// Where the sun is on its day or night arc (0...1), from local time and that day's sunrise and sunset.
func solar(_ f: Double, _ s: Sun) -> (day: Bool, arc: Double) {
    var d = (f - s.noon).truncatingRemainder(dividingBy: 24)
    if d < -12 { d += 24 } else if d >= 12 { d -= 24 }
    let r = s.rise - s.noon, st = s.set - s.noon
    if d >= r && d < st { return (true, (d - r) / (st - r)) }
    return (false, ((d - st) + 24).truncatingRemainder(dividingBy: 24) / (24 - (st - r)))
}

// MARK: - Sun and moon in the sky

private let rad = Double.pi / 180

/// Days since J2000.0 (2000-01-01 12:00 UTC).
private func j2000(_ minutes: Double) -> Double { minutes / 1440 - 10957.5 }

/// Elevation (degrees) and hour angle (degrees, -180...180) of a body at right ascension/declination (radians).
private func horizontal(ra: Double, dec: Double, d: Double, lat: Double, lon: Double) -> (elev: Double, hourAngle: Double) {
    var h = (280.46061837 + 360.98564736629 * d + lon - ra / rad).truncatingRemainder(dividingBy: 360)
    if h > 180 { h -= 360 } else if h < -180 { h += 360 }
    let phi = lat * rad
    return (asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h * rad)) / rad, h)
}

/// Sun's right ascension and declination (radians), low-precision Astronomical Almanac: about 0.01°.
private func solarEquatorial(_ d: Double) -> (ra: Double, dec: Double) {
    let g = (357.529 + 0.98560028 * d) * rad
    let l = (280.459 + 0.98564736 * d + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
    let e = (23.439 - 0.00000036 * d) * rad
    return (atan2(cos(e) * sin(l), cos(l)), asin(sin(e) * sin(l)))
}

private func solarDeclination(_ d: Double) -> Double { solarEquatorial(d).dec }

func sunPosition(_ p: Person, _ minutes: Double) -> (elev: Double, hourAngle: Double) {
    let d = j2000(minutes), s = solarEquatorial(d)
    return horizontal(ra: s.ra, dec: s.dec, d: d, lat: p.lat, lon: p.lon)
}

/// Low-precision lunar position, good to about a degree: plenty for a sky.
func moonPosition(_ p: Person, _ minutes: Double) -> (elev: Double, hourAngle: Double) {
    let d = j2000(minutes)
    let L = (218.316 + 13.176396 * d) * rad, M = (134.963 + 13.064993 * d) * rad, F = (93.272 + 13.229350 * d) * rad
    let l = L + 6.289 * rad * sin(M), b = 5.128 * rad * sin(F), e = 23.4397 * rad
    let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
    let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
    return horizontal(ra: ra, dec: dec, d: d, lat: p.lat, lon: p.lon)
}

/// 0 = new, 0.5 = full, from the mean synodic month since the new moon of 2000-01-06 18:14 UTC.
func moonPhase(_ minutes: Double) -> Double {
    let synodic = 29.530588853 * 1440
    let age = (minutes - 15_786_374).truncatingRemainder(dividingBy: synodic)
    return (age < 0 ? age + synodic : age) / synodic
}

struct SkyState {
    let sunElev: Double, sunX: Double
    let moonElev: Double, moonX: Double, phase: Double
    let zenith: RGB, horizon: RGB
}

/// Everything the sky shader needs for one person at one moment. X runs 0 (rising side) to 1 (setting side).
func skyState(_ p: Person, _ minutes: Double) -> SkyState {
    let l = Local(p.tz, minutes)
    let s = sunPosition(p, minutes), mo = moonPosition(p, minutes)
    let arc = solar(l.f, sun(p, l))
    // Below the horizon the sun keeps sliding off the side it set on, and comes back in on the side it rises.
    let x = arc.day ? arc.arc : arc.arc < 0.5 ? 1 + arc.arc * 0.8 : -0.8 * (1 - arc.arc)
    let (z, h) = skyColors(s.elev)
    return SkyState(sunElev: s.elev, sunX: x, moonElev: mo.elev, moonX: (mo.hourAngle + 90) / 180,
                    phase: moonPhase(minutes), zenith: z, horizon: h)
}

typealias RGB = SIMD3<Double>

private func hex(_ s: String) -> RGB {
    let v = Int(s.dropFirst(), radix: 16)!
    return RGB(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255))
}

/// Zenith and horizon colours by sun elevation, with stops at the astronomical, nautical and civil twilight lines.
private let elevationStops: [(Double, RGB, RGB)] = ([
    (-90, "#02040C", "#060A1C"), (-18, "#04061A", "#0A1030"), (-12, "#070C28", "#18224E"),
    (-6, "#141D55", "#43376F"), (-3, "#283776", "#B5677F"), (0, "#3A5BA6", "#F0936A"),
    (4, "#4677C2", "#F8B47E"), (10, "#3A7FD4", "#9CCBF2"), (30, "#2E74D0", "#8CC2EE"),
    (90, "#2468C8", "#86BDEB"),
] as [(Double, String, String)]).map { ($0.0, hex($0.1), hex($0.2)) }

func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { a + (b - a) * t }

/// A richer version of a sky colour for small skies on black (the notch): more saturated, deep night lifted so it
/// reads as indigo rather than black, and the palest day blues held back so white text stays legible on them.
func vivid(_ c: RGB, _ amount: Double) -> RGB {
    guard amount > 0 else { return c }
    let r = c.x / 255, g = c.y / 255, b = c.z / 255
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    var h = 0.0
    if d > 0 {
        h = mx == r ? (g - b) / d : mx == g ? 2 + (b - r) / d : 4 + (r - g) / d
        h = (h / 6).truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
    }
    var s = mx == 0 ? 0 : d / mx, v = mx
    // Scaled by `amount` (0.35 is the notch's): +18% saturation, never past 0.88 so blues don't turn neon.
    let k = amount / 0.35
    s = max(s, min(0.88, s * (1 + 0.18 * k)))
    if v < 0.3 { v += (0.3 - v) * 0.3 * k }
    if v > 0.82 { v -= (v - 0.82) * 0.5 * k }
    // Back to RGB.
    let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    let (rr, gg, bb): (Double, Double, Double) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    return RGB(rr * 255, gg * 255, bb * 255)
}
func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

func skyColors(_ elev: Double) -> (zenith: RGB, horizon: RGB) {
    let i = elevationStops.lastIndex { $0.0 <= elev } ?? 0
    let (ta, a1, a2) = elevationStops[i], (tb, b1, b2) = elevationStops[min(i + 1, elevationStops.count - 1)]
    let e = tb > ta ? smooth((elev - ta) / (tb - ta)) : 0
    return (mix(a1, b1, e), mix(a2, b2, e))
}

private let green = hex("#34D399"), amber = hex("#FFC46B"), orange = hex("#FFB347"),
            blue = hex("#60B6FF"), purple = hex("#C9A7FF"), grey = hex("#9AA3C7")

/// What they're probably doing, in the words that matter for how you know them.
func status(_ p: Person, _ l: Local) -> (String, RGB) {
    // Their own calendar beats any guess from the clock.
    if BusyTimes.theirs[p.id]?.contains(where: { $0.contains(l.at) }) == true { return ("In a meeting", amber) }
    let f = l.f, weekday = (p.relation == .work ? p.workdays : p.weekdays).contains(l.wd)
    switch p.relation {
    case .work:
        let workday = p.days.contains(l.wd)
        if workday && p.inHours(f) {
            if f - p.start < 0.75 && f >= p.start { return ("Coffee first", amber) }
            if (12.5..<13.5).contains(f) { return ("Lunch", orange) }
            return f >= 18 ? ("Off work", blue) : ("Working", green)
        }
        // ponytail: assumes people sleep roughly 11 PM–6 AM outside their set hours.
        if f >= 23 || f < 6 { return ("Asleep", grey) }
        if !workday { return (weekday ? "Day off" : "Weekend", blue) }
        if f < p.start { return ("Getting ready", amber) }
        return f < 22 ? ("Off work", blue) : ("Winding down", purple)

    case .personal:
        guard p.days.contains(l.wd) && p.inHours(f) else {
            let toStart = (p.start - f + 24).truncatingRemainder(dividingBy: 24)
            let sinceEnd = (f - p.end + 24).truncatingRemainder(dividingBy: 24)
            if toStart <= 1.5 { return ("Waking up", amber) }
            if sinceEnd < 1 { return ("Winding down", purple) }
            return ("Asleep", grey)
        }
        if p.busyDay(l) { return ("Probably busy", amber) }
        if weekday && f < 9 { return ("Morning rush", amber) }
        if weekday && (12.5..<13.5).contains(f) { return ("Lunch break", orange) }
        if (19..<20.5).contains(f) { return ("Dinner time", orange) }
        return ("Good time to call", green)
    }
}

// MARK: - Next shared window

/// The next stretch (minutes since 1970) when everyone in `team` is free, starting from `after` (or now, if inside one).
func nextWindow(_ team: [Person], mode: Person.Kind?, after m: Double) -> (start: Double, end: Double)? {
    guard let home = team.first(where: \.isHome) ?? team.first else { return nil }
    let runs = freeRuns(team, from: dayStart(home.tz, m), slots: 96 * 8, mode: mode)
    return runs.first { $0.upperBound > m }.map { ($0.lowerBound, $0.upperBound) }
}

func startText(_ m: Double, people: [Person]) -> String {
    guard let home = people.first(where: \.isHome) ?? people.first else { return "" }
    let l = Local(home.tz, m)
    let days = l.dn - Local(home.tz, nowMinutes()).dn
    let day = days == 0 ? "" : days == 1 ? "tomorrow " : Calendar.current.shortWeekdaySymbols[l.wd] + " "
    return "\(day)\(hm(l))"
}
