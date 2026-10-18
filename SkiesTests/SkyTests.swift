import Testing
import Foundation
@testable import Skies

struct SkyTests {
    // 2026-10-18 12:00 UTC: London is on BST, San Francisco on PDT.
    let noonUTC = Date(timeIntervalSince1970: 1_792_324_800).timeIntervalSince1970 / 60

    @Test func localReading() {
        let l = Local(home.tz, noonUTC)
        #expect(l.off == 330)
        #expect(l.h == 17 && l.m == 30)
        #expect(l.wd == 0)
    }

    @Test func everyoneAwakeWindow() {
        let runs = overlapRuns(noonUTC)
        #expect(runs.count == 1)
        #expect(runs.first.map { Local(home.tz, $0.lowerBound).f } == 20.5)
        #expect(runs.first.map { $0.upperBound - $0.lowerBound } == 90)
    }

    @Test func durations() {
        #expect(dur(90) == "1h 30m")
        #expect(dur(-1500) == "1d 1h")
        #expect(dur(45) == "45m")
        #expect(snap(22) == 15)
    }
}
