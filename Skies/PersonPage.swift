import SwiftUI

/// One person's page as a sheet (from a band's menu).
struct PersonPage: View {
    let people: People
    let model: Scrubber
    let holidays: Holidays
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PersonDetail(people: people, model: model, holidays: holidays, id: id) { dismiss() }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 680)
        #endif
    }
}

/// One person's sky, full screen, with Weather-style modules underneath. Works pushed from the People list too.
struct PersonDetail: View {
    @Bindable var people: People
    let model: Scrubber
    let holidays: Holidays
    let id: UUID
    /// Called after "Plan with…" picks them, so whoever presented this can close.
    let onPlan: () -> Void
    @AppStorage(ShowBy.key, store: .skies) private var showBy: ShowBy = .name
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let i = people.list.firstIndex(where: { $0.id == id }) {
            let p = people.list[i]
            SkyClock(moving: model.isMoving) { date in
                let m = model.minutes(at: date)
                ScrollView {
                    VStack(spacing: 14) {
                        hero(p, m: m)
                        #if os(macOS)
                        NavigationLink { PersonEditor(person: $people.list[i]) } label: {
                            Label("Edit \(p.name)", systemImage: "pencil")
                                .font(.sf(14, .semibold)).padding(.horizontal, 16).frame(height: 34)
                        }
                        .buttonStyle(.whole)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        #endif
                        if let contact = Binding($people.list[i].contact) { ReachModule(contact: contact) }
                        dayModule(p, m: m)
                        sunModule(p, m: m)
                        holidayModule(p, m: m)
                        if !p.isHome {
                            Button {
                                people.picked = [p.id]
                                onPlan()
                            } label: {
                                Label("Plan with \(p.shortName)", systemImage: "person.crop.circle.badge.checkmark")
                                    .sf(17, .semibold).padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonStyle(.whole)
                            .glassEffect(.regular.tint(.mint.opacity(0.4)).interactive(), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .background {
                    SkyBackground(person: p, minutes: m, flare: 1, twinkle: true)
                        .ignoresSafeArea()
                }
            }
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Edit") { PersonEditor(person: $people.list[i]) }
                }
            }
        }
    }

    private var home: Person { people.home }

    private func hero(_ p: Person, m: Double) -> some View {
        let l = Local(p.tz, m), h = Local(home.tz, m)
        let diff = Double(l.off - h.off)
        let rel = p.isHome ? "Your time" : diff == 0 ? "Same time as you" : "\(dur(diff)) \(diff < 0 ? "behind" : "ahead of") you"
        return VStack(spacing: 2) {
            Avatar(person: p, size: 84).padding(.bottom, 10)
            Text(p.title(showBy)).sf(32, .semibold)
            Text([p.name, p.code, p.city].filter { $0 != p.title(showBy) }.joined(separator: " · ")).sf(17, .medium).opacity(0.8)
            if !p.tagObjects.isEmpty {
                HStack(spacing: 6) {
                    ForEach(p.tagObjects) { t in
                        Text(t.name).sf(13, .semibold)
                            .padding(.horizontal, 10).frame(minHeight: 24)
                            .background(Color(t.rgb).opacity(0.85), in: Capsule())
                    }
                }
                .padding(.top, 6)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(clock(l)).sf(96, .thin).tracking(-3).monospacedDigit()
                if !TimeFormat.twentyFour { Text(ampm(l.h)).sf(26, .light) }
            }
            .lineLimit(1).minimumScaleFactor(0.5)
            Text("\(status(p, l).0) · \(rel)").sf(17, .medium)
        }
        .skyLegible()
        .padding(.top, 36).padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    // MARK: Their day, your time

    /// Their availability and yours on one axis (your day), with the time you share outlined.
    private func dayModule(_ p: Person, m: Double) -> some View {
        let start = dayStart(home.tz, m)
        let talk = p.relation == .personal
        let runs = p.isHome ? [] : freeRuns([home, p], from: start, slots: 96, mode: p.relation)
        return Module(title: p.isHome ? "Your day" : "Their day, your time", icon: "clock") {
            VStack(alignment: .leading, spacing: 12) {
                if !p.isHome {
                    Text(runs.isEmpty ? "No shared \(talk ? "talking" : "working") time this day"
                         : "\(talk ? "Best to talk" : "Overlap") \(runs.map { timeRange($0, home) }.joined(separator: ", "))")
                        .sf(17, .semibold)
                }
                DayLanes(home: home, person: p, start: start, now: nowMinutes(), scrub: m, runs: runs)
                    .frame(height: p.isHome ? 44 : 78)
                let legends = typeSize.row(spacing: 14)
                legends {
                    legend(.mint, "Free")
                    legend(Color(hex: 0xFFC46B), "Busy")
                    legend(.white.opacity(0.25), "Off")
                }
                Text("\(p.isHome ? "You're" : "They're") free \(hourText(p.start))–\(hourText(p.end)) \(p.isHome ? "your" : "their") time, \(daysText(p.days)).")
                    .sf(13, .regular).opacity(0.7)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 6)
            Text(text).sf(12, .medium).opacity(0.75)
        }
    }

    // MARK: Sun

    /// Their sun and yours across your day, so the daylight you share is easy to see.
    private func sunModule(_ p: Person, m: Double) -> some View {
        let l = Local(p.tz, m), s = sun(p, l)
        let start = dayStart(home.tz, m)
        let theirDay = s.set - s.rise
        let mine = sun(home, Local(home.tz, m))
        let gap = theirDay - (mine.set - mine.rise)
        // Their sunrise and sunset, as moments, so they can be shown in your time too.
        let theirStart = dayStart(p.tz, m)
        let rise = theirStart + s.rise * 60, set = theirStart + s.set * 60
        func yours(_ t: Double) -> String { let h = Local(home.tz, t); return "\(hm(h))" }
        let shared = sharedDaylight(home, p, from: start)
        return Module(title: "Sunrise and sunset", icon: "sunrise.fill") {
            VStack(alignment: .leading, spacing: 10) {
                let big = typeSize.isAccessibilitySize
                let times = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                times {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hourText(s.rise)).sf(28, .regular)
                        Text(p.isHome ? "Sunrise" : "Sunrise · \(yours(rise)) yours").sf(13, .medium).opacity(0.65)
                    }
                    if !big { Spacer() }
                    VStack(alignment: big ? .leading : .trailing, spacing: 2) {
                        Text(hourText(s.set)).sf(28, .regular)
                        Text(p.isHome ? "Sunset" : "Sunset · \(yours(set)) yours").sf(13, .medium).opacity(0.65)
                    }
                }
                SunCurves(home: home, person: p, dayStart: start, now: m).frame(height: 84)
                if !p.isHome {
                    let legends = typeSize.row(spacing: 14)
                    legends {
                        legend(.white, p.shortName)
                        legend(.white.opacity(0.35), "You")
                        legend(Color.sun.opacity(0.35), "Both in daylight")
                    }
                }
                Text(p.isHome ? "\(Int(theirDay))h \(Int((theirDay - Double(Int(theirDay))) * 60))m of daylight"
                     : shared.isEmpty ? "You never share daylight today."
                     : "Daylight together \(shared.map { timeRange($0, home) }.joined(separator: ", ")). \(abs(gap) < 1.0 / 6 ? "About the same day length as you." : "\(dur(abs(gap) * 60)) \(gap > 0 ? "more" : "less") daylight than you.")")
                    .sf(13, .medium).opacity(0.75)
            }
        }
    }

    /// Stretches of your day when the sun is up for both of you.
    private func sharedDaylight(_ a: Person, _ b: Person, from start: Double) -> [ClosedRange<Double>] {
        var runs: [ClosedRange<Double>] = []
        var cur: Double?
        for k in 0...96 {
            let t = start + Double(k) * 15
            let both = k < 96 && sunPosition(a, t).elev > -0.833 && sunPosition(b, t).elev > -0.833
            if both, cur == nil { cur = t }
            if !both, let c = cur { runs.append(c...t); cur = nil }
        }
        return runs
    }

    // MARK: Their days

    /// Their public holidays, read from your Calendar's holiday calendars, and their birthday from the linked contact.
    @ViewBuilder private func holidayModule(_ p: Person, m: Double) -> some View {
        let l = Local(p.tz, m)
        let country = p.region.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        Module(title: "Their days", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                if let b = p.contact?.birthday, let month = b.month, let day = b.day {
                    let date = gmtCalendar.date(from: DateComponents(year: 2000, month: month, day: day))
                    // A birthday is a calendar date, not a moment: format it in GMT so it can't slip a day.
                    Label("Birthday \(date.map { $0.formatted(Date.FormatStyle(timeZone: .gmt).day().month(.wide)) } ?? "")",
                          systemImage: "birthday.cake.fill")
                        .sf(16, .medium)
                }
                if let country {
                    if !holidays.granted {
                        Text("See public holidays in \(country) from the holiday calendars in your Calendar app.")
                            .sf(15, .regular).opacity(0.85)
                        Button { Task { await holidays.enable() } } label: {
                            Text("Show holidays").sf(15, .semibold).padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 38)
                        }
                            .buttonStyle(.whole)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    } else if holidays.covers(p) {
                        ForEach(holidays.upcoming(p, from: l), id: \.day) { h in
                            let row = typeSize.row()
                            row {
                                Text(h.title).sf(15, .medium)
                                if !typeSize.isAccessibilitySize { Spacer() }
                                Text(holidayDate(h.day)).sf(14, .regular).opacity(0.75)
                            }
                        }
                    } else {
                        Text("No holiday calendar for \(country) yet. Add one in Calendar \u{203A} Holidays and it shows up here.")
                            .sf(15, .regular).opacity(0.85)
                    }
                } else {
                    Text("Holidays appear once Skies knows which country \(p.city) is in.").sf(15, .regular).opacity(0.85)
                }
            }
        }
    }

    private func holidayDate(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let d = gmtCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return key }
        return d.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Lanes

/// Free, busy and asleep across your day, for them and for you, with the shared window outlined.
struct DayLanes: View {
    let home: Person, person: Person
    let start: Double, now: Double, scrub: Double
    let runs: [ClosedRange<Double>]

    var body: some View {
        let rows: [(String, Person)] = person.isHome ? [("You", home)] : [(person.shortName, person), ("You", home)]
        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in
                let labelW = 54.0, barH = 14.0, gap = 10.0
                let w = size.width - labelW
                func x(_ t: Double) -> Double { labelW + (t - start) / 1440 * w }
                let mode: Person.Kind? = person.isHome ? nil : person.relation
                for (row, (name, who)) in rows.enumerated() {
                    let y = Double(row) * (barH + gap)
                    ctx.draw(Text(name).font(.sf(12, .semibold)).foregroundStyle(.white.opacity(0.8)),
                             at: CGPoint(x: 0, y: y + barH / 2), anchor: .leading)
                    // Free, busy (inside their hours but at work), or off; consecutive slots merged into one bar each,
                    // so translucent pieces never overlap into stripes.
                    func kind(_ k: Int) -> Int {
                        let l = Local(who.tz, start + Double(k) * 15 + 7.5)
                        if who.free(l, with: mode) { return 0 }
                        let inHours = who.days.contains(l.wd) && who.inHours(l.f)
                        return inHours || (who.isHome && mode == .personal && l.f >= 8 && l.f < 22) ? 1 : 2
                    }
                    let colors: [Color] = [.mint, Color(hex: 0xFFC46B).opacity(0.8), .white.opacity(0.18)]
                    var k = 0
                    while k < 96 {
                        let c = kind(k)
                        var e = k + 1
                        while e < 96 && kind(e) == c { e += 1 }
                        let rect = CGRect(x: x(start + Double(k) * 15), y: y, width: Double(e - k) / 96 * w, height: barH)
                        ctx.fill(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0), cornerRadius: 3), with: .color(colors[c]))
                        k = e
                    }
                }
                let lanesH = Double(rows.count) * barH + Double(rows.count - 1) * gap
                for r in runs {
                    let rect = CGRect(x: x(r.lowerBound) - 1, y: -3, width: x(r.upperBound) - x(r.lowerBound) + 2, height: lanesH + 6)
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(.white), lineWidth: 1.5)
                }
                for (t, opacity) in [(now, 1.0), (scrub, 0.5)] where t >= start && t <= start + 1440 && (t == now || abs(scrub - now) > 1) {
                    ctx.fill(Path(CGRect(x: x(t) - 1, y: -6, width: 2, height: lanesH + 12)), with: .color(Color.sun.opacity(opacity)))
                }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 54)
                ForEach(["12 AM", "6 AM", "12 PM", "6 PM"], id: \.self) {
                    Text($0).font(.sf(10, .medium)).opacity(0.5).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(runs.isEmpty ? "No shared time" : "Shared time " + runs.map { timeRange($0, home) }.joined(separator: ", "))
    }
}

// MARK: - Sun curves

/// Their sun's real elevation through your day, with yours faint behind it and the daylight you share shaded.
struct SunCurves: View {
    let home: Person, person: Person, dayStart: Double, now: Double

    var body: some View {
        Canvas { ctx, size in
            let people = person.isHome ? [home] : [home, person]
            let samples = people.map { p in
                (0...96).map { k in sunPosition(p, dayStart + Double(k) * 15).elev }
            }
            let all = samples.flatMap { $0 }
            let top = max(10, all.max() ?? 10), bottom = min(-10, all.min() ?? -10)
            func y(_ e: Double) -> Double { (top - e) / (top - bottom) * size.height }
            func x(_ k: Int) -> Double { Double(k) / 96 * size.width }
            let horizon = y(0)

            if samples.count == 2 {
                var k = 0
                while k < 96 {
                    guard samples[0][k] > 0 && samples[1][k] > 0 else { k += 1; continue }
                    var e = k + 1
                    while e < 96 && samples[0][e] > 0 && samples[1][e] > 0 { e += 1 }
                    ctx.fill(Path(CGRect(x: x(k), y: 0, width: x(e) - x(k), height: horizon)), with: .color(Color.sun.opacity(0.24)))
                    k = e
                }
            }
            ctx.fill(Path(CGRect(x: 0, y: horizon - 0.5, width: size.width, height: 1)), with: .color(.white.opacity(0.35)))

            for (i, s) in samples.enumerated() {
                let theirs = i == samples.count - 1
                var curve = Path()
                curve.addLines(s.indices.map { CGPoint(x: x($0), y: y(s[$0])) })
                var above = ctx
                above.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
                above.stroke(curve, with: .color(.white.opacity(theirs ? 1 : 0.35)), lineWidth: theirs ? 2 : 1.5)
                var below = ctx
                below.clip(to: Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)))
                below.stroke(curve, with: .color(.white.opacity(theirs ? 0.3 : 0.15)), lineWidth: theirs ? 2 : 1.5)
            }

            let f = (now - dayStart) / 1440
            if f >= 0 && f <= 1 {
                let e = sunPosition(person, now).elev
                let p = CGPoint(x: f * size.width, y: y(e))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                         with: .color(e > 0 ? .sun : .white.opacity(0.7)))
            }
        }
        .accessibilityHidden(true)
    }
}
