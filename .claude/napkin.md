# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-02-10 | me | Ran git commands despite an attached review brief saying the full diff/history was already provided. | When a review request includes the full diff/log, review directly from that artifact unless explicitly asked to re-run git commands. |
| 2026-02-11 | me | Posted an in-progress status update in the `final` channel before work was complete. | Use `commentary` for progress updates and reserve `final` for the end-of-turn results summary. |

## User Preferences
- (accumulate here as you learn them)

## Patterns That Work
- For new agent tools, add the tool definition in `sidecar/src/tools/index.ts` and implement the matching `toolName` case in `Flux/Sources/FluxApp.swift`'s `handleToolRequest` switch.
- For lightweight macOS tooltips in SwiftUI settings, attach `.help("...")` to an `Image(systemName: "info.circle")` in the row trailing UI.
- Store third-party bot tokens in macOS Keychain (not `UserDefaults`), and migrate/remove any legacy `UserDefaults` values at app launch.
- For `AVAudioNode.installTap(...)` used from a `@MainActor` type, build the tap block in a `nonisolated` helper. Otherwise the closure inherits `@MainActor` isolation and can SIGTRAP on macOS 26 when CoreAudio invokes it off-main.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- (project/domain context that matters)
