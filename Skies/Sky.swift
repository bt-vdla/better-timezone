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
}

func h12(_ h: Int) -> Int { (h + 11) % 12 + 1 }
func ampm(_ h: Int) -> String { h < 12 ? "AM" : "PM" }
func clock(_ l: Local) -> String { "\(h12(l.h)):" + String(format: "%02d", l.m) }

func dur(_ minutes: Double) -> String {
    let mins = Int(abs(minutes).rounded())
    let d = mins / 1440, h = mins % 1440 / 60, m = mins % 60
    if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    return h > 0 ? "\(h)h" : "\(m)m"
}

/// Merged 15-minute runs from `start` where every person in `team` is free.
func freeRuns(_ team: [Person], from start: Double, slots: Int) -> [ClosedRange<Double>] {
    var runs: [ClosedRange<Double>] = []
    var cur: (Double, Double)?
    for k in 0..<slots {
        let a = start + Double(k) * 15
        if team.allSatisfy({ $0.free(Local($0.tz, a)) }) {
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

private let gmtCalendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }()

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
func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

func skyColors(_ elev: Double) -> (zenith: RGB, horizon: RGB) {
    let i = elevationStops.lastIndex { $0.0 <= elev } ?? 0
    let (ta, a1, a2) = elevationStops[i], (tb, b1, b2) = elevationStops[min(i + 1, elevationStops.count - 1)]
    let e = tb > ta ? smooth((elev - ta) / (tb - ta)) : 0
    return (mix(a1, b1, e), mix(a2, b2, e))
}

func status(_ p: Person, _ l: Local) -> (String, RGB) {
    let f = l.f
    if p.inHours(f) {
        guard p.days.contains(l.wd) else { return ("Day off", hex("#60B6FF")) }
        switch f {
        case ..<9: return ("Coffee first", hex("#FFC46B"))
        case 12.5..<13.5: return ("Lunch", hex("#FFB347"))
        case 18...: return ("Off work", hex("#60B6FF"))
        default: return ("Working", hex("#34D399"))
        }
    }
    let toStart = (p.start - f + 24).truncatingRemainder(dividingBy: 24)
    let sinceEnd = (f - p.end + 24).truncatingRemainder(dividingBy: 24)
    if toStart <= 1.5 { return ("Waking up", hex("#FFC46B")) }
    if sinceEnd < 1.5 { return ("Winding down", hex("#C9A7FF")) }
    return ("Asleep", hex("#9AA3C7"))
}
