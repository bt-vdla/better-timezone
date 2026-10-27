import SwiftUI

/// Every release of Skies, newest first. Add one here with every version or build bump: a test checks the top entry
/// matches the app's own version and build.
struct Release: Identifiable {
    enum Kind { case new, better, fixed }
    let version: String, build: Int, date: String
    let changes: [(Kind, String)]
    var id: Int { build }

    static var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var installedBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }

    static let all: [Release] = [
        Release(version: "1.1.1", build: 5, date: "2026-10-27", changes: [
            (.new, "Version history, under People on iPhone and in Settings on Mac"),
            (.fixed, "Ask answers \"can I call Kate now\" and \"is it a good time to ring Mom\" with yes or not now, and when they're next free"),
        ]),
        Release(version: "1.1", build: 4, date: "2026-10-27", changes: [
            (.new, "Fair meeting times: \"find 30 min for team this week\" spreads the out-of-hours stretch so nobody carries it"),
            (.new, "Skip my meetings: your calendar's busy times come out of every free window"),
            (.new, "Wake-up and birthday notifications, timed for each person"),
            (.new, "12- or 24-hour clocks everywhere, including widgets"),
            (.new, "Mac menu bar shows up to three clocks, from your people or any city"),
            (.new, "Convert Time with Skies in the Mac Services menu"),
            (.new, "Fuller first-run setup, vivid skies in the notch, grain on widget skies"),
            (.better, "Scrubbing is smoother, and rows and the header no longer jump"),
            (.better, "Every button's whole shape is tappable"),
            (.better, "Far less battery: the Mac window rests when closed, minimised or in the background, clocks redraw on the minute, and stars hold still in Low Power Mode"),
            (.better, "Widget +1h and −1h reload less and no longer dim between taps"),
            (.fixed, "The header time no longer truncates"),
            (.fixed, "\"Tomorrow, 9h 30m ahead\" fits its row"),
        ]),
        Release(version: "1.0", build: 3, date: "2026-10-26", changes: [
            (.new, "Ask Skies in the notch and on iPhone: \"india 3pm\", \"is Amma awake\", \"when can I talk to family\", \"time in Tokyo\""),
            (.new, "Conversions between two clocks: \"7am guyana time to india\", \"time in india when it's 9am in new york\""),
            (.new, "Airport codes everywhere, and a typo corrector that shows \"Read as …\""),
            (.new, "Daylight saving: the gap between clocks, clock-change cues and questions, and a heads-up two weeks ahead"),
            (.new, "One orbit app icon on iPhone and Mac"),
            (.better, "Even spacing and concentric corners in the notch"),
            (.fixed, "Long holiday names no longer push the home screen sideways"),
        ]),
        Release(version: "1.0", build: 2, date: "2026-10-25", changes: [
            (.new, "Widgets on iPhone and Mac: Person, Everyone's skies, Next time to talk and Reach now, with time travel"),
            (.new, "Lock Screen widgets, a Control Center button and a Live Activity on iPhone"),
            (.new, "Tags for people, with colours, quiet hours and a Focus filter"),
        ]),
        Release(version: "1.0", build: 1, date: "2026-10-24", changes: [
            (.new, "Skies: a sky for every person, scrubbed through the day with a spring"),
            (.new, "Real skies from each city's sun and moon, drawn by a shader with stars and lens flare"),
            (.new, "People with free hours, days off, linked contacts, birthdays and public holidays"),
            (.new, "Planner, person pages and onboarding"),
            (.new, "Mac: Skies in the notch, opened with ⌃⌥S, and a menu bar item"),
            (.new, "Names first, with each city's airport code beside them"),
            (.better, "Dynamic Type across Skies"),
        ]),
    ]
}

/// The version log: what changed in each release, newest first, with the one on this device marked.
struct ReleaseLog: View {
    var body: some View {
        List {
            ForEach(Release.all) { r in
                Section {
                    ForEach(r.changes.indices, id: \.self) { i in
                        let (kind, text) = r.changes[i]
                        Label {
                            Text(text)
                        } icon: {
                            Image(systemName: kind.symbol).foregroundStyle(kind.color)
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(r.version) (\(r.build))").font(.headline).foregroundStyle(.primary)
                        Text(r.day).foregroundStyle(.secondary)
                        Spacer()
                        if r.build == Release.installedBuild {
                            Text("Installed").font(.caption.weight(.semibold)).foregroundStyle(.green)
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .navigationTitle("Version History")
    }
}

/// "Version 1.1.1 (5)", for the bottom of settings.
struct VersionLabel: View {
    var body: some View {
        LabeledContent("Version", value: "\(Release.installedVersion) (\(Release.installedBuild))")
    }
}

private extension Release {
    /// Read and shown in UTC, so "2026-10-27" stays the 27th west of Greenwich too.
    var day: String {
        guard let d = try? Date(date, strategy: .iso8601.year().month().day()) else { return date }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.timeZone = .gmt
        return d.formatted(style)
    }
}

private extension Release.Kind {
    var symbol: String {
        switch self { case .new: "sparkles"; case .better: "arrow.up.circle"; case .fixed: "wrench.adjustable" }
    }
    var color: Color {
        switch self { case .new: .yellow; case .better: .blue; case .fixed: .green }
    }
}
