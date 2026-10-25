import SwiftUI
import AppIntents
import Synchronization

/// A group a person belongs to ("Family", "Client"), kept apart from their name. It says whether they're
/// work or personal, and can carry rules: quiet hours in their time, their weekend off, a calendar, a nudge.
struct PersonTag: Codable, Hashable, Identifiable, Sendable {
    /// Stable across renames, so people keep their tags when one is renamed.
    var id: String
    var name: String
    var kind: Person.Kind
    var color: Int
    /// Don't count them as free before or after these hours, their time.
    var notBefore: Double?
    var notAfter: Double?
    /// Leave their weekend alone.
    var skipWeekend = false
    /// Where Add to Calendar puts plans with them.
    var calendarID: String?
    /// A notification when the next shared window with everyone in this tag opens.
    var nudge = false

    var rgb: RGB { Tags.palette[color % Tags.palette.count] }

    /// Whether this tag's rules leave the moment open. `workdays` is the person's own working week.
    func allows(_ l: Local, workdays: Set<Int>) -> Bool {
        if let a = notBefore, l.f < a { return false }
        if let b = notAfter, l.f >= b { return false }
        return !(skipWeekend && !workdays.contains(l.wd))
    }
}

enum Tags {
    static let key = "tags.v1"

    static let palette: [RGB] = [
        [236, 104, 150], [64, 196, 170], [240, 128, 90], [96, 150, 240],
        [240, 180, 60], [160, 120, 230], [130, 200, 90], [150, 160, 180],
    ]

    static let builtIn: [PersonTag] = [
        PersonTag(id: "family", name: "Family", kind: .personal, color: 0),
        PersonTag(id: "friends", name: "Friends", kind: .personal, color: 1),
        PersonTag(id: "partner", name: "Partner", kind: .personal, color: 2),
        PersonTag(id: "team", name: "Team", kind: .work, color: 3),
        PersonTag(id: "client", name: "Client", kind: .work, color: 4),
    ]

    /// Cached by id: availability asks every 15-minute slot, so a lookup must not decode or allocate.
    private static let cache = Mutex<(list: [PersonTag], byID: [String: PersonTag])?>(nil)

    static var all: [PersonTag] { loaded.list }
    static func named(_ id: String) -> PersonTag? { loaded.byID[id] }

    private static var loaded: (list: [PersonTag], byID: [String: PersonTag]) {
        cache.withLock { c in
            if let c { return c }
            let list = UserDefaults.skies.data(forKey: key).flatMap { try? JSONDecoder().decode([PersonTag].self, from: $0) } ?? builtIn
            let fresh = (list, Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
            c = fresh
            return fresh
        }
    }

    /// Re-read after another process (the app, a widget) may have changed them.
    static func reload() { cache.withLock { $0 = nil } }

    static func save(_ list: [PersonTag]) {
        UserDefaults.skies.set(try? JSONEncoder().encode(list), forKey: key)
        reload()
    }

    /// A new tag from a typed name, guessing work or personal from the word itself.
    static func make(_ name: String) -> PersonTag {
        let base = name.lowercased().filter { $0.isLetter || $0.isNumber }
        var id = base.isEmpty ? "tag" : base, n = 2
        while named(id) != nil { id = "\(base)\(n)"; n += 1 }
        return PersonTag(id: id, name: name, kind: .infer(name, isHome: false), color: all.count)
    }

    /// The existing tag a typed word means ("family", "Family"), or nil.
    static func match(_ word: String) -> PersonTag? {
        let w = word.lowercased()
        return all.first { $0.id == w || $0.name.lowercased() == w }
    }

    /// What a name or contact suggests ("Amma" → Family). Shown as a suggestion, never applied by itself.
    // ponytail: word lists; a contact's relation field could feed this if the keyword guesses miss.
    static func suggest(for p: Person) -> PersonTag? {
        guard p.tagList.isEmpty, !p.isHome else { return nil }
        let words = Set(p.label.lowercased().split { !$0.isLetter }.map(String.init))
        for (id, keys) in hints where !words.isDisjoint(with: keys) {
            if let t = named(id) { return t }
        }
        return p.contact?.organization != nil ? named("team") : nil
    }

    private static let hints: [(String, Set<String>)] = [
        ("family", ["family", "amma", "appa", "mom", "mum", "mommy", "dad", "daddy", "mother", "father", "maa", "papa",
                    "nana", "nani", "dadi", "dada", "thatha", "ammamma", "brother", "sister", "bro", "sis", "bhai", "didi",
                    "akka", "anna", "aunt", "auntie", "uncle", "cousin", "grandma", "grandpa", "son", "daughter", "kids"]),
        ("partner", ["partner", "wife", "husband", "bae", "babe", "love", "darling", "honey", "gf", "bf"]),
        ("friends", ["friend", "friends", "buddy", "pal", "mate", "homie", "gang", "crew"]),
        ("client", ["client", "clients", "customer", "vendor", "investor", "investors"]),
        ("team", ["team", "colleague", "colleagues", "manager", "boss", "office", "work", "studio", "board", "project", "site"]),
    ]

    /// Pulls finished hashtags out of a typed name: "Amma #family " gives ("Amma", ["family"]).
    /// One still being typed ("Amma #fa") stays in the name and comes back as `typing` until a space,
    /// or `final` (Return), finishes it.
    static func hashtags(in text: String, final: Bool = false) -> (name: String, tags: [String], typing: String?) {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let open = !final && !text.hasSuffix(" ")
        var name: [String] = [], tags: [String] = [], typing: String?
        for (i, w) in words.enumerated() {
            guard w.hasPrefix("#"), w.count > 1 else { name.append(w); continue }
            if open && i == words.count - 1 { typing = String(w.dropFirst()); name.append(w) }
            else { tags.append(String(w.dropFirst())) }
        }
        if typing == nil, open, text.hasSuffix("#") { typing = "" }
        return tags.isEmpty ? (text, [], typing) : (name.joined(separator: " "), tags, typing)
    }

    /// The tag a Focus asked Skies to show, if any.
    static var focused: String? { UserDefaults.skies.string(forKey: "focus.tag") }

    /// The calendar plans with these people go to: their shared tag's, when they share one that has a calendar.
    static func calendar(for people: [Person]) -> String? {
        let ids = people.map { Set($0.tagList) }.reduce(nil as Set<String>?) { shared, t in shared?.intersection(t) ?? t } ?? []
        return all.first { ids.contains($0.id) && $0.calendarID != nil }?.calendarID
    }
}

extension Person {
    var tagList: [String] { tags ?? [] }
    /// Their tags in the order chosen, skipping any since deleted.
    var tagObjects: [PersonTag] { tagList.compactMap(Tags.named) }

    func has(_ tag: String) -> Bool { tagList.contains(tag) }

    /// Adds or removes a tag. The tags now say work or personal, and the hours follow unless they were customised.
    mutating func toggleTag(_ id: String) {
        let old = relation
        tags = has(id) ? tagList.filter { $0 != id } : tagList + [id]
        kind = nil
        follow(from: old)
    }

    /// Moves finished hashtags typed into the name onto the person, making new tags as needed.
    mutating func takeHashtags(final: Bool = false) {
        let r = Tags.hashtags(in: label, final: final)
        guard !r.tags.isEmpty else { return }
        label = r.name
        var made: [PersonTag] = []
        for word in r.tags {
            let t = Tags.match(word) ?? made.first { $0.name.lowercased() == word.lowercased() } ?? {
                let n = Tags.make(word)
                made.append(n)
                return n
            }()
            if !has(t.id) { toggleTag(t.id) }
        }
        if !made.isEmpty { Tags.save(Tags.all + made) }
    }
}

/// A small dot per tag, in the tag's colour.
struct TagDots: View {
    let person: Person
    var size: CGFloat = 7
    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(person.tagObjects.prefix(3)) { t in
                Circle().fill(Color(red: t.rgb.x / 255, green: t.rgb.y / 255, blue: t.rgb.z / 255))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
            }
        }
        .accessibilityLabel(person.tagObjects.map(\.name).joined(separator: ", "))
    }
}

// MARK: - App Intents

struct TagEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tag"
    static let defaultQuery = TagQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ t: PersonTag) { (id, name) = (t.id, t.name) }
}

struct TagQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TagEntity] {
        Tags.reload()
        return Tags.all.filter { identifiers.contains($0.id) }.map(TagEntity.init)
    }

    func suggestedEntities() async throws -> [TagEntity] {
        Tags.reload()
        return Tags.all.map(TagEntity.init)
    }
}
