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
| 2026-02-11 | me | Ran `ls` before reading `.claude/napkin.md` at session start. | Read the napkin before any other command in a new session. |
| 2026-02-11 | me | Used `z.record(z.any())` with Zod v4 and hit a TS overload error. | Use `z.record(z.string(), z.any())` for passthrough maps. |
| 2026-02-11 | me | Used `process.chdir()` inside Vitest tests, which fails in worker threads. | Avoid `process.chdir()` in Vitest; create fixtures under the repo/root or run tests in forks/single-thread mode. |
| 2026-02-11 | me | Added a mutable static test override in a nonisolated type, triggering Swift concurrency-safety errors. | Prefer environment-driven overrides or isolate overrides on an actor to satisfy concurrency rules. |
| 2026-02-11 | me | Put `ConversationStore.overrideHistoryDirectory` behind `#if DEBUG`, which broke `swift test -c release` compilation. | Keep test hooks needed by test targets compiled in release too, or gate tests and hooks consistently. |
| 2026-02-11 | me | Left GitHub macOS workflows on `macos-latest` while code used macOS 26 Speech APIs unavailable on the macOS 15 image. | Pin workflows to `macos-26` when builds depend on macOS 26 SDK/runtime features. |
| 2026-02-11 | me | Switched to `.macOS(.v26)` in `Package.swift` without bumping tools version, causing manifest parse failures. | Use `// swift-tools-version: 6.2` (or newer) when targeting `.macOS(.v26)` in SwiftPM manifests. |
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
- If using `EKEventStore.requestFullAccessToReminders()`, include `NSRemindersFullAccessUsageDescription` in `Flux/Info.plist` or macOS will terminate the app at runtime.
- For closed-island background activity indicators, emit explicit sidecar run lifecycle events (e.g. `run_status` true/false) and drive Swift UI from `AgentBridge.isAgentWorking` instead of inferring from hover/tool-call UI state.
- Keep closed-island activity robust with multiple signals: sidecar `run_status`, `stream_chunk`/`tool_use_*` tracking in `AgentBridge`, plus a UI fallback for any pending tool calls in `ConversationStore`.
- If closed-island activity still doesn’t render, derive “working” from three independent paths in UI state: bridge run/tool/stream activity, pending tool calls, and whether the active conversation has a newer user message than assistant message.
- In the closed island, center-clustered icons can look missing; pin activity sparkle to the left edge and the task icon to the right edge for unmistakable visibility.
- For closed notch layouts that rely on `Spacer()`, use fixed `frame(width:height:)` on the container instead of `maxWidth/maxHeight`; otherwise the view can collapse to intrinsic width and edge indicators appear missing.
- For closed-notch activity affordances, use explicit left/right slot widths (not spacer distribution) so status icons remain visible whenever the island widens.
- For closed-island activity UI, keep an independent `ConversationStore` run-state flag (started on send, updated by stream/run-status callbacks) and OR it with bridge state so indicators survive dropped/late WebSocket lifecycle events.
- In animating notch UIs, pin closed-header content to `.top` during expand/collapse transitions; centered stacks make indicators appear too low and only visible during a brief morph frame.
- Add a short visibility latch (~1.5s) for closed-state activity indicators so transient state flips do not cause one-frame flashes.
- For a global "hold fn" gesture on macOS, listen to `.flagsChanged`, check `.function` in modifier flags, and gate with a `wasPressed` latch so the action fires once per hold.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- (project/domain context that matters)
- `read_ax_tree` is frontmost-window-only, so it can miss user-visible context outside Flux itself.
