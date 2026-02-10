# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-02-10 | me | Ran git commands despite an attached review brief saying the full diff/history was already provided. | When a review request includes the full diff/log, review directly from that artifact unless explicitly asked to re-run git commands. |

## User Preferences
- (accumulate here as you learn them)

## Patterns That Work
- For new agent tools, add the tool definition in `sidecar/src/tools/index.ts` and implement the matching `toolName` case in `Flux/Sources/FluxApp.swift`'s `handleToolRequest` switch.
- For lightweight macOS tooltips in SwiftUI settings, attach `.help("...")` to an `Image(systemName: "info.circle")` in the row trailing UI.
- Store third-party bot tokens in macOS Keychain (not `UserDefaults`), and migrate/remove any legacy `UserDefaults` values at app launch.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- (project/domain context that matters)
