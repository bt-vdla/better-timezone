import SwiftUI

/// A Weather-style card: small symbol header, then content.
struct Module<Content: View>: View {
    let title: String, icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title.uppercased(), systemImage: icon)
                .font(sf(12, .semibold)).tracking(0.4).opacity(0.6)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }
}

/// The selected team's week: one row per day with the shared window as a range bar, like Weather's 10-day forecast.
struct PlannerSheet: View {
    let people: People
    let model: Scrubber
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.animation(minimumInterval: model.isMoving ? nil : 1)) { ctx in
                let m = model.minutes(at: ctx.date), now = nowMinutes(ctx.date)
                ScrollView {
                    VStack(spacing: 14) {
                        week(m: m, now: now)
                        hours(m: m, now: now)
                        changes(now: now)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(people.everyone ? "Everyone" : people.team.map(\.city).joined(separator: ", "))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        #else
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private var home: Person { people.home }

    // MARK: This week

    private func week(m: Double, now: Double) -> some View {
        let today = dayStart(home.tz, now)
        let runs = people.runs(from: today)
        return Module(title: "Free together this week", icon: "calendar") {
            VStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { k in
                    let start = dayStart(home.tz, today + Double(k) * 1440 + 720)
                    let end = start + 1440
                    let day = runs.compactMap { r -> ClosedRange<Double>? in
                        let a = max(r.lowerBound, start), b = min(r.upperBound, end)
                        return a < b ? a...b : nil
                    }
                    let total = day.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
                    Button {
                        if let first = day.first { model.springTo(first.lowerBound, response: 0.5) }
                    } label: {
                        HStack(spacing: 12) {
                            Text(k == 0 ? "Today" : k == 1 ? "Tomorrow" : Calendar.current.weekdaySymbols[Local(home.tz, start + 720).wd])
                                .font(sf(16, .medium)).frame(width: 92, alignment: .leading)
                            RangeBar(start: start, runs: day,
                                     now: k == 0 ? now : nil,
                                     scrub: (start..<end).contains(m) ? m : nil)
                            Text(total > 0 ? dur(total) : "—")
                                .font(sf(14, .medium)).monospacedDigit().opacity(total > 0 ? 0.9 : 0.4)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale(scale: 0.98))
                    .disabled(day.isEmpty)
                    .accessibilityLabel(day.isEmpty ? "No shared time" : day.map { timeRange($0, home) }.joined(separator: ", "))
                    if k < 6 { Divider().opacity(0.4) }
                }
                HStack {
                    ForEach(["12 AM", "6 AM", "12 PM", "6 PM"], id: \.self) { Text($0).frame(maxWidth: .infinity, alignment: .leading) }
                }
                .font(sf(10, .medium)).opacity(0.45)
                .padding(.leading, 104).padding(.trailing, 68).padding(.top, 6)
            }
        }
    }

    // MARK: Next 24 hours

    private func hours(m: Double, now: Double) -> some View {
        let first = (now / 60).rounded(.down) * 60
        return Module(title: "Next 24 hours", icon: "clock") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<24, id: \.self) { k in
                        let t = first + Double(k) * 60
                        let l = Local(home.tz, t)
                        let free = people.team.filter { $0.free(Local($0.tz, t + 30)) }.count
                        let all = free == people.team.count
                        let up = sunPosition(home, t + 30).elev > 0
                        Button { model.springTo(t, response: 0.5) } label: {
                            VStack(spacing: 8) {
                                Text(k == 0 ? "Now" : "\(h12(l.h)) \(ampm(l.h))").font(sf(13, .semibold))
                                Image(systemName: up ? "sun.max.fill" : "moon.stars.fill")
                                    .symbolRenderingMode(.multicolor).font(sf(18, .regular)).frame(height: 22)
                                Text("\(free)/\(people.team.count)").font(sf(13, .medium)).monospacedDigit()
                                    .foregroundStyle(all ? Color.mint : .white.opacity(0.6))
                            }
                            .frame(width: 52).padding(.vertical, 10)
                            .background(all ? Color.mint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(PressScale())
                        .accessibilityLabel("\(h12(l.h)) \(ampm(l.h)), \(free) of \(people.team.count) free")
                    }
                }
            }
        }
    }

    // MARK: Clock changes

    @ViewBuilder private func changes(now: Double) -> some View {
        let upcoming = clockChanges(people.list, in: now...(now + 60 * 1440))
        if !upcoming.isEmpty {
            Module(title: "Clock changes", icon: "clock.arrow.2.circlepath") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(upcoming, id: \.person.id) { c in
                        let date = Date(timeIntervalSince1970: c.at * 60)
                            .formatted(Date.FormatStyle(timeZone: home.tz).weekday(.abbreviated).day().month(.abbreviated))
                        HStack {
                            Text(c.person.city).font(sf(15, .semibold))
                            Spacer()
                            Text("\(date) · clocks go \(c.shift < 0 ? "back" : "forward") \(dur(Double(c.shift)))")
                                .font(sf(14, .regular)).opacity(0.8)
                        }
                    }
                    if let note = clockNote(people, after: now) {
                        Text(note).font(sf(13, .medium)).foregroundStyle(Color.sun)
                    }
                }
            }
        }
    }
}

/// A day on a 24-hour axis with the shared window filled in, plus "now" and the scrubbed moment.
struct RangeBar: View {
    let start: Double, runs: [ClosedRange<Double>]
    var now: Double? = nil, scrub: Double? = nil

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = { (t: Double) -> Double in (t - start) / 1440 * w }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                ForEach(runs, id: \.lowerBound) { r in
                    Capsule()
                        .fill(LinearGradient(colors: [.mint, Color(hex: 0x5ED0F0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, x(r.upperBound) - x(r.lowerBound)))
                        .offset(x: x(r.lowerBound))
                }
                if let scrub {
                    Capsule().fill(.white).frame(width: 2, height: 12).offset(x: x(scrub) - 1)
                }
                if let now {
                    Circle().fill(Color.sun).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                        .offset(x: x(now) - 3.5)
                }
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
