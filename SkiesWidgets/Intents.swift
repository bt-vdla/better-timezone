import AppIntents
import WidgetKit

// MARK: - Choosing a person

struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonQuery()

    let id: String
    let name: String
    let city: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(city)") }

    init(_ p: Person) {
        id = p.id.uuidString
        name = p.name
        city = p.city
    }
}

struct PersonQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PersonEntity] {
        Person.saved().filter { identifiers.contains($0.id.uuidString) }.map(PersonEntity.init)
    }

    func suggestedEntities() async throws -> [PersonEntity] { Person.saved().map(PersonEntity.init) }

    /// Someone other than you, if there is anyone.
    func defaultResult() async -> PersonEntity? {
        let all = Person.saved()
        return (all.first { !$0.isHome } ?? all.first).map(PersonEntity.init)
    }
}

struct PersonConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Person"
    static let description = IntentDescription("Their sky and their time.")

    @Parameter(title: "Person") var person: PersonEntity?
}

struct NextConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Next time to talk"
    static let description = IntentDescription("When you and someone (or everyone) are next free together.")

    @Parameter(title: "With", description: "One person. Leave empty to use a tag or everyone") var person: PersonEntity?
    @Parameter(title: "Or a tag", description: "Everyone with this tag") var tag: TagEntity?
}

struct StackConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Everyone's skies"
    static let description = IntentDescription("Your people, sky by sky.")

    @Parameter(title: "Tag", description: "Leave empty for everyone") var tag: TagEntity?
}

extension Person {
    /// The configured person, or someone other than you if nothing is chosen yet.
    static func pick(_ entity: PersonEntity?, from all: [Person]) -> Person? {
        all.first { $0.id.uuidString == entity?.id } ?? all.first { !$0.isHome } ?? all.first
    }
}

// MARK: - Time travel

/// A shared offset the widgets show time at. It lapses after 15 minutes, so a widget never stays in the future.
enum TimeTravel {
    static let span: TimeInterval = 15 * 60
    private static let offsetKey = "timeTravel.offset", atKey = "timeTravel.at"

    static var since: Date? { UserDefaults.skies.object(forKey: atKey) as? Date }

    static func offset(at date: Date) -> Double {
        guard let since, date.timeIntervalSince(since) < span else { return 0 }
        return UserDefaults.skies.double(forKey: offsetKey)
    }

    static func shift(by minutes: Double) {
        set(minutes == 0 ? 0 : offset(at: .now) + minutes)
    }

    static func set(_ minutes: Double) {
        UserDefaults.skies.set(max(-24 * 60, min(24 * 60, minutes)), forKey: offsetKey)
        UserDefaults.skies.set(Date.now, forKey: atKey)
        // Only the widgets that show the offset; the next-window widget has nothing to redraw.
        for kind in ["person", "stack"] { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }
}

/// "Show me then": moves every widget straight to a moment, like the next time you're all free.
struct TravelIntent: AppIntent {
    static let title: LocalizedStringResource = "Jump to a time"
    static let isDiscoverable = false

    @Parameter(title: "Minutes from now") var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult {
        TimeTravel.set(Double(minutes))
        return .result()
    }
}

/// The people ticked on the Mac's stack widget, to plan with right there on the desktop.
enum WidgetPlan {
    static let key = "widget.plan"
    static var ids: Set<String> { Set(UserDefaults.skies.stringArray(forKey: key) ?? []) }
}

struct TogglePlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Include in the plan"
    static let isDiscoverable = false

    @Parameter(title: "Person") var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        var ids = WidgetPlan.ids
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.skies.set(Array(ids), forKey: WidgetPlan.key)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// −1h, +1h and Now on the widgets. Zero minutes means back to now.
struct ShiftTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Move through time"
    static let isDiscoverable = false

    @Parameter(title: "Minutes") var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult {
        // The offset is shared, so every Skies widget moves together, not just the one tapped.
        TimeTravel.shift(by: Double(minutes))
        return .result()
    }
}
