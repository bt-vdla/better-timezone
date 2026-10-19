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

    @Test func durations() {
        #expect(dur(90) == "1h 30m")
        #expect(dur(-1500) == "1d 1h")
        #expect(snap(22) == 15)
    }
}
