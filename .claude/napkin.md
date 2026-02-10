# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|

## User Preferences
- (accumulate here as you learn them)

## Patterns That Work
- For new agent tools, add the tool definition in `sidecar/src/tools/index.ts` and implement the matching `toolName` case in `Flux/Sources/FluxApp.swift`'s `handleToolRequest` switch.
- For lightweight macOS tooltips in SwiftUI settings, attach `.help("...")` to an `Image(systemName: "info.circle")` in the row trailing UI.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- (project/domain context that matters)
