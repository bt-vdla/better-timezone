import SwiftUI
import Contacts
import ContactsUI

extension Person.Contact {
    /// Copies what the picker handed back. Picked contacts can arrive without some keys, so each one is checked.
    init(_ c: CNContact) {
        func has(_ key: String) -> Bool { c.isKeyAvailable(key) }
        id = c.identifier
        let given = has(CNContactGivenNameKey) ? c.givenName : ""
        let family = has(CNContactFamilyNameKey) ? c.familyName : ""
        let org = has(CNContactOrganizationNameKey) ? c.organizationName : ""
        name = [given, family].filter { !$0.isEmpty }.joined(separator: " ").nonEmpty ?? org.nonEmpty ?? "Contact"
        phones = has(CNContactPhoneNumbersKey) ? c.phoneNumbers.map {
            Number(label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? CNLabelPhoneNumberMobile),
                   value: $0.value.stringValue)
        } : nil
        email = has(CNContactEmailAddressesKey) ? c.emailAddresses.first.map { $0.value as String } : nil
        birthday = has(CNContactBirthdayKey) ? c.birthday : nil
        photo = has(CNContactThumbnailImageDataKey) ? c.thumbnailImageData : nil
    }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Where a picked contact lives: the country on their first postal address.
func contactRegion(_ c: CNContact) -> String? {
    guard c.isKeyAvailable(CNContactPostalAddressesKey) else { return nil }
    return c.postalAddresses.first?.value.isoCountryCode.uppercased().nonEmpty
}

// MARK: - Face

/// Their contact photo, or their initials when the card has no photo. Without a contact it shows what they are
/// to you (you, work, personal), so every row keeps the same leading circle and the names line up.
struct Avatar: View {
    let person: Person
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = person.contact?.photo, let image = platformImage(data) {
                image.resizable().scaledToFill()
            } else if let c = person.contact {
                Text(c.initials).font(sf(size * 0.4, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.22))
            } else {
                Image(systemName: person.isHome ? "location.fill" : person.relation.symbol)
                    .font(sf(size * 0.36, .semibold)).foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.14))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(person.contact == nil ? 0.25 : 0.5), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private func platformImage(_ data: Data) -> Image? {
        #if os(iOS)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

// MARK: - Reach them

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

/// Every way to reach them, laid out like Phone favourites: each number with its call, video, audio, message
/// and WhatsApp buttons, and the pinned favourite as one big button on top.
struct ReachModule: View {
    @Binding var contact: Person.Contact
    @Environment(\.openURL) private var openURL

    var body: some View {
        Module(title: "Reach \(contact.firstName)", icon: "phone.fill") {
            VStack(alignment: .leading, spacing: 14) {
                if let fav = contact.preferred {
                    Button { go(fav) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: fav.method.icon).font(sf(20, .semibold)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fav.method.title).font(sf(17, .semibold))
                                Text("\(contact.label(for: fav.value)) · \(fav.value)").font(sf(13, .regular)).opacity(0.75)
                            }
                            Spacer()
                            if contact.favourite != nil { Image(systemName: "star.fill").foregroundStyle(Color.sun) }
                        }
                        .padding(.horizontal, 16).frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.mint.opacity(0.35)).interactive(), in: RoundedRectangle(cornerRadius: 18))
                }
                ForEach(contact.numbers, id: \.self) { n in
                    row(label: n.label, value: n.value, methods: Channel.Method.forNumbers)
                }
                if let email = contact.email {
                    row(label: "email", value: email, methods: Channel.Method.forEmail)
                }
                Text("Touch and hold any of these to make it the favourite.")
                    .font(sf(12, .regular)).opacity(0.6)
            }
        }
    }

    private func row(label: String, value: String, methods: [Channel.Method]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label.capitalized).font(sf(13, .medium)).opacity(0.6)
                Text(value).font(sf(15, .regular)).lineLimit(1)
            }
            HStack(spacing: 8) {
                ForEach(methods, id: \.self) { m in
                    let channel = Channel(method: m, value: value)
                    Button { go(channel) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: m.icon).font(sf(15, .semibold))
                            Text(m.short).font(sf(10, .medium)).opacity(0.75).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                            .overlay(alignment: .topTrailing) {
                                if contact.favourite == channel {
                                    Image(systemName: "star.fill").font(sf(9, .bold)).foregroundStyle(Color.sun).padding(5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                    .contextMenu {
                        if contact.favourite == channel {
                            Button("Remove favourite", systemImage: "star.slash") { contact.favourite = nil }
                        } else {
                            Button("Make favourite", systemImage: "star") { contact.favourite = channel }
                        }
                    }
                    .accessibilityLabel("\(m.title), \(label)")
                    .accessibilityAction(named: "Make favourite") { contact.favourite = channel }
                }
            }
        }
    }

    private func go(_ c: Channel) { if let url = c.url { openURL(url) } }
}

// MARK: - Pick a contact

#if os(iOS)
/// The system contact picker runs out of process, so it needs no Contacts permission.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        init(parent: ContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPick(contact)
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { parent.isPresented = false }
    }
}
#else
/// The Mac contact picker is a popover, anchored to whatever view this sits behind.
struct ContactPicker: NSViewRepresentable {
    @Binding var isPresented: Bool
    let onPick: (CNContact) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.parent = self
        guard isPresented, context.coordinator.picker == nil else { return }
        let picker = CNContactPicker()
        picker.delegate = context.coordinator
        context.coordinator.picker = picker
        DispatchQueue.main.async { picker.showRelative(to: view.bounds, of: view, preferredEdge: .maxY) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        var parent: ContactPicker
        var picker: CNContactPicker?
        init(parent: ContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
            parent.onPick(contact)
            picker.close()
        }

        func contactPickerDidClose(_ picker: CNContactPicker) {
            self.picker = nil
            parent.isPresented = false
        }
    }
}
#endif
