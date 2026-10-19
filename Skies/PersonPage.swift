import SwiftUI

/// One person's sky, full screen, with Weather-style modules underneath.
struct PersonPage: View {
    @Bindable var people: People
    let model: Scrubber
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let i = people.list.firstIndex(where: { $0.id == id }) {
                let p = people.list[i]
                TimelineView(.animation(minimumInterval: model.isMoving ? nil : 1)) { ctx in
                    let m = model.minutes(at: ctx.date)
                    ScrollView {
                        VStack(spacing: 14) {
                            hero(p, m: m)
                            if !p.isHome { together(p, m: m) }
                            sunModule(p, m: m)
                            weekModule(p)
                            if !p.isHome {
                                Button {
                                    people.picked = [p.id]
                                    dismiss()
                                } label: {
                                    Label("Plan with \(p.city)", systemImage: "person.crop.circle.badge.checkmark")
                                        .font(sf(17, .semibold)).frame(maxWidth: .infinity).frame(height: 50)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.tint(.mint.opacity(0.4)).interactive(), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                    .background { SkyBackground(person: p, minutes: m).ignoresSafeArea() }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink("Edit") { PersonEditor(person: $people.list[i]) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 680)
        #endif
    }

    private var home: Person { people.home }

    private func hero(_ p: Person, m: Double) -> some View {
        let l = Local(p.tz, m), h = Local(home.tz, m)
        let diff = Double(l.off - h.off)
        let rel = p.isHome ? "Your time" : diff == 0 ? "Same time as you" : "\(dur(diff)) \(diff < 0 ? "behind" : "ahead of") you"
        return VStack(spacing: 2) {
            Text(p.city).font(sf(32, .semibold))
            if !p.label.isEmpty { Text(p.label).font(sf(17, .medium)).opacity(0.8) }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(clock(l)).font(sf(96, .thin)).tracking(-3).monospacedDigit()
                Text(ampm(l.h)).font(sf(26, .light))
            }
            Text("\(status(p, l).0) · \(rel)").font(sf(17, .medium))
        }
        .skyLegible()
        .padding(.top, 36).padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private func together(_ p: Person, m: Double) -> some View {
        let runs = freeRuns([home, p], from: dayStart(home.tz, m), slots: 96)
        let theirStart = dayStart(p.tz, m) + p.start * 60
        let mine = Local(home.tz, theirStart)
        return Module(title: "With you", icon: "person.2") {
            VStack(alignment: .leading, spacing: 6) {
                Text(runs.isEmpty ? "No shared free time this day" : "Free together \(runs.map { timeRange($0, home) }.joined(separator: ", ")) your time")
                    .font(sf(17, .semibold))
                Text("When it's \(hourText(p.start)) in \(p.city), it's \(clock(mine)) \(ampm(mine.h)) for you.")
                    .font(sf(15, .regular)).opacity(0.8)
            }
        }
    }

    private func sunModule(_ p: Person, m: Double) -> some View {
        let l = Local(p.tz, m)
        let s = sun(p, l)
        let start = dayStart(p.tz, m)
        let day = s.set - s.rise
        return Module(title: "Sunrise and sunset", icon: "sunrise.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(hourText(s.rise.truncatingRemainder(dividingBy: 24))).font(sf(28, .regular))
                        Text("Sunrise").font(sf(13, .medium)).opacity(0.6)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(hourText(s.set.truncatingRemainder(dividingBy: 24))).font(sf(28, .regular))
                        Text("Sunset").font(sf(13, .medium)).opacity(0.6)
                    }
                }
                SunCurve(person: p, dayStart: start, now: m).frame(height: 70)
                Text("\(Int(day))h \(Int((day - Double(Int(day))) * 60))m of daylight")
                    .font(sf(13, .medium)).opacity(0.7)
            }
        }
    }

    private func weekModule(_ p: Person) -> some View {
        let first = Calendar.current.firstWeekday - 1
        return Module(title: "Free to talk", icon: "calendar.badge.clock") {
            VStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let d = (i + first) % 7
                    let on = p.days.contains(d)
                    HStack(spacing: 12) {
                        Text(Calendar.current.shortWeekdaySymbols[d]).font(sf(15, .medium)).frame(width: 44, alignment: .leading)
                        if on {
                            RangeBar(start: 0, runs: p.end > p.start ? [p.start * 60...p.end * 60]
                                                                     : [0...p.end * 60, p.start * 60...1440])
                            Text("\(hourText(p.start))–\(hourText(p.end))").font(sf(13, .regular)).opacity(0.75)
                                .frame(width: 120, alignment: .trailing)
                        } else {
                            Text("Day off").font(sf(14, .regular)).opacity(0.45)
                            Spacer()
                        }
                    }
                    .frame(height: 34)
                }
            }
        }
    }
}

/// The sun's real elevation through the local day, with the horizon and where it is right now.
struct SunCurve: View {
    let person: Person, dayStart: Double, now: Double

    var body: some View {
        Canvas { ctx, size in
            let samples = (0...96).map { k -> CGPoint in
                let t = dayStart + Double(k) * 15
                return CGPoint(x: Double(k) / 96 * size.width, y: sunPosition(person, t).elev)
            }
            let top = max(10, samples.map(\.y).max() ?? 10), bottom = min(-10, samples.map(\.y).min() ?? -10)
            func y(_ e: Double) -> Double { (top - e) / (top - bottom) * size.height }
            var curve = Path()
            curve.addLines(samples.map { CGPoint(x: $0.x, y: y($0.y)) })
            let horizon = y(0)
            ctx.fill(Path(CGRect(x: 0, y: horizon - 0.5, width: size.width, height: 1)), with: .color(.white.opacity(0.35)))
            var above = ctx
            above.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
            above.stroke(curve, with: .color(.white), lineWidth: 2)
            var below = ctx
            below.clip(to: Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)))
            below.stroke(curve, with: .color(.white.opacity(0.3)), lineWidth: 2)

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
