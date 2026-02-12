---
status: pending
priority: p2
issue_id: "001"
tags: [screen-capture, caret-highlight]
dependencies: []
---

# Fix caret highlight coordinates on non-origin displays

## Problem Statement

Caret highlighting for `capture_screen` window captures miscomputes the window bounds on multi-monitor layouts where the display origin is not `(0,0)`. This offsets the red rectangle so it renders off-image (or not at all) for windows on secondary screens above/below or left/right of the primary display.

## Findings

- `windowFrameToScreenCoords` in `Flux/Sources/Services/ScreenCapture.swift` flips Y using `screen.frame.height` but never subtracts `screen.frame.origin`.
- `windowFrame.origin` is in global screen coordinates, so on displays with a non-zero origin the conversion yields a negative/incorrect Y (and X) value.
- `annotateImage` clamps the rect to the captured image and returns the unmodified image when the rect is outside bounds, so the highlight silently disappears on those displays.

## Proposed Solutions

### Option 1: Adjust bounds conversion to account for screen origin (preferred)

**Approach:** Compute the top-left coordinate using `screen.frame.maxY` and subtract `screen.frame.origin.x`/`origin.y` when converting `windowFrame` to display-local coordinates before flipping.

**Pros:**
- Minimal change localized to `windowFrameToScreenCoords`.
- Keeps existing caret mapping logic intact.

**Cons:**
- Still relies on converting to top-left coordinates, which may be confusing to maintain.

**Effort:** 1-2 hours

**Risk:** Low

---

### Option 2: Keep bounds in global (bottom-left) coords and convert caret rect instead

**Approach:** Leave `window.frame` in its original coordinate space and convert the caret rect to the same space inside `annotateImage` before subtracting origins.

**Pros:**
- Eliminates implicit coordinate flips.
- Makes the mapping step explicit.

**Cons:**
- Slightly more refactor work.

**Effort:** 2-3 hours

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `Flux/Sources/Services/ScreenCapture.swift` (`windowFrameToScreenCoords` and caret highlight mapping)

**Related components:**
- `AccessibilityReader.getCaretBounds()`
- `capture_screen` tool handler in `FluxApp.swift`

## Resources

- **PR:** caret highlight feature branch
- **Code:** `windowFrameToScreenCoords` in `ScreenCapture.swift`

## Acceptance Criteria

- [ ] Caret highlight renders correctly for windows on displays with non-zero origins (above/below/left of primary)
- [ ] Caret highlight still renders correctly on the primary display
- [ ] No regressions for display capture annotations

## Work Log

### 2026-02-11 - Initial Discovery

**By:** Claude Code

**Actions:**
- Reviewed caret highlight diff and identified coordinate conversion bug
- Documented multi-monitor reproduction scenario and mitigation options

**Learnings:**
- Screen coordinate conversions must account for `NSScreen.frame.origin`

## Notes

- Add a quick manual test by placing a window on a secondary display and enabling `highlight_caret`.
