import Foundation

// The model the app and its widgets share: plain Foundation, no UI frameworks.

func nowMinutes(_ d: Date = .now) -> Double { d.timeIntervalSince1970 / 60 }

extension UserDefaults {
    /// iPhone App Groups must start with "group." and be in the profile. A free team can't register one on the Mac,
    /// but the Mac accepts a group named after the team without registration.
    #if os(macOS)
    static let groupID = "P6SP5RHNLV.com.btstd.skies"
    #else
    static let groupID = "group.com.btstd.skies"
    #endif
    /// Where the Mac kept people before its group worked: a store only the app itself could see.
    static let oldMacGroupID = "group.com.btstd.skies"
    /// Shared with the widgets through the App Group; the app's own defaults if the group isn't available.
    nonisolated(unsafe) static let skies = UserDefaults(suiteName: groupID) ?? .standard
}

extension Person {
    static let storeKey = "people.v1"

    /// Your saved people, as the widgets read them (the app goes through `People`).
    static func saved() -> [Person] {
        UserDefaults.skies.data(forKey: storeKey).flatMap { try? JSONDecoder().decode([Person].self, from: $0) } ?? defaults
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Person.Contact {
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
}

/// One way to reach someone, on one number or address: what a Phone favourite is.
struct Channel: Codable, Hashable {
    enum Method: String, Codable, CaseIterable {
        case call, facetime, facetimeAudio, message, whatsapp, email

        var title: String {
            switch self {
            case .call: "Call"
            case .facetime: "FaceTime"
            case .facetimeAudio: "FaceTime Audio"
            case .message: "Message"
            case .whatsapp: "WhatsApp"
            case .email: "Mail"
            }
        }

        var icon: String {
            switch self {
            case .call: "phone.fill"
            case .facetime: "video.fill"
            case .facetimeAudio: "waveform"
            case .message: "message.fill"
            case .whatsapp: "bubble.left.and.text.bubble.right.fill"
            case .email: "envelope.fill"
            }
        }

        /// The caption under its button, short enough for five in a row.
        var short: String {
            switch self {
            case .facetime: "Video"
            case .facetimeAudio: "Audio"
            default: title
            }
        }

        static let forNumbers: [Method] = [.call, .facetime, .facetimeAudio, .message, .whatsapp]
        static let forEmail: [Method] = [.facetime, .facetimeAudio, .email]
    }

    var method: Method
    var value: String

    var url: URL? {
        let dial = value.filter { "+0123456789".contains($0) }
        let target = value.contains("@") ? value : dial
        return switch method {
        case .call: URL(string: "tel:\(dial)")
        case .facetime: URL(string: "facetime:\(target)")
        case .facetimeAudio: URL(string: "facetime-audio:\(target)")
        case .message: URL(string: "sms:\(target)")
        // ponytail: WhatsApp has no public link that starts a call, so this opens the chat; it also needs the
        // full international number, so numbers saved without a country code won't resolve.
        case .whatsapp: URL(string: "https://wa.me/\(dial.filter(\.isNumber))")
        case .email: URL(string: "mailto:\(value)")
        }
    }
}

extension Person.Contact {
    /// The pinned favourite, or the obvious default: call their first number, else FaceTime their email.
    var preferred: Channel? {
        favourite ?? numbers.first.map { Channel(method: .call, value: $0.value) }
            ?? email.map { Channel(method: .facetime, value: $0) }
    }

    func label(for value: String) -> String { numbers.first { $0.value == value }?.label ?? "email" }
}

