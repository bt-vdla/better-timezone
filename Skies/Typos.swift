import Foundation
import Synchronization

/// Autocorrect for Ask: a noisy-channel corrector. Every word Skies doesn't know gets its likeliest intended words
/// (keyboard-aware edit distance over everything Skies understands), and Ask itself chooses between the readings:
/// the one it understands best wins, so a correction only happens when it makes sense of the question.
enum Typos {
    /// The words questions are made of, beyond places, codes, people and tags.
    static let grammar: [String] = """
        to in into at for from and convert what whats time is it its are when can could should shall will would i we \
        my me mine here local your speak talk call meet chat ring reach catch see phone facetime video up with next best \
        awake asleep sleeping free available around busy working work online now today tonight tomorrow noon midnight \
        am pm hour hours hr hrs min mins minute minutes ago later ahead back before half an one everyone everybody all \
        them people show dst daylight saving savings clock clocks change changes summer winter standard forward observe \
        does do did there go spring fall switch have use on after once ends end starts start begins over relation \
        relative compared versus vs gap difference between ahead behind sunday monday tuesday wednesday thursday friday saturday sun mon tue wed thu fri sat
        """.split(whereSeparator: \.isWhitespace).map(String.init)

    struct Word { let text: String; let prior: Double }

    /// Places and codes: built once. Multi-word names count word by word ("new", "york"), and run together ("newyork").
    private static let world: (words: [Word], known: Set<String>) = {
        var words: [String: Double] = [:]
        func add(_ w: String, _ prior: Double) { if w.count >= 2 { words[w] = min(words[w] ?? .infinity, prior) } }
        for g in grammar { add(g, 0) }
        // Codes pull weakest: three letters are easy to land on by accident ("toi" is a slip of "to", not Réunion).
        let codes = Set(Airports.byCode.keys.map { $0.lowercased() })
        var runTogether = Set<String>()
        for key in Places.keys {
            let parts = key.split(separator: " ").map(String.init)
            for p in parts { add(p, codes.contains(p) ? 0.5 : 0.15) }
            if parts.count > 1 { add(parts.joined(), 0.2); runTogether.insert(parts.joined()) }
        }
        for code in codes where !Airports.words.contains(code) { add(code, 0.5) }
        // Sorted, so equal guesses always come out in the same order.
        let list = words.map { Word(text: $0.key, prior: $0.value) }.sorted { ($0.prior, $0.text) < ($1.prior, $1.text) }
        return (list, Set(words.keys).subtracting(runTogether).union(Airports.words))
    }()

    /// Your people and tags, which change: words with the strongest pull after grammar.
    private static func yours(_ people: [Person]) -> [Word] {
        let texts = people.flatMap { [$0.name, $0.city, $0.code, $0.contact?.firstName ?? ""] } + Tags.all.map(\.name)
        return Set(texts.flatMap { $0.lowercased().split(separator: " ").map(String.init) }).filter { $0.count >= 2 }
            .map { Word(text: $0, prior: 0.05) }
    }

    /// Words worth correcting: letters only, two or more of them, and not something Skies already knows.
    static func unknown(_ token: String, people: [Word]) -> Bool {
        token.count >= 2 && token.allSatisfy(\.isLetter) && !world.known.contains(token) && !people.contains { $0.text == token }
    }

    /// The likeliest intended words for a typo, cheapest first, with their cost.
    /// Guesses already worked out: a typo stays the same while the next words are typed.
    private static let memo = Mutex<[String: [(String, Double)]]>([:])

    static func candidates(_ token: String, people: [Word], limit: Int = 5) -> [(String, Double)] {
        let key = token + "|" + people.map(\.text).joined(separator: ",")
        if let hit = memo.withLock({ $0[key] }) { return hit }
        let result = guess(token, people: people, limit: limit)
        memo.withLock { if $0.count > 500 { $0.removeAll() }; $0[key] = result }
        return result
    }

    private static func guess(_ token: String, people: [Word], limit: Int) -> [(String, Double)] {
        // Short words get one small slip at most: guessing further on three letters is a coin toss.
        let budget = token.count <= 3 ? 0.5 : token.count <= 5 ? 1.3 : 1.9
        var found: [(String, Double)] = []
        // A three-letter word is a step away from dozens of airport codes; guessing one is a coin toss ("gyt" isn't
        // George Town's GGT), so short words are never corrected into codes.
        let codesAllowed = token.count >= 4
        for w in people + world.words where abs(w.text.count - token.count) <= 2 && (codesAllowed || w.prior < 0.5) {
            let d = distance(token, w.text, cap: budget)
            if d <= budget { found.append((w.text, d + w.prior)) }
        }
        // A run-together multi-word name reads back with its space ("newyork" → "new york").
        return found.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.prefix(limit).map { (Places.spaced[$0.0] ?? $0.0, $0.1) }
    }

    // MARK: Keyboard-aware edit distance

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let near: [Character: Set<Character>] = {
        var map: [Character: Set<Character>] = [:]
        let grid = rows.map(Array.init)
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() {
                var n = Set<Character>()
                for dr in -1...1 { for dc in -1...1 where !(dr == 0 && dc == 0) {
                    let rr = r + dr, cc = c + dc
                    if grid.indices.contains(rr), grid[rr].indices.contains(cc) { n.insert(grid[rr][cc]) }
                } }
                map[ch] = n
            }
        }
        return map
    }()

    /// Damerau–Levenshtein with costs shaped like real typing: a neighbouring key or swapped pair costs less than a
    /// random letter, a doubled or dropped repeat costs least. Gives up early past `cap`.
    static func distance(_ a: String, _ b: String, cap: Double = .infinity) -> Double {
        let s = Array(a), t = Array(b)
        if s == t { return 0 }
        var d = Array(repeating: Array(repeating: 0.0, count: t.count + 1), count: s.count + 1)
        // A doubled letter typed or dropped is the smallest slip; a dropped vowel ("whn", "tlk") the next.
        // An extra key beside its neighbour ("toi": i sits by o) is a fat-finger slip, nearly as small as a repeat.
        func extra(_ x: [Character], _ i: Int) -> Double {
            if i > 0 && x[i] == x[i - 1] { return 0.3 }
            let beside = (i > 0 && near[x[i - 1]]?.contains(x[i]) == true) || (i + 1 < x.count && near[x[i + 1]]?.contains(x[i]) == true)
            return beside ? 0.4 : 0.8
        }
        func missing(_ x: [Character], _ i: Int) -> Double { i > 0 && x[i] == x[i - 1] ? 0.3 : "aeiou".contains(x[i]) ? 0.5 : 0.8 }
        for i in 1...max(1, s.count) where i <= s.count { d[i][0] = d[i - 1][0] + extra(s, i - 1) }
        for j in 1...max(1, t.count) where j <= t.count { d[0][j] = d[0][j - 1] + missing(t, j - 1) }
        guard !s.isEmpty, !t.isEmpty else { return d[s.count][t.count] }
        for i in 1...s.count {
            var best = Double.infinity
            for j in 1...t.count {
                let sub = s[i - 1] == t[j - 1] ? 0 : near[s[i - 1]]?.contains(t[j - 1]) == true ? 0.5 : 1
                var v = min(d[i - 1][j] + extra(s, i - 1), d[i][j - 1] + missing(t, j - 1), d[i - 1][j - 1] + sub)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] { v = min(v, d[i - 2][j - 2] + 0.5) }
                d[i][j] = v
                best = min(best, v)
            }
            if best > cap { return best }
        }
        return d[s.count][t.count]
    }

    // MARK: Choosing a reading

    /// Readings of the question with typos swapped for likely words, cheapest first (the original among them).
    static func readings(_ query: String, people: [Person], max: Int = 16) -> [(text: String, cost: Double, unknown: Int)] {
        let mine = yours(people)
        let tokens = query.lowercased().split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        struct Beam { var words: [String]; var cost: Double; var unknown: Int }
        struct Option { let word: String; let cost: Double; let unknown: Int }
        var beams = [Beam(words: [], cost: 0, unknown: 0)]
        for raw in tokens {
            let token = raw.trimmingCharacters(in: .punctuationCharacters)
            var options = [Option(word: raw, cost: 0, unknown: 0)]
            if unknown(token, people: mine) {
                options = [Option(word: raw, cost: 0, unknown: 1)]
                    + candidates(token, people: mine).map { Option(word: $0.0, cost: $0.1, unknown: 0) }
            }
            var next: [Beam] = []
            for b in beams {
                for o in options { next.append(Beam(words: b.words + [o.word], cost: b.cost + o.cost, unknown: b.unknown + o.unknown)) }
            }
            beams = Array(next.sorted { ($0.cost, $0.unknown) < ($1.cost, $1.unknown) }.prefix(max * 2))
        }
        return beams.prefix(max).map { ($0.words.joined(separator: " "), $0.cost, $0.unknown) }
    }
}

extension Places {
    /// Every name and code Skies knows, for the corrector.
    static var keys: [String] { Array(spacedTable.keys) }

    /// Multi-word names by their run-together spelling: "newyork" → "new york".
    static let spaced: [String: String] = Dictionary(
        spacedTable.keys.filter { $0.contains(" ") }.map { ($0.replacingOccurrences(of: " ", with: ""), $0) },
        uniquingKeysWith: { a, _ in a })
}
