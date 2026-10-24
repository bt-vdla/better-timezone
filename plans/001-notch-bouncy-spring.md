# 001 — Give the notch a bouncy, fluid open and close

- **Status**: DONE
- **Commit**: a7ec9b5 (plus uncommitted `Skies/Notch.swift`, staged; it must exist before executing)
- **Severity**: HIGH (requested feel change)
- **Category**: Interruptibility / Easing & duration / Accessibility
- **Estimated scope**: 1 file (`Skies/Notch.swift`), ~25 lines

## Problem

The notch panel opens and closes with springs that barely overshoot, so it reads as a tween
rather than something elastic growing out of the notch. Content fades in on a plain ease-out
with only a 4% scale, so it doesn't share the shape's physics. Closing ignores Reduce Motion,
and the closed "ears" (the countdown beside the notch) appear and disappear with no animation,
so the black shape jumps in width.

```swift
// Skies/Notch.swift:130-133 — current (open)
let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
// The shape leads, like the notch growing; the content follows a beat later, blurred into focus.
withAnimation(reduce ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) { state.shapeOpen = true }
withAnimation(.easeOut(duration: 0.22).delay(reduce ? 0 : 0.08)) { state.contentShown = true }
```

```swift
// Skies/Notch.swift:139-149 — current (close)
// Closing is quicker: content out first, then the shape tucks back into the notch.
withAnimation(.easeOut(duration: 0.1)) { state.contentShown = false }
withAnimation(.spring(response: 0.26, dampingFraction: 1).delay(0.05)) { state.shapeOpen = false }
monitors.forEach(NSEvent.removeMonitor)
monitors = []
closing = Task {
    try? await Task.sleep(for: .milliseconds(320))
    guard !Task.isCancelled, !state.shapeOpen else { return }
    panel.ignoresMouseEvents = true
    panel.resignKey()
}
```

```swift
// Skies/Notch.swift:258-265 — current (content inside the shape)
.overlay(alignment: .top) {
    content(m: m, now: now, time: ctx.date.timeIntervalSinceReferenceDate)
        .frame(width: openWidth, height: openHeight)
        .opacity(state.contentShown ? 1 : 0)
        .blur(radius: state.contentShown ? 0 : 10)
        .scaleEffect(state.contentShown ? 1 : 0.96, anchor: .top)
        .allowsHitTesting(state.contentShown)
}
```

```swift
// Skies/Notch.swift:244-247 — current (ears change the closed width with no animation)
let soon = state.shapeOpen ? nil : countdown(now)
let earW: CGFloat = soon == nil ? 0 : 74
let closed = CGSize(width: state.notch.width == 0 && soon == nil ? 0 : state.notch.width + earW * 2,
                    height: state.notch.width == 0 && soon == nil ? 0 : state.notch.height)
```

Note on frequency: this panel opens from a keyboard shortcut, and the usual rule is that
shortcut-triggered UI shouldn't animate. The user has explicitly chosen an Alcove-style
animated notch, so it stays animated. To respect the rule's intent the motion must never
block: the panel takes clicks and keys from the first frame of opening, and every spring
retargets if the shortcut is pressed again mid-flight.

## Target

Apple-style springs (`duration` + `bounce`), the bounce reserved for the open:

| Moment | Animation |
| --- | --- |
| Shape opens | `.spring(duration: 0.5, bounce: 0.3)` |
| Content in (scale) | same spring, `.delay(0.06)`; scale from `0.9` to `1`, anchor `.top` |
| Content in (opacity + blur) | `.easeOutStrong(0.2)` with `.delay(0.06)`; blur `10` → `0` |
| Content out | `.easeOutStrong(0.12)` (no delay) |
| Shape closes | `.spring(duration: 0.35, bounce: 0.15)` with `.delay(0.04)` |
| Ears appear / disappear | `.spring(duration: 0.4, bounce: 0.25)` |
| Reduce Motion: everything | `.easeOutStrong(0.2)`, no scale (content scale stays `1`), opacity/blur kept |

`easeOutStrong` already exists in this repo (see conventions). A bounce of 0.3 is the top of
the allowed 0.1–0.3 range; that's intentional for this playful, rare-ish reveal. Closing
undershooting slightly is invisible because the hardware notch is black.

## Repo conventions to follow

- Strong ease-out is a project helper, `Skies/SkiesView.swift:18`:
  ```swift
  static func easeOutStrong(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
  ```
  Use `.easeOutStrong(x)` instead of `.easeOut(duration: x)`.
- Springs elsewhere use SwiftUI's `.spring(...)`; use the `duration:bounce:` initialiser here.
- Reduce Motion in AppKit code is read as `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (`Skies/Notch.swift:130`).

## Steps

1. In `NotchController` (`Skies/Notch.swift`), add below `static let size = ...` (line 80):
   ```swift
   /// One place for the notch's motion: a bouncy open, a quicker settle on close.
   static let openSpring = Animation.spring(duration: 0.5, bounce: 0.3)
   static let closeSpring = Animation.spring(duration: 0.35, bounce: 0.15)
   static let earSpring = Animation.spring(duration: 0.4, bounce: 0.25)
   static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
   ```
2. Replace lines 130–133 of `open()` with:
   ```swift
   let reduce = Self.reduceMotion
   // The shape leads, like the notch growing; the content follows a beat later on the same spring.
   withAnimation(reduce ? .easeOutStrong(0.2) : Self.openSpring) { state.shapeOpen = true }
   withAnimation(reduce ? .easeOutStrong(0.2) : Self.openSpring.delay(0.06)) { state.contentShown = true }
   ```
3. Replace the two `withAnimation` lines in `close()` (139–141, keep the comment) with:
   ```swift
   let reduce = Self.reduceMotion
   withAnimation(.easeOutStrong(reduce ? 0.2 : 0.12)) { state.contentShown = false }
   withAnimation(reduce ? .easeOutStrong(0.2) : Self.closeSpring.delay(0.04)) { state.shapeOpen = false }
   ```
   and change `Task.sleep(for: .milliseconds(320))` to `Task.sleep(for: .milliseconds(420))` so the panel
   stops taking clicks only after the close spring has settled.
4. In `NotchView`, replace the content modifiers (lines 261–264) with separate animations for scale
   (spring) and fade (ease-out), so opacity never bounces:
   ```swift
   .scaleEffect(state.contentShown || NotchController.reduceMotion ? 1 : 0.9, anchor: .top)
   .animation(NotchController.reduceMotion ? nil : NotchController.openSpring.delay(0.06), value: state.contentShown)
   .opacity(state.contentShown ? 1 : 0)
   .blur(radius: state.contentShown ? 0 : 10)
   .animation(.easeOutStrong(state.contentShown ? 0.2 : 0.12).delay(state.contentShown ? 0.06 : 0), value: state.contentShown)
   .allowsHitTesting(state.contentShown)
   ```
   (These scoped `.animation(_:value:)` modifiers take precedence over the `withAnimation` transaction
   for these properties; the `withAnimation` in step 2/3 still drives the shape.)
5. In `NotchView.body`, after `.frame(width: size.width, height: size.height)` on the shape (line 254), add:
   ```swift
   .animation(NotchController.reduceMotion ? .easeOutStrong(0.2) : NotchController.earSpring, value: soon != nil)
   ```
   so the closed shape widens and narrows smoothly when the countdown ears appear or go.
6. Make sure the panel accepts input from the first frame of opening: `panel.ignoresMouseEvents = false`
   and `panel.makeKeyAndOrderFront(nil)` must stay **before** the `withAnimation` calls in `open()`
   (they already are; do not move them).

## Boundaries

- Do NOT touch anything outside `Skies/Notch.swift`.
- Do NOT change the panel size, the open width/height, the content layout, or the shape (plan 002 owns the shape).
- Do NOT add dependencies.
- If a quoted excerpt doesn't match the file (line drift is fine, different code is not), STOP and report.

## Verification

- **Mechanical**: `cd "/Users/bt/Desktop/The BT Std./Dev/Skies" && xcodebuild -scheme Skies -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **` with no new warnings in `Skies/`; then `xcodebuild -scheme Skies -destination 'platform=macOS' test` → 15 tests pass. Build into default DerivedData (never `-derivedDataPath` under ~/Desktop).
- **Feel check** (on the MacBook, real notch):
  - Press ⌃⌥S: the black shape grows out of the notch, overshoots slightly past its final size and settles once, in about half a second. The content arrives a beat after the shape and also settles from slightly smaller, never fading in a bouncing way.
  - Press ⌃⌥S again immediately while it's still opening: it reverses smoothly from where it is, with no jump or restart.
  - Esc: content disappears first, then the shape tucks back into the notch, faster than it opened and with barely any bounce.
  - Clicks land on tiles while the open is still springing.
  - Screen-record at 120 fps (⇧⌘5) and step through: the shape leads, content follows ~60 ms later.
  - System Settings › Accessibility › Display › Reduce Motion on: open/close are a short fade-and-resize with no overshoot and no content scale.
- **Done when**: all of the above hold and the build/tests pass.
