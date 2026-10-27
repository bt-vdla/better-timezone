import Foundation
import Synchronization

/// Airport codes for places, from the bundled OurAirports list (public domain).
enum Airports {
    struct Airport: Sendable {
        let code: String, lat: Double, lon: Double, large: Bool
        let country: String, city: String
        /// Nil where it isn't certain offline (parts of Russia, Brazil, Mexico): looked up on Apple Maps when asked.
        let tz: TimeZone?

        /// "Sydney (SYD)": the city first, so a code always says where it is.
        var label: String {
            let place = city.components(separatedBy: " (").first?.split(separator: " ").joined(separator: " ") ?? city
            return place.isEmpty ? code : "\(place) (\(code))"
        }
    }

    private static let all: [Airport] = {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 7, let lat = Double(f[1]), let lon = Double(f[2]) else { return nil }
            return Airport(code: String(f[0]), lat: lat, lon: lon, large: f[3] == "0",
                           country: String(f[4]), city: String(f[5]), tz: TimeZone(identifier: String(f[6])))
        }
    }()

    /// Every airport by its code ("SFO").
    static let byCode: [String: Airport] = Dictionary(all.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })

    /// Codes that are everyday words or time words in lowercase ("the" is Teresina, "fri" is a day): typed in
    /// capitals they still count.
    static let words: Set<String> = Set("""
        the and for are you can now any all how who why was has had her him his its not but our out see she too two way may day \
        get got let put say set use try ask big end far few new old own top yes off ago per via one six ten man men mom dad son \
        sis bro mum fam job act add age art bad bar bed bit box boy bus buy car cat cup cut die dog dry due eat egg eye fan fat \
        fit fly fun gas god gun guy hat hit hot ice ill key kid law lay leg lie lot low map mix net nor odd oil pay pen pet pop \
        raw red run sad sea sit sky sun tax tea tie tip toy war wet win yet zip lol omg btw pls plz thx hey hmm wow yay ama \
        mon tue wed thu fri sat jan feb mar apr jun jul aug sep oct nov dec min hrs sec eve tmr tom est edt cst cdt mst mdt pst \
        pdt ist gmt utc bst cet jst gst sgt hkt aest am pm time talk call free
        """.split(whereSeparator: \.isWhitespace).map(String.init))

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
