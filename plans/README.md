# Animation plans

Written by `improve-animations` against commit `a7ec9b5` plus the staged, uncommitted `Skies/Notch.swift`.
Each plan is self-contained; execute in order.

| # | Plan | Severity | Status |
| --- | --- | --- | --- |
| 001 | [Bouncy, fluid notch open and close](001-notch-bouncy-spring.md) | HIGH | DONE |
| 002 | [Notch-shaped top edges](002-notch-shoulders.md) | MEDIUM | DONE |

## Order and dependencies

1. **001 first.** It sets the springs that the shape's radii ride on.
2. **002 second.** It only changes the shape; its corner radii animate with whatever transaction 001
   uses. It works on its own too, but the feel check assumes 001 is in.

Both touch only `Skies/Notch.swift`, so run them one after the other, not in parallel.
