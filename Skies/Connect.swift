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
        organization = org.nonEmpty
    }

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
                Text(c.initials).font(.sf(size * 0.4, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.22))
            } else {
                Image(systemName: person.isHome ? "location.fill" : person.relation.symbol)
                    .font(.sf(size * 0.36, .semibold)).foregroundStyle(.white.opacity(0.9))
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

/// Every way to reach them, laid out like Phone favourites: each number with its call, video, audio, message
/// and WhatsApp buttons, and the pinned favourite as one big button on top.
struct ReachModule: View {
    @Binding var contact: Person.Contact
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Module(title: "Reach \(contact.firstName)", icon: "phone.fill") {
            VStack(alignment: .leading, spacing: 14) {
                if let fav = contact.preferred {
                    Button { go(fav) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: fav.method.icon).sf(20, .semibold).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fav.method.title).sf(17, .semibold)
                                Text("\(contact.label(for: fav.value)) · \(fav.value)").sf(13, .regular).opacity(0.75)
                            }
                            Spacer()
                            if contact.favourite != nil { Image(systemName: "star.fill").foregroundStyle(Color.sun) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 60)
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
                    .sf(12, .regular).opacity(0.6)
            }
        }
    }

    private func row(label: String, value: String, methods: [Channel.Method]) -> some View {
        let line = typeSize.row(spacing: 8)
        return VStack(alignment: .leading, spacing: 8) {
            line {
                Text(label.capitalized).sf(13, .medium).opacity(0.6)
                Text(value).sf(15, .regular).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                ForEach(methods, id: \.self) { m in
                    let channel = Channel(method: m, value: value)
                    Button { go(channel) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: m.icon).sf(15, .semibold)
                            // Like Phone's contact card: icons only at accessibility sizes; touch and hold shows the name large.
                            if !typeSize.isAccessibilitySize {
                                Text(m.short).sf(10, .medium).opacity(0.75).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(alignment: .topTrailing) {
                                if contact.favourite == channel {
                                    Image(systemName: "star.fill").sf(9, .bold).foregroundStyle(Color.sun).padding(5)
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
                    .accessibilityShowsLargeContentViewer { Label(m.title, systemImage: m.icon) }
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
