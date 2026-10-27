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

    @Test func typedTimes() {
        // Monday 5:30 PM in Hyderabad.
        let now = mondayNoonUTC
        func at(_ q: String) -> (h: Int, m: Int, wd: Int, who: String?)? {
            guard let j = JumpParser.parse(q, people: team, now: now) else { return nil }
            let l = Local((j.person ?? home).tz, j.minutes)
            return (l.h, l.m, l.wd, j.person?.city)
        }
        #expect(at("8pm")! == (20, 0, 1, nil))
        #expect(at("3pm")! == (15, 0, 2, nil))            // gone today, so tomorrow
        #expect(at("9")! == (21, 0, 1, nil))              // the next 9 o'clock
        #expect(at("noon")! == (12, 0, 2, nil))
        #expect(at("6:45 pm")! == (18, 45, 1, nil))
        #expect(at("London 3pm")! == (15, 0, 1, "London"))
        #expect(at("fri 9am Dubai")! == (9, 0, 5, "Dubai"))
        #expect(at("san francisco 9am")! == (9, 0, 1, "San Francisco"))
        #expect(at("fri 3")! == (15, 0, 5, nil))          // a named day reads 1–6 as afternoon
        #expect(at("tomorrow")! == (9, 0, 2, nil))
        #expect(JumpParser.parse("in 2h", people: team, now: now)?.minutes == now + 120)
        #expect(JumpParser.parse("+90m", people: team, now: now)?.minutes == now + 90)
        #expect(JumpParser.parse("Partners", people: team, now: now) == nil)
        #expect(JumpParser.parse("25pm", people: team, now: now) == nil)
    }

    @Test func placesAnywhere() {
        let now = mondayNoonUTC
        func at(_ q: String) -> (h: Int, wd: Int, tz: String, mine: Int)? {
            guard let j = JumpParser.parse(q, people: team, now: now), let z = j.zone else { return nil }
            return (Local(z.tz, j.minutes).h, Local(z.tz, j.minutes).wd, z.tz.identifier, Local(home.tz, j.minutes).h)
        }
        // Home is Hyderabad here, so India 3pm is gone today and means tomorrow.
        #expect(at("india 3pm")! == (15, 2, "Asia/Kolkata", 15))
        #expect(at("3pm tokyo")! == (15, 2, "Asia/Tokyo", 11))     // 3 PM Tokyo is 11:30 AM in Hyderabad
        #expect(at("3pm pst")!.tz == "America/Los_Angeles")
        #expect(at("new york 9am")!.tz == "America/New_York")
        #expect(at("germany 9am")!.tz == "Europe/Berlin")
        #expect(Places.zone(named: "Bengaluru")?.tz.identifier == "Asia/Kolkata")
        // Spans from now, with or without a place.
        let span = { (q: String) in JumpParser.parse(q, people: team, now: now) }
        #expect(span("india 3 hours from now")?.minutes == now + 180)
        #expect(span("india 3 hours from now")?.zone?.tz.identifier == "Asia/Kolkata")
        #expect(span("tokyo in 90 mins")?.minutes == now + 90)
        #expect(span("an hour from now")?.minutes == now + 60)
        #expect(span("london in half an hour")?.zone?.tz.identifier == "Europe/London")   // Partners' clock
        #expect(span("london in half an hour")?.minutes == now + 30)
        #expect(span("2h ago")?.minutes == now - 120)
        // The answer says how far from now, which is what the question was about.
        let head = { (q: String) in Ask.hits(q, people: team, now: now).first?.headline }
        #expect(head("ist 5 hours from now") == "In 5h")
        #expect(head("tokyo in 90 mins") == "In 1h 30m")
        #expect(head("2h ago") == "2h ago")
        #expect(head("8pm") == "In 2h 30m")   // 5:30 PM in Hyderabad now
        #expect(Ask.placeWords("Visakhapatnam 3pm") == "visakhapatnam")
    }

    /// "7am guyana time to india time" and friends: a time on one clock, read on another.
    @Test func conversions() {
        let now = mondayNoonUTC   // Mon: 8:00 Guyana, 13:00 London (BST), 8:00 New York (EDT), 5:00 SF, 17:30 India
        struct C: Equatable { let fromTZ: String, fromH: Int, toTZ: String, toH: Int, toM: Int, toWD: Int }
        func c(_ q: String) -> C? {
            guard let j = JumpParser.parse(q, people: team, now: now), let f = j.zone, let t = j.to else { return nil }
            let a = Local(f.tz, j.minutes), b = Local(t.tz, j.minutes)
            return C(fromTZ: f.tz.identifier, fromH: a.h, toTZ: t.tz.identifier, toH: b.h, toM: b.m, toWD: b.wd)
        }
        let guyanaToIndia = C(fromTZ: "America/Guyana", fromH: 7, toTZ: "Asia/Kolkata", toH: 16, toM: 30, toWD: 2)
        #expect(c("7am guyana time to india time") == guyanaToIndia)   // 7am already gone in Guyana: tomorrow
        #expect(c("7am Guyana time to India time?") == guyanaToIndia)
        #expect(c("7 am guyana to india") == guyanaToIndia)
        #expect(c("7 a.m. guyana → india") == guyanaToIndia)
        #expect(c("guyana 7am to india") == guyanaToIndia)
        #expect(c("india time for 7am guyana") == guyanaToIndia)
        #expect(c("what time in india when it's 7am in guyana") == guyanaToIndia)
        #expect(c("7am guyana in ist") == guyanaToIndia)
        #expect(c("3pm london to tokyo") == C(fromTZ: "Europe/London", fromH: 15, toTZ: "Asia/Tokyo", toH: 23, toM: 0, toWD: 1))
        #expect(c("convert 3pm est to ist") == C(fromTZ: "America/New_York", fromH: 15, toTZ: "Asia/Kolkata", toH: 0, toM: 30, toWD: 2))
        #expect(c("9am my time in dubai") == C(fromTZ: "Asia/Kolkata", fromH: 9, toTZ: "Asia/Dubai", toH: 7, toM: 30, toWD: 2))
        #expect(c("3pm to tokyo") == C(fromTZ: "Asia/Kolkata", fromH: 15, toTZ: "Asia/Tokyo", toH: 18, toM: 30, toWD: 2))
        #expect(c("design review 9am to partners") == C(fromTZ: "America/Los_Angeles", fromH: 9, toTZ: "Europe/London", toH: 17, toM: 0, toWD: 1))
        #expect(c("fri 10am sydney to london")?.toTZ == "Europe/London")
        #expect(c("fri 10am sydney to london")?.fromH == 10)
        // Still one clock: "3pm in tokyo" is Tokyo's 3pm, and plain times are yours.
        #expect(JumpParser.parse("3pm in tokyo", people: team, now: now)?.to == nil)
        #expect(JumpParser.parse("3pm in tokyo", people: team, now: now)?.zone?.tz.identifier == "Asia/Tokyo")
        #expect(JumpParser.parse("8pm", people: team, now: now)?.zone == nil)
        // The answer says both.
        #expect(Ask.hits("7am guyana time to india time", people: team, now: now).first?.title == "7:00 AM in Guyana is 4:30 PM in India")
        #expect(Ask.hits("what time is it in india when it's 9am in new york", people: team, now: now).first?.title == "9:00 AM in New York is 6:30 PM in India")
        #expect(Ask.hits("3pm london to tokyo", people: team, now: now).first?.title == "3:00 PM in London is 11:00 PM in Tokyo")
        #expect(Ask.hits("9am my time in dubai", people: team, now: now).first?.title.hasPrefix("Your 9:00 AM is") == true)
    }

    /// Airport codes: anywhere in the world, as a clock to read or convert to.
    @Test func airportCodes() {
        let now = mondayNoonUTC
        let p = { (q: String) in JumpParser.parse(q, people: team, now: now) }
        // 7am JFK has gone (8:00 there), so Tuesday 7:00 EDT = 16:30 in Mumbai.
        let j = p("7am jfk to bom")
        #expect(j?.zone?.tz.identifier == "America/New_York" && j?.to?.tz.identifier == "Asia/Kolkata")
        #expect(j.map { Local(TimeZone(identifier: "Asia/Kolkata")!, $0.minutes) }.map { ($0.h, $0.m) } ?? (0, 0) == (16, 30))
        #expect(p("3pm LHR to NRT")?.to?.tz.identifier == "Asia/Tokyo")
        #expect(p("9am syd")?.zone?.tz.identifier == "Australia/Sydney")
        #expect(p("noon elp")?.zone?.tz.identifier == "America/Denver")      // El Paso: Mountain, unlike the rest of Texas
        #expect(p("noon bna")?.zone?.tz.identifier == "America/Chicago")     // Nashville: Central
        #expect(p("noon dps")?.zone?.tz.identifier == "Asia/Makassar")       // Bali
        #expect(p("noon pek")?.zone?.tz.identifier == "Asia/Shanghai")
        #expect(Ask.hits("syd", people: team, now: now).first?.title.hasSuffix("in Sydney (SYD)") == true)
        // Everyday words stay words, unless typed in capitals.
        #expect(p("the 3pm")?.zone == nil)
        #expect(p("sea 9am")?.zone == nil)
        #expect(p("SEA 9am")?.zone?.tz.identifier == "America/Los_Angeles")
        // Codes Skies can't be sure of offline come from Apple Maps, then work the same way.
        #expect(p("kzn 3pm")?.zone == nil)
        let kazan = Zone(name: "KZN", tz: TimeZone(identifier: "Europe/Moscow")!)
        #expect(JumpParser.parse("kzn 3pm to dubai", people: team, now: now, extra: [kazan])?.zone?.name == "KZN")
        let labelled = Zone(name: "Kazan (KZN)", tz: TimeZone(identifier: "Europe/Moscow")!, key: "kzn")
        #expect(JumpParser.parse("kzn 3pm to dubai", people: team, now: now, extra: [labelled])?.zone?.name == "Kazan (KZN)")
    }

    /// Typos: read as what was meant, but only when that makes sense of the question.
    @Test func typos() {
        let now = mondayNoonUTC
        let read = { (q: String) in Ask.readAs(q, people: team, now: now) }
        let top = { (q: String) in Ask.hits(q, people: team, now: now).first?.title ?? "" }
        #expect(read("7am est toi ist") == "7am est to ist")
        #expect(top("7am est toi ist") == top("7am est to ist"))
        #expect(read("7am guyna time to inda time") == "7am guyana time to india time")
        #expect(top("7am guyna to inda") == "7:00 AM in Guyana is 4:30 PM in India")
        #expect(read("3pm londn to tokio") == "3pm london to tokyo")
        #expect(read("new yrok 9am")?.hasPrefix("new york") == true)
        #expect(read("newyork 9am") == "new york 9am")
        #expect(read("whn can i tlk to partners") == "when can i talk to partners")
        #expect(top("is investr awake").hasPrefix("Yes"))
        #expect(read("9am dubia") == "9am dubai")
        // Already right: left alone.
        #expect(read("7am est to ist") == nil)
        #expect(read("sin 3pm") == nil)          // Singapore's code, not "in"
        #expect(read("is partners awake") == nil)
        #expect(read("time in tokyo") == nil)
        // The keyboard shapes the guess: o and i are neighbours, so "toi" is a slip of "to", not a word.
        #expect(Typos.distance("tine", "time") < Typos.distance("tixe", "time"))
        #expect(Typos.distance("tokoy", "tokyo") == 0.5)
        // Time-zone abbreviations are words Skies knows, not typos; short words never become airport codes.
        #expect(read("1pm gyt to ist") == nil)
        #expect(top("1pm gyt to ist") == "1:00 PM in Guyana Time is 10:30 PM in India")
        #expect(top("9am npt to aest").hasPrefix("9:00 AM in Nepal Time"))
        #expect(top("9am wit to wib").contains("Eastern Indonesia") || top("9am wit to wib").contains("Jayapura"))
        // Two slips on a three-letter word is a guess too far: left as typed.
        #expect(read("1pm gyx to ist") == nil)
        #expect(read("9am xyt") == nil)
        #expect(read("9am qyt") == nil)
    }

    /// Clock changes, as cues on answers and as questions. Europe went back on Sun 25 Oct 2026, the US on Sun 1 Nov.
    @Test func daylightSaving() {
        let now = mondayNoonUTC                // Mon 19 Oct, before either change
        let weekLater = now + 7 * 1440         // Mon 26 Oct, the day after Europe's
        let first = { (q: String, at: Double) in Ask.hits(q, people: team, now: at).first }
        // A change between now and then: the gap then isn't today's.
        let sunday = first("sun 9am london to india", now)
        #expect(sunday?.gap == "+5h 30m")
        #expect(sunday?.cue == "London's clocks go back 1h Sun, 25 Oct: 5h 30m apart then, 4h 30m now")
        // A change in the past week: today's gap is new.
        #expect(first("3pm london to india", weekLater)?.cue == "London's clocks went back 1h yesterday: 5h 30m apart now, was 4h 30m")
        // A change in the fortnight after: worth knowing before it becomes a habit.
        #expect(first("fri 9am new york to london", now)?.cue == "From Sun, 25 Oct, 4h apart: London's clocks go back 1h")
        // Nothing changing: no cue. Summer time is tagged on its clock.
        #expect(first("3pm tokyo to india", now)?.cue == nil)
        #expect(first("3pm london to tokyo", now)?.clocks.first?.day.hasSuffix("summer time") == true)
        #expect(first("9am new york to tokyo", now)?.clocks.first?.day.hasSuffix("daylight time") == true)
        // Asked directly.
        #expect(first("when do clocks change in london", now)?.title == "London's clocks go back 1h Sun, 25 Oct")
        #expect(first("does india have dst", now)?.title == "India doesn't change its clocks")
        #expect(first("does india have dst", now)?.detail.hasPrefix("Always UTC+5:30") == true)
        #expect(first("is new york on daylight time", now)?.title == "Yes: New York is on daylight time (UTC−4)")
        #expect(first("is tokyo on summer time?", now)?.title == "No: Tokyo doesn't change its clocks")
        #expect(first("dst sydney", now)?.title.hasPrefix("Sydney's clocks go back 1h") == true)
        #expect(Ask.readAs("when do clocks chnage in london", people: team, now: now) == "when do clocks change in london")

        // After a change: the gap then against now (home here is Hyderabad, which never changes).
        #expect(first("after dst ends, what's my time vs london", now)?.title == "After Sun, 25 Oct, London is 5h 30m behind you")
        #expect(first("after dst ends, what's my time vs london", now)?.gap == "−5h 30m")
        #expect(first("when dst ends, gap to new york", now)?.title == "After Sun, 1 Nov, New York is 10h 30m behind you")
        #expect(first("once summer time starts in london, gap to me", now)?.title == "After Sun, 28 Mar, London is 4h 30m behind you")
        #expect(first("after dst what will my time be in relation to ist", now)?.title == "No clock change ahead for you or India")
        #expect(first("after dst, my time vs dubai", now)?.title == "No clock change ahead for you or Dubai")
        // With a time: read on the first day after the change.
        let later = first("after the clocks go back, 9am new york in india", now)
        #expect(later?.title == "9:00 AM in New York is 7:30 PM in India")
        #expect(later?.cue == "New York's clocks go back 1h Sun, 1 Nov")
        // Typos too.
        #expect(first("aftr dst ends whats my time vs london", now)?.title == "After Sun, 25 Oct, London is 5h 30m behind you")

        // The heads-up: the nearest change in the next fortnight (or the last two days) that moves someone's gap,
        // and a question Ask can answer about it.
        let ahead = Clocks.headsUp(team, now: now)
        #expect(ahead?.text == "Partners' clocks go back in 6 days")
        #expect(ahead?.short == "Clocks go back in 6d")
        #expect(first(ahead!.ask, now)?.title == "After Sun, 25 Oct, Partners is 5h 30m behind you")
        let behind = Clocks.headsUp(team, now: weekLater)
        #expect(behind?.text == "Partners' clocks went back yesterday")
        #expect(first(behind!.ask, weekLater)?.cue?.hasPrefix("Partners' clocks went back 1h yesterday") == true)
        #expect(Clocks.headsUp(team, now: now + 60 * 1440) == nil)   // mid-December: nothing for weeks
    }

    @Test func questions() {
        let now = mondayNoonUTC   // Monday 5:30 PM Hyderabad, 7:00 AM Georgetown, 5:00 AM San Francisco
        let first = { (q: String) in Ask.hits(q, people: team, now: now).first?.title ?? "" }
        #expect(first("is design review awake?").hasPrefix("No, Design review's asleep"))
        #expect(first("Is Investor up").hasPrefix("Yes"))
        #expect(first("when can I speak to partners?").hasPrefix("Free with Partners"))
        #expect(first("when can i talk to everyone").contains("everyone"))
        #expect(first("what time is it in tokyo").hasSuffix("in Tokyo"))
        #expect(first("tokyo").hasSuffix("in Tokyo"))
        #expect(Ask.target("my team", team) == nil)   // no tags on the defaults
        #expect(Ask.target("partners and investor", team)?.members.count == 2)
    }

    @Test func durations() {
        #expect(dur(90) == "1h 30m")
        #expect(dur(-1500) == "1d 1h")
        #expect(snap(22) == 15)
    }
}
