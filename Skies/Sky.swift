import Foundation

struct Zone: Identifiable, Sendable {
    let city: String
    let tag: String
    let tz: TimeZone
    var home = false
    var id: String { city }
}

let zones: [Zone] = [
    Zone(city: "Hyderabad", tag: "You", tz: TimeZone(identifier: "Asia/Kolkata")!, home: true),
    Zone(city: "Georgetown", tag: "Site team", tz: TimeZone(identifier: "America/Guyana")!),
    Zone(city: "London", tag: "Partners", tz: TimeZone(identifier: "Europe/London")!),
    Zone(city: "Dubai", tag: "Investor", tz: TimeZone(identifier: "Asia/Dubai")!),
    Zone(city: "San Francisco", tag: "Design review", tz: TimeZone(identifier: "America/Los_Angeles")!),
]
let home = zones[0]

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

func awake(_ f: Double) -> Bool { f >= 8 && f < 22 }
func allAwake(_ minutes: Double) -> Bool { zones.allSatisfy { awake(Local($0.tz, minutes).f) } }

/// Runs of 15-minute slots on the home day (containing `minutes`) where every zone is awake.
func overlapRuns(_ minutes: Double) -> [ClosedRange<Double>] {
    let start = minutes - Local(home.tz, minutes).f * 60
    var runs: [ClosedRange<Double>] = []
    var cur: (Double, Double)?
    for k in 0..<96 {
        let a = start + Double(k) * 15
        if allAwake(a) {
            cur = (cur?.0 ?? a, a + 15)
        } else if let c = cur {
            runs.append(c.0...c.1)
            cur = nil
        }
    }
    if let c = cur { runs.append(c.0...c.1) }
    return runs
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

func status(_ f: Double) -> (String, RGB) {
    switch f {
    case ..<6: ("Asleep", hex("#9AA3C7"))
    case ..<8: ("Waking up", hex("#FFC46B"))
    case ..<9: ("Coffee first", hex("#FFC46B"))
    case ..<12.5: ("Working", hex("#34D399"))
    case ..<13.5: ("Lunch", hex("#FFB347"))
    case ..<18: ("Working", hex("#34D399"))
    case ..<21: ("Off work", hex("#60B6FF"))
    case ..<23: ("Winding down", hex("#C9A7FF"))
    default: ("Asleep", hex("#9AA3C7"))
    }
}
