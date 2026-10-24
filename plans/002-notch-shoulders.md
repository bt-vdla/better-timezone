# 002 — Curve the panel's top edges into the screen like the real notch

- **Status**: DONE
- **Commit**: a7ec9b5 (plus uncommitted `Skies/Notch.swift`, staged; it must exist before executing)
- **Severity**: MEDIUM
- **Category**: Physicality & origin
- **Estimated scope**: 1 file (`Skies/Notch.swift`), ~45 lines (one new `Shape`, three call sites)

## Problem

The panel is a rectangle with a flat top and rounded bottom corners. The MacBook's hardware
notch (and Alcove's panel) instead **flares into the top edge of the screen**: each top corner
is a concave curve, so the black shape looks like it pours out of the bezel instead of being a
box stuck under the menu bar. Without the flare, the closed shape's square top corners also
show as a hard step beside the hardware notch.

```swift
// Skies/Notch.swift:249-266 — current
let radius: CGFloat = state.shapeOpen ? 26 : min(10, closed.height / 2)

ZStack(alignment: .top) {
    UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        .fill(.black)
        .frame(width: size.width, height: size.height)
        // … two overlays …
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
}
```

## Target

A custom animatable `NotchShape` with two radii:

- `top`: the concave flare at each top corner. The shape is `2 × top` wider than its visible body,
  and the extra width curves outward into the screen edge.
- `bottom`: the convex rounding at the two bottom corners.

| State | `top` | `bottom` |
| --- | --- | --- |
| Closed (resting on the notch) | `6` | `min(10, height / 2)` |
| Open | `14` | `26` |

Both radii animate with whatever transaction changes `state.shapeOpen` (the springs from plan 001,
if that has landed), so the flare grows as the panel opens.

Path, for a rect of width `w`, height `h`, with `t = top`, `b = bottom`:

1. Start at `(0, 0)`.
2. Concave curve into the body: quad curve to `(t, t)` with control point `(t, 0)`.
3. Straight down the left side to `(t, h - b)`.
4. Bottom-left corner: quad curve to `(t + b, h)` with control `(t, h)`.
5. Along the bottom to `(w - t - b, h)`.
6. Bottom-right corner: quad curve to `(w - t, h - b)` with control `(w - t, h)`.
7. Up the right side to `(w - t, t)`.
8. Concave flare out: quad curve to `(w, 0)` with control `(w - t, 0)`.
9. Close.

## Repo conventions to follow

- Shapes in this project are SwiftUI `Shape`s used with `.fill` and `.clipShape`; follow the existing
  `UnevenRoundedRectangle(..., style: .continuous)` usage it replaces.
- Doc comments use `///` and state the why (see `Skies/Notch.swift:66-74`, `NotchState`).
- macOS-only code lives inside the file's `#if os(macOS)` block (already true for all of `Notch.swift`).

## Steps

1. In `Skies/Notch.swift`, just above `struct NotchView: View {` (line ~232), add:
   ```swift
   /// The notch's own silhouette: concave shoulders that flare into the screen's top edge, rounded
   /// bottom corners. It is `2 × top` wider than its body; the extra width is the flare.
   struct NotchShape: Shape {
       var top: CGFloat
       var bottom: CGFloat

       var animatableData: AnimatablePair<CGFloat, CGFloat> {
           get { AnimatablePair(top, bottom) }
           set { top = newValue.first; bottom = newValue.second }
       }

       func path(in rect: CGRect) -> Path {
           let w = rect.width, h = rect.height
           let t = min(top, w / 4, h), b = min(bottom, (w - 2 * t) / 2, h - t)
           var p = Path()
           p.move(to: CGPoint(x: 0, y: 0))
           p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
           p.addLine(to: CGPoint(x: t, y: h - b))
           p.addQuadCurve(to: CGPoint(x: t + b, y: h), control: CGPoint(x: t, y: h))
           p.addLine(to: CGPoint(x: w - t - b, y: h))
           p.addQuadCurve(to: CGPoint(x: w - t, y: h - b), control: CGPoint(x: w - t, y: h))
           p.addLine(to: CGPoint(x: w - t, y: t))
           p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
           p.closeSubpath()
           return p.offsetBy(dx: rect.minX, dy: rect.minY)
       }
   }
   ```
2. In `NotchView.body`, replace
   ```swift
   let radius: CGFloat = state.shapeOpen ? 26 : min(10, closed.height / 2)
   ```
   with
   ```swift
   let flare: CGFloat = state.shapeOpen ? 14 : 6
   let radius: CGFloat = state.shapeOpen ? 26 : min(10, closed.height / 2)
   let shape = NotchShape(top: closed.height == 0 && !state.shapeOpen ? 0 : flare, bottom: radius)
   ```
3. Widen the drawn size by the flare on both sides so the **body** keeps today's width (the body must
   still exactly cover the hardware notch when closed). Replace
   ```swift
   let size = state.shapeOpen ? CGSize(width: openWidth, height: openHeight) : closed
   ```
   with
   ```swift
   let body = state.shapeOpen ? CGSize(width: openWidth, height: openHeight) : closed
   let size = CGSize(width: body.width + (body.width == 0 ? 0 : 2 * (state.shapeOpen ? 14 : 6)), height: body.height)
   ```
   (`size` is then used, unchanged, by the existing `.frame(width: size.width, height: size.height)`.)
4. Replace the fill and the clip:
   - `UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous).fill(.black)` → `shape.fill(.black)`
   - `.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))` → `.clipShape(shape)`
5. Leave the overlays (ears, content) alone: they're centred with `alignment: .top`, so a shape that's
   wider only by the symmetric flare keeps them centred over the body.

## Boundaries

- Do NOT touch anything outside `Skies/Notch.swift`.
- Do NOT change animations or timings (plan 001 owns those); the radii simply ride the existing transaction.
- Do NOT change `NotchController.size` (780 × 280); the open body (`openWidth` + 28) still fits inside it.
- If a quoted excerpt doesn't match the file, STOP and report.

## Verification

- **Mechanical**: `cd "/Users/bt/Desktop/The BT Std./Dev/Skies" && xcodebuild -scheme Skies -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`, no new warnings in `Skies/`; `xcodebuild -scheme Skies -destination 'platform=macOS' test` → 15 tests pass. Default DerivedData only.
- **Visual check** (MacBook with a notch): launch the debug build with
  `open <DerivedData>/Build/Products/Debug/Skies.app --args -SkiesOpenNotch YES`, then capture the top of
  the screen with `screencapture -x -R 0,0,1512,330 top.png` and zoom into the panel's top corners:
  - Both top corners curve **outward** into the screen edge (concave), with no square step.
  - The bottom corners stay round.
  - The panel's content is still centred and nothing is clipped by the flare.
- **Feel check**:
  - Open and close with ⌃⌥S: the shoulders grow from a small flare (6 pt) to a larger one (14 pt) as the
    panel opens, and shrink back as it closes, in step with the shape (no lag, no pop at the end).
  - When the countdown ears show beside the closed notch, the widened closed shape has the same small
    flare, and its body lines up with the hardware notch's edges.
  - At 120 fps screen recording, step through an open: the flare never inverts or spikes mid-animation.
- **Done when**: the corners match the hardware notch's silhouette closed and open, and build/tests pass.
