import SwiftUI

let pxPerMinute = 72.0 / 60
private let bound = 48.0 * 60

func nowMinutes(_ d: Date = .now) -> Double { d.timeIntervalSince1970 / 60 }
func snap(_ m: Double) -> Double { (m / 15).rounded() * 15 }

/// Where the scrubber is, as a pure function of time, so the view never mutates state per frame.
@MainActor @Observable final class Scrubber {
    struct Motion {
        let start: Date, from: Double, delta: Double, v0: Double, live: Bool, spring: Spring
        func t(_ d: Date) -> Double { d.timeIntervalSince(start) }
        func value(at d: Date) -> Double {
            from + spring.value(target: delta, initialVelocity: v0, time: t(d)) + (live ? t(d) / 60 : 0)
        }
        func velocity(at d: Date) -> Double { spring.velocity(target: delta, initialVelocity: v0, time: t(d)) }
    }
    enum Mode { case live, rest(Double), drag(Double), spring(Motion) }

    var mode = Mode.live
    var hintGone = false
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var dragStart: Double?

    var isMoving: Bool {
        switch mode { case .drag, .spring: true; default: false }
    }

    func minutes(at d: Date) -> Double {
        switch mode {
        case .live: nowMinutes(d)
        case .rest(let m), .drag(let m): m
        case .spring(let s): s.value(at: d)
        }
    }

    /// Where a keyboard step should start from: the spring's destination if one is in flight.
    var base: Double {
        if case .spring(let s) = mode, !s.live { return s.from + s.delta }
        return minutes(at: .now)
    }

    func springTo(_ to: Double, live: Bool = false, damping: Double = 1, response: Double = 0.45, velocity: Double? = nil) {
        let now = Date.now
        let from = minutes(at: now)
        var v0 = 0.0
        if let velocity { v0 = velocity } else if case .spring(let s) = mode { v0 = s.velocity(at: now) }
        if reduceMotion { mode = live ? .live : .rest(to); return }

        let motion = Motion(start: now, from: from, delta: to - from, v0: v0, live: live,
                            spring: Spring(response: response, dampingRatio: damping))
        mode = .spring(motion)
        let settle = motion.spring.settlingDuration(target: motion.delta, initialVelocity: v0, epsilon: 0.02)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(settle))
            guard let self, case .spring(let cur) = self.mode, cur.start == motion.start else { return }
            self.mode = live ? .live : .rest(to)
        }
    }

    func goNow() { springTo(nowMinutes(), live: true, response: 0.5) }

    func dragChanged(_ g: DragGesture.Value, width: Double) {
        if dragStart == nil { dragStart = minutes(at: .now); hintGone = true }
        let now = nowMinutes(), lo = now - bound, hi = now + bound
        var raw = dragStart! - g.translation.width / pxPerMinute
        if raw > hi { raw = hi + rubber((raw - hi) * pxPerMinute, width) / pxPerMinute }
        if raw < lo { raw = lo - rubber((lo - raw) * pxPerMinute, width) / pxPerMinute }
        mode = .drag(raw)
    }

    func dragEnded(_ g: DragGesture.Value) {
        dragStart = nil
        let x = minutes(at: .now), now = nowMinutes()
        let projected = x - (g.predictedEndTranslation.width - g.translation.width) / pxPerMinute
        let t = snap(min(now + bound, max(now - bound, projected)))
        let vel = -g.velocity.width / pxPerMinute
        if abs(t - now) < 8 { springTo(now, live: true, damping: 0.86, response: 0.42, velocity: vel) }
        else { springTo(t, damping: 0.86, response: 0.42, velocity: vel) }
    }

    func step(_ minutes: Double) { springTo(snap(base + minutes)) }

    private func rubber(_ over: Double, _ dim: Double, _ c: Double = 0.55) -> Double {
        over * dim * c / (dim + c * abs(over))
    }
}
