import SwiftUI
import MapKit

struct PeopleSheet: View {
    @Bindable var people: People
    let model: Scrubber
    let holidays: Holidays
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("coached") private var coached = true

    var body: some View {
        NavigationStack {
            List {
                ForEach(people.list) { p in
                    NavigationLink {
                        PersonDetail(people: people, model: model, holidays: holidays, id: p.id) { dismiss() }
                    } label: { PersonLabel(person: p) }
                        .deleteDisabled(p.isHome)
                }
                .onMove { people.list.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { people.list.remove(atOffsets: $0) }

                NavigationLink {
                    CitySearch { place in
                        var p = Person(place: place)
                        p.applyPreset(p.relation)
                        people.list.append(p)
                    }
                } label: {
                    Label("Add a city", systemImage: "plus.circle.fill")
                }

                Section {
                    Button("Run setup again", systemImage: "sparkles") {
                        coached = false
                        onboarded = false
                    }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
    }
}

private struct PersonLabel: View {
    let person: Person
    var body: some View {
        HStack(spacing: 12) {
        Avatar(person: person, size: 34)
        VStack(alignment: .leading, spacing: 2) {
            Text(person.city).font(.body.weight(.semibold))
            Text([person.label, hoursText(person), person.tz.localizedName(for: .generic, locale: .current) ?? person.tzID]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
        }
    }
}

func hourText(_ h: Double) -> String {
    let h = (h.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
    let hh = Int(h), mm = Int(((h - Double(hh)) * 60).rounded()) % 60
    return mm == 0 ? "\(h12(hh)) \(ampm(hh))" : "\(h12(hh)):\(String(format: "%02d", mm)) \(ampm(hh))"
}

private func hoursText(_ p: Person) -> String { "\(hourText(p.start))–\(hourText(p.end))" }

struct PersonEditor: View {
    @Binding var person: Person
    @State private var pickingContact = false
    private let halfHours = stride(from: 0.0, through: 24, by: 0.5).map { $0 }

    var body: some View {
        Form {
            Section {
                TextField("Who's there? (e.g. Design team, Mom)", text: $person.label)
                    .onChange(of: person.label) { old, _ in
                        if person.kind == nil { person.follow(from: .infer(old, isHome: person.isHome)) }
                    }
                Picker("Relationship", selection: Binding(
                    get: { person.relation },
                    set: { new in
                        let old = person.relation
                        person.kind = new
                        person.follow(from: old)
                    })) {
                    ForEach(Person.Kind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                NavigationLink {
                    CitySearch { place in
                        person.city = place.city
                        person.tzID = place.tz.identifier
                        person.lat = place.coord.latitude
                        person.lon = place.coord.longitude
                        person.region = place.region
                    }
                } label: {
                    LabeledContent("City", value: person.city)
                }
            } footer: {
                Text(person.tz.localizedName(for: .generic, locale: .current) ?? person.tzID)
            }

            Section {
                if let c = person.contact {
                    HStack(spacing: 12) {
                        Avatar(person: person, size: 36)
                        Text(c.name)
                        Spacer()
                        Button("Unlink", role: .destructive) { person.contact = nil }
                    }
                } else {
                    Button { pickingContact = true } label: {
                        Label("Link a contact", systemImage: "person.crop.circle.badge.plus")
                    }
                    .background(ContactPicker(isPresented: $pickingContact) { c in
                        let contact = Person.Contact(c)
                        person.contact = contact
                        if person.label.isEmpty { person.label = contact.firstName }
                        if person.region == nil { person.region = contactRegion(c) }
                    })
                }
            } header: {
                Text("Contact")
            } footer: {
                Text("Shows their photo, adds Call, Message and FaceTime, and remembers their birthday.")
            }

            Section {
                Picker("From", selection: $person.start) {
                    ForEach(halfHours.dropLast(), id: \.self) { Text(hourText($0)).tag($0) }
                }
                Picker("Until", selection: $person.end) {
                    ForEach(halfHours.dropFirst(), id: \.self) { Text($0 == 24 ? "Midnight" : hourText($0)).tag($0) }
                }
                DayPicker(days: $person.days)
            } header: {
                Text("Free to talk")
            } footer: {
                Text("The overlap only counts times inside these hours, on these days.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(person.label.isEmpty ? person.city : person.label)
    }
}

private struct DayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let d = (i + Calendar.current.firstWeekday - 1) % 7
                let on = days.contains(d)
                Button {
                    if on { days.remove(d) } else { days.insert(d) }
                } label: {
                    Text(Calendar.current.veryShortStandaloneWeekdaySymbols[d])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[d])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// Apple Maps autocomplete, the way Weather's city search works: suggestions as you type (partials and
/// misspellings included), resolved to a real place, and so its own time zone, only when you pick one.
@MainActor @Observable final class PlaceCompleter: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var offline = false
    var query = "" {
        didSet {
            completer.queryFragment = query
            if query.trimmingCharacters(in: .whitespaces).isEmpty { results = [] }
        }
    }
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.delegate = self
    }

    // MapKit calls the completer's delegate on the main thread.
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
        offline = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        offline = (error as? MKError)?.code == .serverFailure || (error as NSError).domain == NSURLErrorDomain
    }
}

struct CitySearch: View {
    let onPick: (Place) -> Void
    @State private var places = PlaceCompleter()
    @State private var resolving: String?
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(places.results, id: \.self) { c in
                Button { Task { await pick(c) } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).foregroundStyle(.primary)
                            if !c.subtitle.isEmpty { Text(c.subtitle).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if resolving == c.title + c.subtitle { ProgressView() }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(resolving != nil)
            }
        }
        .overlay {
            if places.offline { ContentUnavailableView("Can't reach Apple Maps", systemImage: "wifi.slash") }
            else if places.results.isEmpty && !places.query.isEmpty && resolving == nil { ContentUnavailableView.search(text: places.query) }
        }
        .searchable(text: $places.query, prompt: "Any city or town")
        .onSubmit(of: .search) { Task { await pickBestMatch() } }
        .onChange(of: places.query) { problem = nil }
        .navigationTitle("Add a city")
    }

    private func pick(_ c: MKLocalSearchCompletion) async {
        resolving = c.title + c.subtitle
        defer { resolving = nil }
        let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first { $0.timeZone != nil }
        use(item, asked: c.title)
    }

    /// Return on a full name ("Vizag", "Vishakhapatnam") goes straight to the best match.
    private func pickBestMatch() async {
        let q = places.query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        resolving = q
        defer { resolving = nil }
        use(await findPlace(q), asked: q)
    }

    private func use(_ item: MKMapItem?, asked: String) {
        guard let item, let place = Place(item) else {
            problem = "Couldn't find a time zone for \u{201C}\(asked)\u{201D}. Try the nearest town or city."
            return
        }
        onPick(place)
        dismiss()
    }
}

/// A resolved Apple Maps place: the city's name, its own time zone, where it is, and its country.
struct Place {
    let city: String, tz: TimeZone, coord: CLLocationCoordinate2D, region: String?

    init?(_ item: MKMapItem) {
        guard let tz = item.timeZone else { return nil }
        (city, self.tz, coord) = (cityName(item), tz, item.location.coordinate)
        region = item.addressRepresentations?.region?.identifier
    }
}

extension Person {
    init(place: Place, label: String = "", isHome: Bool = false) {
        self.init(city: place.city, label: label, tzID: place.tz.identifier, lat: place.coord.latitude,
                  lon: place.coord.longitude, isHome: isHome, region: place.region)
    }
}

func cityName(_ item: MKMapItem) -> String { item.addressRepresentations?.cityName ?? item.name ?? "Unknown" }

/// The first Apple Maps place for a query that knows its time zone.
func findPlace(_ query: String) async -> MKMapItem? {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.resultTypes = .address
    return try? await MKLocalSearch(request: request).start().mapItems.first { $0.timeZone != nil }
}

extension People {
    /// People saved before Skies knew countries get theirs once, from Apple Maps, for local weekends and holidays.
    func fillRegions() async {
        for p in list where p.region == nil {
            guard let item = await findPlace(p.city), item.timeZone?.identifier == p.tzID,
                  let region = item.addressRepresentations?.region?.identifier,
                  let i = list.firstIndex(where: { $0.id == p.id }) else { continue }
            list[i].region = region
        }
    }
}
