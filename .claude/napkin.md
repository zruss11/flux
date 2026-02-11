# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-02-10 | me | Ran git commands despite an attached review brief saying the full diff/history was already provided. | When a review request includes the full diff/log, review directly from that artifact unless explicitly asked to re-run git commands. |
| 2026-02-11 | me | Used `security find-identity` without limiting keychains in `scripts/dev.sh`, which can trigger repeated admin-password prompts for the System keychain. | Only search user keychains (for example via `security list-keychains -d user`) or require an explicit `FLUX_CODESIGN_IDENTITY`. |
| 2026-02-11 | me | Used Bash 4-only `mapfile` in a script that may run under macOS's default Bash 3.2. | Use a `while IFS= read -r ...` loop (Bash 3.2-compatible) or explicitly depend on a newer Bash. |
| 2026-02-11 | me | Accidentally used `require()` inside an ESM TypeScript module (`sidecar/src/skills/loadInstalledSkills.ts`). | In ESM, use `import` and async `fs.stat`/`fs.access` checks instead of `require()`. |
| 2026-02-11 | me | Posted an in-progress status update in the `final` channel before work was complete. | Use `commentary` for progress updates and reserve `final` for the end-of-turn results summary. |
| 2026-02-11 | me | Typed a Unicode comparison symbol (`≥`) in source while editing AppleScript in Swift raw strings. | Keep source edits ASCII-only unless Unicode is explicitly required; use `>=` style operators in embedded scripts. |
| 2026-02-11 | me | Used `>=` inside AppleScript and caused parse errors (`Expected end of line but found identifier`). | In AppleScript use textual comparisons (`is greater than or equal to`) or valid AppleScript operators. |
| 2026-02-11 | user | Needed to keep working on existing branch `zruss11/all-window-context`, but I renamed away from it. | Keep the current task branch stable when user says to continue existing work; only rename when explicitly needed. |
| 2026-02-11 | me | Announced that I was using/reading the napkin skill in user-facing status text. | Apply napkin silently; do not mention reading it in updates. |
| 2026-02-11 | me | Added block-based NotificationCenter observer on a `@MainActor` app delegate and hit Swift 6 Sendable/data-race compiler errors. | Prefer selector-based observers (or main-actor isolated async hops) when notification payloads would otherwise cross actor boundaries unsafely. |

## User Preferences
- (accumulate here as you learn them)
- For screen understanding, prefer global visible-window context instead of only frontmost-window AX tree when the task involves multiple apps/windows.
- In UI copy, label scheduled work as "Automations" and avoid "cron/crons" wording.
- Automation runs should live in dedicated chat threads, with thread targeting implicit in the UI.

## Patterns That Work
- For new agent tools, add the tool definition in `sidecar/src/tools/index.ts` and implement the matching `toolName` case in `Flux/Sources/FluxApp.swift`'s `handleToolRequest` switch.
- For lightweight macOS tooltips in SwiftUI settings, attach `.help("...")` to an `Image(systemName: "info.circle")` in the row trailing UI.
- Store third-party bot tokens in macOS Keychain (not `UserDefaults`), and migrate/remove any legacy `UserDefaults` values at app launch.
- For SpriteKit inside a SwiftUI `SpriteView` hosted in a non-activating `NSPanel`, don't rely on the per-frame `update(_:)` loop or off-screen spawn; spawn nodes within visible bounds in `didMove`/`didChangeSize` so content renders even if physics/time is throttled.
- For `AVAudioNode.installTap(...)` used from a `@MainActor` type, build the tap block in a `nonisolated` helper. Otherwise the closure inherits `@MainActor` isolation and can SIGTRAP on macOS 26 when CoreAudio invokes it off-main.
- Telegram DM pairing state is shared via `~/.flux/telegram/pairing.json` so both Swift and the sidecar can read/write approvals.
- For `capture_screen` results in the Anthropic conversation loop, send image payloads as tool-result image blocks (`source: {type: 'base64', media_type, data}`) rather than raw base64 text to avoid token-limit failures.
- For recurring agent workflows, implement persistence/scheduling in a dedicated Swift service and expose CRUD/run controls via sidecar tool definitions + matching `FluxApp` tool handlers.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- (project/domain context that matters)
- `read_ax_tree` is frontmost-window-only, so it can miss user-visible context outside Flux itself.
