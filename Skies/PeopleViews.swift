import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
import MapKit

struct PeopleSheet: View {
    @Bindable var people: People
    let model: Scrubber
    let holidays: Holidays
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("coached") private var coached = true
    @AppStorage(ShowBy.key, store: .skies) private var showBy: ShowBy = .name

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
                    NavigationLink { TagsList(people: people) } label: { Label("Tags", systemImage: "tag") }
                }

                Section {
                    CalendarToggle()
                } footer: {
                    Text("Free times leave out your meetings. Skies reads only when you're busy, on this device.")
                }

                Section {
                    TimeFormatPicker()
                    Picker("Show people by", selection: $showBy) {
                        ForEach(ShowBy.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("What each sky is labelled with across Skies. The other two show smaller, beside it.")
                }

                Section {
                    Button("Run setup again", systemImage: "sparkles") {
                        coached = false
                        onboarded = false
                    }
                }

                Section {
                    NavigationLink { ReleaseLog() } label: { VersionLabel() }
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
    @AppStorage(ShowBy.key, store: .skies) private var showBy: ShowBy = .name
    var body: some View {
        HStack(spacing: 12) {
        Avatar(person: person, size: 34)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(person.title(showBy)).font(.body.weight(.semibold))
                TagDots(person: person)
            }
            Text(([person.name, person.code, person.city].filter { $0 != person.title(showBy) } + person.tagObjects.map(\.name) + [hoursText(person)])
                .joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
        }
    }
}

func hourText(_ h: Double) -> String {
    let h = (h.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
    let hh = Int(h), mm = Int(((h - Double(hh)) * 60).rounded()) % 60
    return mm == 0 ? hourText(hh) : hm(Local(TimeZone(identifier: "UTC")!, Double(hh * 60 + mm)))
}

private func hoursText(_ p: Person) -> String { "\(hourText(p.start))–\(hourText(p.end))" }

struct PersonEditor: View {
    @Binding var person: Person
    @State private var pickingContact = false
    private let halfHours = stride(from: 0.0, through: 24, by: 0.5).map { $0 }

    /// A notification switch; turning one on asks for permission the first time.
    private func notify(_ key: WritableKeyPath<Person.Notify, Bool>) -> Binding<Bool> {
        Binding(get: { person.notify?[keyPath: key] ?? false }, set: { on in
            var n = person.notify ?? Person.Notify()
            n[keyPath: key] = on
            person.notify = n
            if on { Task { if !(await Nudges.ask()) { var off = person.notify ?? Person.Notify(); off[keyPath: key] = false; person.notify = off } } }
        })
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, or type # to tag", text: $person.label)
                    .autocorrectionDisabled()
                    .onChange(of: person.label) { old, _ in
                        if person.kind == nil && person.tagList.isEmpty { person.follow(from: .infer(old, isHome: person.isHome)) }
                        person.takeHashtags()
                    }
                    .onSubmit { person.takeHashtags(final: true) }
                if !person.isHome {
                    TagChips(person: $person).padding(.vertical, 4)
                }
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
                LabeledContent("Short code") {
                    TextField(Airports.nearest(lat: person.lat, lon: person.lon) ?? "Code", text: Binding(
                        get: { person.codeOverride ?? "" },
                        set: { person.codeOverride = String($0.uppercased().filter(\.isLetter).prefix(4)).nonEmpty }))
                        .multilineTextAlignment(.trailing)
                        .monospaced()
                        .autocorrectionDisabled()
                }
            } footer: {
                Text("\(person.isHome ? "" : "\(person.relation.title), from \(person.tagObjects.first.map { "the \($0.name) tag" } ?? "their name"). ")\(person.tz.localizedName(for: .generic, locale: .current) ?? person.tzID). The short code shows beside their name; leave it empty to use the nearest airport.")
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

            if !person.isHome {
                Section {
                    Toggle("When they wake up", isOn: notify(\.wake))
                    if person.contact?.birthday != nil {
                        Toggle("On their birthday, their time", isOn: notify(\.birthday))
                    }
                } header: {
                    Text("Let me know")
                } footer: {
                    Text("Quiet notifications. A birthday that starts in your night waits until your 8 AM.")
                }
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
        .navigationTitle(person.name)
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
                .buttonStyle(.whole)
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
    /// Put the cursor in the search field on open (the Mac's Add a City window).
    var focused = false
    let onPick: (Place) -> Void
    @FocusState private var searching: Bool
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
                .buttonStyle(.whole)
                .disabled(resolving != nil)
            }
        }
        .overlay {
            if places.offline { ContentUnavailableView("Can't reach Apple Maps", systemImage: "wifi.slash") }
            else if places.results.isEmpty && !places.query.isEmpty && resolving == nil { ContentUnavailableView.search(text: places.query) }
        }
        .searchable(text: $places.query, prompt: "Any city or town")
        .searchFocused($searching)
        .onAppear { if focused { searching = true } }
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

/// System, 12-hour or 24-hour clocks, everywhere in Skies including widgets.
struct TimeFormatPicker: View {
    @AppStorage(TimeFormat.key, store: .skies) private var format = "system"
    var body: some View {
        Picker("Time format", selection: $format) {
            Text("System").tag("system")
            Text("12-hour").tag("12")
            Text("24-hour").tag("24")
        }
        .onChange(of: format) {
            TimeFormat.twentyFour = TimeFormat.read()
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }
}

/// "Skip my meetings": your calendar's busy times come out of every free window.
struct CalendarToggle: View {
    @State private var calendars = Calendars.shared
    var body: some View {
        Toggle(isOn: Binding(get: { calendars.on }, set: { on in Task { await calendars.turn(on) } })) {
            Label("Skip my meetings", systemImage: "calendar.badge.minus")
        }
    }
}
