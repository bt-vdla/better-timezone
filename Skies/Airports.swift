import Foundation
import Synchronization

/// Airport codes for places, from the bundled OurAirports list (public domain).
enum Airports {
    private struct Airport { let code: String; let lat: Double; let lon: Double; let large: Bool }

    private static let all: [Airport] = {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: ",")
            guard f.count == 4, let lat = Double(f[1]), let lon = Double(f[2]) else { return nil }
            return Airport(code: String(f[0]), lat: lat, lon: lon, large: f[3] == "0")
        }
    }()

    private static let cache = Mutex<[String: String?]>([:])

    /// The code people would recognise: the nearest large airport within 100 km, else the nearest medium one.
    /// London is LHR, not the slightly closer London City.
    static func nearest(lat: Double, lon: Double) -> String? {
        let key = "\(Int(lat * 100)),\(Int(lon * 100))"
        if let hit = cache.withLock({ $0[key] }) { return hit }
        // ponytail: linear scan over ~3,200 airports, cached per place; a grid index if lists ever get huge.
        let near = all.map { (a: $0, km: km(lat, lon, $0.lat, $0.lon)) }.filter { $0.km <= 100 }
        let pick = (near.filter(\.a.large).min { $0.km < $1.km } ?? near.min { $0.km < $1.km })?.a.code
        cache.withLock { $0[key] = pick }
        return pick
    }

    private static func km(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
        let r = Double.pi / 180
        let a = sin((la2 - la1) * r / 2), b = sin((lo2 - lo1) * r / 2)
        return 2 * 6371 * asin(min(1, sqrt(a * a + cos(la1 * r) * cos(la2 * r) * b * b)))
    }
}

/// What a person is called on screen: their name (default), their place's code, or the city.
enum ShowBy: String, CaseIterable, Identifiable {
    case name, code, city
    var id: Self { self }
    var title: String {
        switch self {
        case .name: "Name"
        case .code: "Airport code"
        case .city: "City"
        }
    }
    static let key = "showBy"
}

extension Person {
    /// Who they are: you, the linked contact's first name, the name you gave them, or (last resort) the city.
    var name: String { isHome ? "You" : contact?.firstName ?? label.nonEmpty ?? city }

    /// Three letters for where they are: your own shortening if you set one, else the nearest airport,
    /// else the city's first three letters.
    var code: String {
        codeOverride?.nonEmpty ?? Airports.nearest(lat: lat, lon: lon) ?? String(city.filter(\.isLetter).prefix(3)).uppercased()
    }

    /// The big label and the small one beside it, for the chosen style.
    func title(_ by: ShowBy) -> String {
        switch by {
        case .name: name
        case .code: code
        case .city: city
        }
    }

    func tag(_ by: ShowBy) -> String { by == .code ? name : code }
}
