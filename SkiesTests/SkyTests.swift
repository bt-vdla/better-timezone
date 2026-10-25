import Testing
import Foundation
@testable import Skies

struct SkyTests {
    let team = Person.defaults
    var home: Person { team[0] }
    // Monday 2026-10-19 12:00 UTC: London still on BST, San Francisco on PDT.
    let mondayNoonUTC = 1_792_411_200.0 / 60
    // Monday 2026-11-02 12:00 UTC: London on GMT, San Francisco on PST.
    let afterUSChange = 1_793_620_800.0 / 60

    @Test func localReading() {
        let l = Local(home.tz, mondayNoonUTC)
        #expect(l.off == 330)
        #expect(l.h == 17 && l.m == 30)
        #expect(l.wd == 1)
    }

    @Test func everyoneFreeWindow() {
        let runs = freeRuns(team, from: dayStart(home.tz, mondayNoonUTC), slots: 96)
        #expect(runs.count == 1)
        #expect(runs.first.map { Local(home.tz, $0.lowerBound).f } == 20.5)
        #expect(runs.first.map { $0.upperBound - $0.lowerBound } == 90)
    }

    @Test func usClockChangeShrinksWindow() {
        let runs = freeRuns(team, from: dayStart(home.tz, afterUSChange), slots: 96)
        #expect(runs.first.map { Local(home.tz, $0.lowerBound).f } == 21.5)
        #expect(runs.first.map { $0.upperBound - $0.lowerBound } == 30)
        let changes = clockChanges(team, in: mondayNoonUTC...afterUSChange)
        #expect(changes.map(\.person.city) == ["London", "San Francisco"])
        #expect(changes.allSatisfy { $0.shift == -60 })
    }

    @Test func daysOffBreakTheWindow() {
        var weekendOnly = team
        weekendOnly[2].days = [0, 6]
        #expect(freeRuns(weekendOnly, from: dayStart(home.tz, mondayNoonUTC), slots: 96).isEmpty)
    }

    @Test func londonSunriseAndSunset() {
        let london = team[2]
        let s = sun(london, Local(london.tz, mondayNoonUTC))
        // Real: 07:29 / 17:57 BST. Should land within 6 minutes.
        #expect(abs(s.rise - 7.48) < 0.1)
        #expect(abs(s.set - 17.95) < 0.1)
        #expect(solar(s.noon, s).day)
    }

    @Test func londonNoonSunHeight() {
        // Solar noon 19 Oct 2026 is about 11:44 UTC; declination is about −10.1°, so 90 − 51.5 − 10.1 ≈ 28.4° up.
        let elev = sunPosition(team[2], mondayNoonUTC - 16).elev
        #expect(abs(elev - 28.4) < 0.3)
        #expect(sunPosition(team[2], mondayNoonUTC + 12 * 60).elev < -18)
    }

    @Test func moonPhaseAtAKnownFullMoon() {
        // Full moon 25 Jan 2024 17:54 UTC.
        let phase = moonPhase(1_706_205_240 / 60)
        #expect(abs(phase - 0.5) < 0.03)
    }

    @Test func relationshipFromLabel() {
        #expect(Person.Kind.infer("Design team", isHome: false) == .work)
        #expect(Person.Kind.infer("Partners", isHome: false) == .work)
        #expect(Person.Kind.infer("Partner", isHome: false) == .personal)
        #expect(Person.Kind.infer("Mom", isHome: false) == .personal)
        #expect(Person.Kind.infer("Priya", isHome: false) == .personal)
        #expect(Person.Kind.infer("You", isHome: true) == .work)
        #expect(team.allSatisfy { $0.relation == .work })
    }

    @Test func personalStatuses() {
        var family = team[2]
        family.label = "Family"
        family.applyPreset(.personal)
        // Monday 19 Oct, London on BST (UTC+1).
        #expect(status(family, Local(family.tz, mondayNoonUTC - 120)).0 == "Probably busy")      // 11:00
        #expect(status(family, Local(family.tz, mondayNoonUTC)).0 == "Lunch break")              // 13:00
        #expect(status(family, Local(family.tz, mondayNoonUTC + 5 * 60)).0 == "Good time to call") // 18:00
        #expect(status(family, Local(family.tz, mondayNoonUTC + 7 * 60)).0 == "Dinner time")     // 20:00
        #expect(status(team[2], Local(family.tz, mondayNoonUTC + 7 * 60)).0 == "Off work")       // same hour, work
    }

    @Test func talkingTimeWithFamily() {
        var family = team[2]
        family.label = "Family"
        family.applyPreset(.personal)
        let pair = [home, family]
        // Monday: both busy 9–5 their time, so only lunch and evenings line up (in Hyderabad time).
        let monday = freeRuns(pair, from: dayStart(home.tz, mondayNoonUTC), slots: 96, mode: .personal)
        #expect(monday.map { Local(home.tz, $0.lowerBound).f } == [12.5, 17, 21.5])
        // Saturday: your own row switches to free-time hours, so the weekend opens up.
        let saturday = mondayNoonUTC + 5 * 1440
        #expect(!freeRuns(pair, from: dayStart(home.tz, saturday), slots: 96, mode: .personal).isEmpty)
        #expect(freeRuns(pair, from: dayStart(home.tz, saturday), slots: 96).isEmpty)
    }

    @Test func localWorkingWeeks() {
        #expect(Person.workdays("IN") == [1, 2, 3, 4, 5, 6])   // CLDR: Sunday is India's weekend
        #expect(Person.workdays("GB") == [1, 2, 3, 4, 5])
        var vizag = Person(city: "Visakhapatnam", label: "Family", tzID: "Asia/Kolkata", lat: 17.69, lon: 83.22, region: "IN")
        vizag.applyPreset(.personal)
        let saturday = mondayNoonUTC + 5 * 1440                    // Sat 24 Oct, 5:30 PM there; 12:30 PM there two hours earlier
        #expect(vizag.weekdays == [1, 2, 3, 4, 5])
        #expect(!vizag.busyDay(Local(vizag.tz, saturday - 300)))
        #expect(Person.workdays("SA") == [0, 1, 2, 3, 4])      // Sunday to Thursday
        #expect(Person.workdays(nil) == [1, 2, 3, 4, 5])
        var riyadh = Person(city: "Riyadh", label: "Family", tzID: "Asia/Riyadh", lat: 24.71, lon: 46.68, region: "SA")
        riyadh.applyPreset(.personal)
        let friday = mondayNoonUTC + 4 * 1440                      // Fri 23 Oct, 3 PM in Riyadh
        #expect(!riyadh.busyDay(Local(riyadh.tz, friday)))
        #expect(riyadh.busyDay(Local(riyadh.tz, mondayNoonUTC)))
        #expect(status(riyadh, Local(riyadh.tz, friday)).0 == "Good time to call")
    }

    @Test func birthdayOnTheirLocalDay() {
        var london = team[2]
        london.contact = Person.Contact(id: "x", name: "Ada Lovelace", birthday: DateComponents(month: 10, day: 19))
        #expect(london.birthday(Local(london.tz, mondayNoonUTC)))          // Mon 19 Oct in London
        #expect(!london.birthday(Local(london.tz, mondayNoonUTC + 1440)))
        #expect(london.contact?.firstName == "Ada" && london.contact?.initials == "AL")
    }

    @MainActor @Test func shareCardRendersAPNG() throws {
        let card = MomentCard(team: Array(team.prefix(3)), minutes: mondayNoonUTC, talk: true)
        let png = try card.png()
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(card.text.hasPrefix("Let's talk: Me 5:30 PM Mon"))
        // Left in the (sandboxed) temp folder so the card can be eyeballed after a run.
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("skies-card.png"))
    }

    @Test func reachLinks() {
        let n = "+1 (555) 522-8243"
        #expect(Channel(method: .call, value: n).url?.absoluteString == "tel:+15555228243")
        #expect(Channel(method: .facetimeAudio, value: n).url?.absoluteString == "facetime-audio:+15555228243")
        #expect(Channel(method: .whatsapp, value: n).url?.absoluteString == "https://wa.me/15555228243")
        #expect(Channel(method: .facetime, value: "ada@example.com").url?.absoluteString == "facetime:ada@example.com")

        var old = Person.Contact(id: "x", name: "Ada", phone: n)
        #expect(old.numbers == [.init(label: "phone", value: n)])            // saved before every number was kept
        #expect(old.preferred == Channel(method: .call, value: n))
        old.favourite = Channel(method: .whatsapp, value: n)
        #expect(old.preferred?.method == .whatsapp)
    }

    @Test func airportCodesAndNames() {
        // Defaults: Hyderabad, Georgetown, London, Dubai, San Francisco.
        #expect(team.map(\.code) == ["HYD", "GEO", "LHR", "DXB", "SFO"])
        let vizag = Person(city: "Visakhapatnam", label: "Family", tzID: "Asia/Kolkata", lat: 17.69, lon: 83.22)
        #expect(vizag.code == "VTZ")
        #expect(vizag.name == "Family")
        var mom = vizag
        mom.contact = Person.Contact(id: "x", name: "Anna Haro")
        #expect(mom.name == "Anna")
        mom.codeOverride = "VIZ"
        #expect(mom.code == "VIZ")
        #expect(mom.title(.name) == "Anna" && mom.tag(.name) == "VIZ")
        #expect(mom.title(.code) == "VIZ" && mom.tag(.code) == "Anna")
        #expect(mom.title(.city) == "Visakhapatnam")
        // No airport within 100 km: the city's first three letters.
        let nowhere = Person(city: "Point Nemo", label: "", tzID: "UTC", lat: -48.88, lon: -123.39)
        #expect(nowhere.code == "POI")
        #expect(team[0].name == "You")
    }

    // Tags are read from the catalogue but never saved here: tests share the real app's defaults.
    @Test func hashtagParsing() {
        #expect(Tags.hashtags(in: "Amma #family ") == ("Amma", ["family"], nil))
        #expect(Tags.hashtags(in: "Amma #fa").typing == "fa")
        #expect(Tags.hashtags(in: "Amma #fa").tags.isEmpty)
        #expect(Tags.hashtags(in: "Amma #fa", final: true) == ("Amma", ["fa"], nil))
        #expect(Tags.hashtags(in: "Amma #").typing == "")
        #expect(Tags.hashtags(in: "Juggy #friends #team ") == ("Juggy", ["friends", "team"], nil))
    }

    @Test func tagsKeepTheName() {
        var amma = Person(city: "Visakhapatnam", label: "Amma", tzID: "Asia/Kolkata", lat: 17.72, lon: 83.31, region: "IN")
        #expect(Tags.suggest(for: amma)?.id == "family")
        amma.label = "Amma #family "
        amma.takeHashtags()
        #expect(amma.label == "Amma" && amma.tagList == ["family"])
        #expect(amma.relation == .personal)
        amma.toggleTag("client")
        #expect(amma.label == "Amma" && amma.tagList == ["family", "client"])
        #expect(Tags.suggest(for: amma) == nil)
        // The first tag decides; hours move only while they're still a preset.
        var juggy = Person(city: "San Francisco", label: "Juggy", tzID: "America/Los_Angeles", lat: 37.77, lon: -122.42, region: "US")
        juggy.applyPreset(.personal)
        juggy.toggleTag("team")
        #expect(juggy.relation == .work && juggy.start == 9 && juggy.end == 18)
        #expect(Tags.match("Family")?.id == "family" && Tags.match("Partners") == nil)
    }

    @Test func tagQuietHours() {
        let t = PersonTag(id: "x", name: "Clients", kind: .work, color: 0, notBefore: 10, notAfter: 17, skipWeekend: true)
        let utc = TimeZone(identifier: "UTC")!
        #expect(!t.allows(Local(utc, mondayNoonUTC - 180), workdays: [1, 2, 3, 4, 5]))
        #expect(t.allows(Local(utc, mondayNoonUTC - 60), workdays: [1, 2, 3, 4, 5]))
        #expect(!t.allows(Local(utc, mondayNoonUTC - 60 - 2 * 1440), workdays: [1, 2, 3, 4, 5]))
    }

    @Test func worldLine() {
        // Noon UTC, 19 October: the sun runs about 15 minutes fast, so it's overhead ~3.7° west, at about −10° latitude.
        let s = subsolar(mondayNoonUTC)
        #expect(s.lat > -11 && s.lat < -9)
        #expect(s.lon > -6 && s.lon < -1.5)
        #expect(sunHeight(lat: s.lat, lon: s.lon, below: s) > 89.9)
        #expect(sunHeight(lat: 0, lon: 180, below: s) < -70)
    }

    @Test func durations() {
        #expect(dur(90) == "1h 30m")
        #expect(dur(-1500) == "1d 1h")
        #expect(snap(22) == 15)
    }
}
