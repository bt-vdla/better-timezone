import SwiftUI
import MapKit
import Contacts

/// First run: welcome on a live sky, where you are, who you talk to, what to call them.
/// Learning the gestures happens afterwards, on the real screen (SkiesView's coaching).
struct Onboarding: View {
    let people: People
    let done: () -> Void

    @State private var step = 0
    @State private var forward = true
    @State private var you = Onboarding.guessYou()
    @State private var others: [Person] = []
    @State private var search: Search?
    /// A contact with no usable address waits here while you search for their city.
    @State private var pendingContact: Person.Contact?
    @State private var pickingContact = false
    @State private var began = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Search: Identifiable { case you, add; var id: Self { self } }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : step == 0 ? nil : 1.0 / 30)) { ctx in
                SkyBackground(person: you, minutes: skyMinutes(ctx.date),
                              time: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate, flare: 1).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if step > 0 {
                        Button("Skip", action: done).font(sf(15, .medium)).buttonStyle(.plain).opacity(0.8)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: whereAreYou
                    case 2: whoDoYouTalkTo
                    default: names
                    }
                }
                .id(step)
                .transition(stepTransition)
                .frame(maxHeight: .infinity)

                HStack(spacing: 12) {
                    if step > 0 {
                        Button { go(-1) } label: {
                            Image(systemName: "chevron.left").font(sf(17, .semibold)).frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel("Back")
                    }
                    Button(action: next) {
                        Text(primaryTitle).font(sf(17, .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 520)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $search) { kind in
            NavigationStack {
                CitySearch { place in
                    var p = Person(place: place, label: kind == .you ? "You" : pendingContact?.firstName ?? "", isHome: kind == .you)
                    p.contact = kind == .you ? nil : pendingContact
                    if kind == .you { you = p } else { add(p) }
                    pendingContact = nil
                }
            }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 460)
            #endif
        }
        .background(ContactPicker(isPresented: $pickingContact) { contact in Task { await addContact(contact) } })
        .task { await placeYou() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Skies").font(sf(64, .semibold)).tracking(-1.5)
            Text("See everyone's day at once.").font(sf(22, .regular)).opacity(0.9)
            Spacer()
            Text("A sky for every city you care about: real sunrises, real time zones, and the hours you can all talk.")
                .font(sf(15, .regular)).multilineTextAlignment(.center).opacity(0.8)
                .padding(.horizontal, 32).padding(.bottom, 24)
        }
        .skyLegible()
    }

    private var whereAreYou: some View {
        VStack(spacing: 20) {
            title("Where are you?", "Your sky sits at the top. Everyone else is measured from it.")
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(you.city).font(sf(28, .semibold))
                    Text(you.tz.localizedName(for: .generic, locale: .current) ?? you.tzID).font(sf(15, .regular)).opacity(0.75)
                }
                Spacer()
                Button("Change") { search = .you }
                    .font(sf(15, .semibold)).padding(.horizontal, 16).frame(height: 36)
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .padding(20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var whoDoYouTalkTo: some View {
        VStack(spacing: 18) {
            title("Who do you talk to?", "Add the cities your people are in. You can change these any time.")
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(others) { p in
                        MiniBand(person: p) { others.removeAll { $0.id == p.id } }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? .easeOutStrong(0.2) : .spring(response: 0.4, dampingFraction: 1), value: others.map(\.id))
                .padding(.horizontal, 24)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(Onboarding.suggestions.filter { s in !others.contains { $0.tzID == s.tzID && $0.city == s.city } && s.tzID != you.tzID }) { s in
                        Button { add(s) } label: {
                            Label(s.city, systemImage: "plus").font(sf(15, .medium)).frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                }
                .padding(.horizontal, 24).padding(.top, 8)

                HStack(spacing: 10) {
                    Button { search = .add } label: {
                        Label("Search", systemImage: "magnifyingglass").font(sf(15, .semibold)).frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    Button { pickingContact = true } label: {
                        Label("From Contacts", systemImage: "person.crop.circle").font(sf(15, .semibold)).frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .padding(.horizontal, 24).padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var names: some View {
        VStack(spacing: 18) {
            title("What do you call them?", "A name and the hours they're free to talk.")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($others) { $p in NameCard(person: $p) }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Text(t).font(sf(32, .semibold)).tracking(-0.5)
            Text(sub).font(sf(16, .regular)).opacity(0.85)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28).padding(.top, 12)
        .skyLegible()
    }

    // MARK: Flow

    private var primaryTitle: String {
        switch step {
        case 0: "Get started"
        case 1: "This is me"
        case 2: others.isEmpty ? "Just me for now" : "Continue"
        default: "Start"
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(_ d: Int) {
        forward = d > 0
        withAnimation(.easeOutStrong(0.35)) { step += d }
    }

    private func next() {
        if step == 3 || (step == 2 && others.isEmpty) { finish() } else { go(1) }
    }

    private func finish() {
        people.picked = []
        people.list = [you] + others
        done()
    }

    private func add(_ p: Person) {
        var p = p
        p.id = UUID()
        p.applyPreset(p.relation)
        others.append(p)
    }

    /// Welcome runs a whole day in 8 seconds; after that the sky is live.
    private func skyMinutes(_ d: Date) -> Double {
        guard step == 0, !reduceMotion else { return nowMinutes(d) }
        let t = d.timeIntervalSince(began).truncatingRemainder(dividingBy: 8) / 8
        return dayStart(you.tz, nowMinutes(d)) + t * 1440
    }

    // MARK: Places

    /// Guess "you" from the device's time zone (no location permission), then ask Maps for real coordinates.
    private static func guessYou() -> Person {
        let tz = TimeZone.current
        let city = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Home"
        // ponytail: rough placeholder until Maps answers: longitude from the UTC offset, a mid latitude.
        return Person(city: city, label: "You", tzID: tz.identifier, lat: 30,
                      lon: Double(tz.secondsFromGMT()) / 240, isHome: true)
    }

    private func placeYou() async {
        guard let item = await findPlace(you.city), item.timeZone?.identifier == you.tzID else { return }
        you.lat = item.location.coordinate.latitude
        you.lon = item.location.coordinate.longitude
        you.region = item.addressRepresentations?.region?.identifier
    }

    /// A contact's first address picks their city; with no address, you search for it and the contact rides along.
    private func addContact(_ c: CNContact) async {
        let contact = Person.Contact(c)
        let address = c.isKeyAvailable(CNContactPostalAddressesKey) ? c.postalAddresses.first?.value : nil
        guard let address,
              let item = await findPlace(CNPostalAddressFormatter.string(from: address, style: .mailingAddress)),
              let place = Place(item) else {
            pendingContact = contact
            search = .add
            return
        }
        var p = Person(place: place, label: contact.firstName)
        p.region = p.region ?? contactRegion(c)
        p.contact = contact
        add(p)
    }

    static let suggestions: [Person] = [
        Person(city: "London", label: "", tzID: "Europe/London", lat: 51.507, lon: -0.128),
        Person(city: "New York", label: "", tzID: "America/New_York", lat: 40.713, lon: -74.006),
        Person(city: "San Francisco", label: "", tzID: "America/Los_Angeles", lat: 37.775, lon: -122.419),
        Person(city: "Dubai", label: "", tzID: "Asia/Dubai", lat: 25.205, lon: 55.271),
        Person(city: "Bengaluru", label: "", tzID: "Asia/Kolkata", lat: 12.972, lon: 77.594),
        Person(city: "Singapore", label: "", tzID: "Asia/Singapore", lat: 1.352, lon: 103.820),
        Person(city: "Tokyo", label: "", tzID: "Asia/Tokyo", lat: 35.676, lon: 139.650),
        Person(city: "Sydney", label: "", tzID: "Australia/Sydney", lat: -33.869, lon: 151.209),
        Person(city: "Berlin", label: "", tzID: "Europe/Berlin", lat: 52.520, lon: 13.405),
        Person(city: "São Paulo", label: "", tzID: "America/Sao_Paulo", lat: -23.551, lon: -46.633),
    ]
}

/// A small live sky for a city being added.
private struct MiniBand: View {
    let person: Person
    let remove: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let m = nowMinutes(ctx.date), l = Local(person.tz, m)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.city).font(sf(18, .semibold))
                    if !person.label.isEmpty { Text(person.label).font(sf(13, .medium)).opacity(0.8) }
                }
                Spacer()
                Text("\(clock(l)) \(ampm(l.h))").font(sf(22, .light)).monospacedDigit()
                Button(action: remove) {
                    Image(systemName: "xmark").font(sf(12, .bold)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Remove \(person.city)")
            }
            .skyLegible()
            .padding(.horizontal, 16).frame(height: 64)
            .background { SkyBackground(person: person, minutes: m) }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

/// Name and hours for one city.
private struct NameCard: View {
    @Binding var person: Person
    private static let names = ["Team", "Family", "Client", "Friends", "Partner"]

    enum Preset: String, CaseIterable { case office = "Office hours", awake = "Awake hours" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(person.city).font(sf(15, .semibold)).opacity(0.75)
            TextField("Who's in \(person.city)?", text: $person.label)
                .font(sf(22, .semibold))
                .textFieldStyle(.plain)
                .onChange(of: person.label) { old, _ in person.follow(from: .infer(old, isHome: false)) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.names, id: \.self) { n in
                        Button(n) { person.label = n }
                            .font(sf(14, .medium)).padding(.horizontal, 12).frame(height: 32)
                            .buttonStyle(.plain)
                            .glassEffect(person.label == n ? .regular.tint(.white.opacity(0.3)).interactive() : .regular.interactive(), in: Capsule())
                    }
                }
            }
            Picker("Hours", selection: Binding(
                get: { person.start == 9 && person.end == 18 ? Preset.office : .awake },
                set: { p in
                    switch p {
                    case .office: person.start = 9; person.end = 18; person.days = [1, 2, 3, 4, 5]
                    case .awake: person.start = 8; person.end = 22; person.days = Set(0..<7)
                    }
                })) {
                ForEach(Preset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("\(hourText(person.start))–\(hourText(person.end)), \(daysText(person.days))")
                .font(sf(13, .regular)).opacity(0.7)
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }
}


func daysText(_ days: Set<Int>) -> String {
    switch days {
    case Set(0..<7): "every day"
    case [1, 2, 3, 4, 5]: "Monday to Friday"
    case []: "no days"
    default: (0..<7).filter(days.contains).map { Calendar.current.shortWeekdaySymbols[$0] }.joined(separator: ", ")
    }
}
