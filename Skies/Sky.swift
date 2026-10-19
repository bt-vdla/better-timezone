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
    let rad = Double.pi / 180
    let decl = -23.44 * cos(2 * .pi / 365 * (n + 10)) * rad
    let b = 2 * .pi * (n - 81) / 364
    let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
    let noon = 12 - p.lon / 15 - eot / 60 + Double(l.off) / 60
    let cosH = (sin(-0.833 * rad) - sin(p.lat * rad) * sin(decl)) / (cos(p.lat * rad) * cos(decl))
    // ponytail: polar day/night clamped to a 1.5h–22.5h day so there is always a dawn and dusk.
    let half = min(11.25, max(0.75, acos(min(1, max(-1, cosH))) / rad / 15))
    return Sun(rise: noon - half, noon: noon, set: noon + half)
}

/// Maps local time onto the sky palette's reference day (sunrise 6:15, noon 12, sunset 18:36),
/// plus where the sun or moon sits on its arc (0...1).
func solar(_ f: Double, _ s: Sun) -> (skyHour: Double, day: Bool, arc: Double) {
    var d = (f - s.noon).truncatingRemainder(dividingBy: 24)
    if d < -12 { d += 24 } else if d >= 12 { d -= 24 }
    let r = s.rise - s.noon, st = s.set - s.noon
    func lerp(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Double { y0 + (d - x0) / (x1 - x0) * (y1 - y0) }
    let hour = d < r ? lerp(-12, r, 0, 6.25) : d < 0 ? lerp(r, 0, 6.25, 12) : d < st ? lerp(0, st, 12, 18.6) : lerp(st, 12, 18.6, 24)
    if d >= r && d < st { return (hour, true, (d - r) / (st - r)) }
    let night = 24 - (st - r)
    return (hour, false, ((d - st) + 24).truncatingRemainder(dividingBy: 24) / night)
}

// MARK: - Sky

typealias RGB = SIMD3<Double>

private func hex(_ s: String) -> RGB {
    let v = Int(s.dropFirst(), radix: 16)!
    return RGB(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255))
}

private let skyStops: [(Double, RGB, RGB)] = ([
    (0, "#0B1030", "#1B2350"), (4.5, "#121844", "#2A2660"), (5.75, "#3A2C6E", "#E0708A"),
    (6.75, "#FF9E7A", "#FFD69C"), (8.5, "#8FD3FF", "#D9F2FF"), (12, "#55B4FF", "#BFE7FF"),
    (16, "#79C2F4", "#FFE3B3"), (18, "#FF8657", "#FFC57A"), (19.25, "#7A3E9D", "#E7708C"),
    (20.5, "#2B2466", "#4B3A86"), (22, "#12163C", "#222A5C"), (24, "#0B1030", "#1B2350"),
] as [(Double, String, String)]).map { ($0.0, hex($0.1), hex($0.2)) }

func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { a + (b - a) * t }
func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

func sky(_ f: Double) -> (RGB, RGB) {
    let i = skyStops.lastIndex { $0.0 <= f }!
    let (ta, a1, a2) = skyStops[i], (tb, b1, b2) = skyStops[min(i + 1, skyStops.count - 1)]
    let e = tb > ta ? smooth((f - ta) / (tb - ta)) : 0
    return (mix(a1, b1, e), mix(a2, b2, e))
}

func luminance(_ c: RGB) -> Double {
    let l = [c.x, c.y, c.z].map { v -> Double in
        let s = v / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
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
