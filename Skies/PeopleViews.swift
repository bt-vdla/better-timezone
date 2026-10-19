import SwiftUI
import MapKit

struct PeopleSheet: View {
    @Bindable var people: People
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach($people.list) { $p in
                    NavigationLink { PersonEditor(person: $p) } label: { PersonLabel(person: p) }
                        .deleteDisabled(p.isHome)
                }
                .onMove { people.list.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { people.list.remove(atOffsets: $0) }

                NavigationLink {
                    CitySearch { city, tz, coord in
                        people.list.append(Person(city: city, label: "", tzID: tz.identifier,
                                                  lat: coord.latitude, lon: coord.longitude))
                    }
                } label: {
                    Label("Add a city", systemImage: "plus.circle.fill")
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

struct PersonSheet: View {
    @Bindable var people: People
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let i = people.list.firstIndex(where: { $0.id == id }) {
                PersonEditor(person: $people.list[i])
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(person.city).font(.body.weight(.semibold))
            Text([person.label, hoursText(person)].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private func hourText(_ h: Double) -> String {
    let hh = Int(h) % 24, mm = Int((h - Double(Int(h))) * 60)
    return mm == 0 ? "\(h12(hh)) \(ampm(hh))" : "\(h12(hh)):\(String(format: "%02d", mm)) \(ampm(hh))"
}

private func hoursText(_ p: Person) -> String { "\(hourText(p.start))–\(hourText(p.end))" }

struct PersonEditor: View {
    @Binding var person: Person
    private let halfHours = stride(from: 0.0, through: 24, by: 0.5).map { $0 }

    var body: some View {
        Form {
            Section {
                TextField("Who's there? (e.g. Design team)", text: $person.label)
                NavigationLink {
                    CitySearch { city, tz, coord in
                        person.city = city
                        person.tzID = tz.identifier
                        person.lat = coord.latitude
                        person.lon = coord.longitude
                    }
                } label: {
                    LabeledContent("City", value: person.city)
                }
            } footer: {
                Text(person.tz.localizedName(for: .generic, locale: .current) ?? person.tzID)
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

/// Apple Maps search: each result carries its own time zone and coordinates.
struct CitySearch: View {
    let onPick: (String, TimeZone, CLLocationCoordinate2D) -> Void
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(results, id: \.self) { item in
            Button {
                guard let tz = item.timeZone else { return }
                onPick(name(item), tz, item.placemark.coordinate)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(item)).foregroundStyle(.primary)
                    Text(subtitle(item)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if failed { ContentUnavailableView("Can't reach Apple Maps", systemImage: "wifi.slash") }
            else if results.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "City")
        .navigationTitle("Add a city")
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .address
            do {
                results = try await MKLocalSearch(request: request).start().mapItems.filter { $0.timeZone != nil }
                failed = false
            } catch {
                if !Task.isCancelled { results = []; failed = (error as? MKError)?.code != .placemarkNotFound }
            }
        }
    }

    private func name(_ item: MKMapItem) -> String { item.placemark.locality ?? item.name ?? "Unknown" }
    private func subtitle(_ item: MKMapItem) -> String {
        [item.placemark.administrativeArea, item.placemark.country].compactMap { $0 }.joined(separator: ", ")
    }
}
