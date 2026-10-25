import AppIntents
#if os(iOS)
import ActivityKit
#endif

/// Opens Skies. The Control Center button runs it; it lives in both the app and the widgets so the system can open the app.
struct OpenSkiesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Skies"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

#if os(iOS)
/// A Live Activity counting down to the next time you're all free, then down to when it closes.
struct WindowActivity: ActivityAttributes {
    /// "Family", "Kate", "Everyone".
    let who: String
    let talk: Bool

    struct ContentState: Codable, Hashable {
        let start: Date
        let end: Date
    }
}
#endif
