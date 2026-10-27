import Testing
import Foundation
@testable import Skies

/// Every common time-zone abbreviation means the zone people mean by it. Left out on purpose: "at" and "nt" (words),
/// "nut" (a word), and FNT, MHT, TVT, which are busier as airport codes than as time zones.
@Test func abbreviations() {
    let expected: [(String, String)] = [
        ("est","America/New_York"),("edt","America/New_York"),("et","America/New_York"),("cst","America/Chicago"),("cdt","America/Chicago"),
        ("ct","America/Chicago"),("mst","America/Denver"),("mdt","America/Denver"),("mt","America/Denver"),("pst","America/Los_Angeles"),
        ("pdt","America/Los_Angeles"),("pt","America/Los_Angeles"),("akst","America/Anchorage"),("akdt","America/Anchorage"),("akt","America/Anchorage"),
        ("hst","Pacific/Honolulu"),("hast","Pacific/Honolulu"),("ast","America/Halifax"),("adt","America/Halifax"),
        ("nst","America/St_Johns"),("ndt","America/St_Johns"),
        ("art","America/Argentina/Buenos_Aires"),("brt","America/Sao_Paulo"),("brst","America/Sao_Paulo"),("clt","America/Santiago"),
        ("clst","America/Santiago"),("cot","America/Bogota"),("pet","America/Lima"),("vet","America/Caracas"),("bot","America/La_Paz"),
        ("ect","America/Guayaquil"),("uyt","America/Montevideo"),("pyt","America/Asuncion"),("srt","America/Paramaribo"),("gft","America/Cayenne"),
        ("gyt","America/Guyana"),
        ("utc","UTC"),("bst","Europe/London"),("wet","Europe/Lisbon"),("west","Europe/Lisbon"),("cet","Europe/Paris"),
        ("cest","Europe/Paris"),("eet","Europe/Athens"),("eest","Europe/Athens"),("msk","Europe/Moscow"),("trt","Europe/Istanbul"),("samt","Europe/Samara"),
        ("wat","Africa/Lagos"),("cat","Africa/Harare"),("eat","Africa/Nairobi"),("sast","Africa/Johannesburg"),
        ("gst","Asia/Dubai"),("irst","Asia/Tehran"),("aft","Asia/Kabul"),("azt","Asia/Baku"),("pkt","Asia/Karachi"),("ist","Asia/Kolkata"),
        ("npt","Asia/Kathmandu"),("bdt","Asia/Dhaka"),("btt","Asia/Thimphu"),("mmt","Asia/Yangon"),("ict","Asia/Bangkok"),("wib","Asia/Jakarta"),
        ("wita","Asia/Makassar"),("wit","Asia/Jayapura"),("myt","Asia/Kuala_Lumpur"),("sgt","Asia/Singapore"),("pht","Asia/Manila"),
        ("hkt","Asia/Hong_Kong"),("bjt","Asia/Shanghai"),("kst","Asia/Seoul"),("jst","Asia/Tokyo"),("ulat","Asia/Ulaanbaatar"),("tlt","Asia/Dili"),
        ("bnt","Asia/Brunei"),("yekt","Asia/Yekaterinburg"),("omst","Asia/Omsk"),("novt","Asia/Novosibirsk"),("krat","Asia/Krasnoyarsk"),
        ("irkt","Asia/Irkutsk"),("yakt","Asia/Yakutsk"),("vlat","Asia/Vladivostok"),("magt","Asia/Magadan"),("pett","Asia/Kamchatka"),
        ("almt","Asia/Almaty"),("uzt","Asia/Tashkent"),("tjt","Asia/Dushanbe"),("tmt","Asia/Ashgabat"),("kgt","Asia/Bishkek"),
        ("awst","Australia/Perth"),("acst","Australia/Adelaide"),("acdt","Australia/Adelaide"),("aest","Australia/Sydney"),("aedt","Australia/Sydney"),
        ("lhst","Australia/Lord_Howe"),("nzst","Pacific/Auckland"),("nzdt","Pacific/Auckland"),("nzt","Pacific/Auckland"),("chast","Pacific/Chatham"),
        ("fjt","Pacific/Fiji"),("tot","Pacific/Tongatapu"),("sst","Pacific/Pago_Pago"),("chst","Pacific/Guam"),("taht","Pacific/Tahiti"),
        ("mart","Pacific/Marquesas"),("gamt","Pacific/Gambier"),("nct","Pacific/Noumea"),("vut","Pacific/Efate"),("sbt","Pacific/Guadalcanal"),
        ("pgt","Pacific/Port_Moresby"),("gilt","Pacific/Tarawa"),("pwt","Pacific/Palau"),
        ("ckt","Pacific/Rarotonga"),("tkt","Pacific/Fakaofo"),("wsst","Pacific/Apia"),("nft","Pacific/Norfolk"),
        ("cxt","Indian/Christmas"),("cct","Indian/Cocos"),("mvt","Indian/Maldives"),("mut","Indian/Mauritius"),("sct","Indian/Mahe"),
        ("ret","Indian/Reunion"),("gmt","GMT"),("iot","Indian/Chagos"),("azot","Atlantic/Azores"),("cvt","Atlantic/Cape_Verde"),("fkst","Atlantic/Stanley"),
        ("idt","Asia/Jerusalem"),
    ]
    func same(_ a: TimeZone, _ b: TimeZone) -> Bool {
        [Date(timeIntervalSince1970: 1_768_478_400), Date(timeIntervalSince1970: 1_784_116_800)].allSatisfy { a.secondsFromGMT(for: $0) == b.secondsFromGMT(for: $0) }
    }
    var missing: [String] = [], wrong: [String] = []
    for (abbr, id) in expected {
        guard let want = TimeZone(identifier: id) else { continue }
        if let z = Places.zone(named: abbr) {
            if !same(z.tz, want) { wrong.append("\(abbr)=\(z.tz.identifier)≠\(id)") }
        } else { missing.append(abbr) }
    }
    #expect(missing.isEmpty, "Unknown: \(missing.joined(separator: " "))")
    #expect(wrong.isEmpty, "Wrong: \(wrong.joined(separator: " "))")
}
