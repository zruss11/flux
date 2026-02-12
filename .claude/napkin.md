# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-02-12 | me | Ran `git status` before reading `.claude/napkin.md` at session start. | Read the napkin first in each fresh session before any other command. |
| 2026-02-12 | me | Mentioned loading internal skills in a user-facing status update. | Keep progress updates focused on technical work only; do not mention internal skill handling. |
| 2026-02-12 | me | Referred to the napkin/skills workflow in a user-facing progress update again. | Keep user-facing updates purely technical and never mention internal skill bookkeeping. |
| 2026-02-12 | me | Mentioned using the napkin/skills flow in a user-facing progress update again. | Keep napkin and skill-internal workflow references out of user-facing commentary; just report technical progress. |
| 2026-02-12 | me | Ran `log show ...` and hit zsh parsing (`zsh:log:1: too many arguments`) because shell resolved `log` unexpectedly. | Use `/usr/bin/log ...` explicitly for macOS unified logging commands in this repo automation environment. |
| 2026-02-12 | me | Added a `DispatchSourceTimer` event handler for `@MainActor` state on a global queue, causing runtime `dispatch_assert_queue_fail` and app crash at launch. | For actor-isolated state polling, run the dispatch source on `.main` (or use a nonisolated helper that never touches actor state off-actor). |
| 2026-02-12 | me | Switched hotkey dictation to batch Parakeet without first checking port allocation; transcriber and MCP bridge both targeted `127.0.0.1:7848`. | Before routing features to local services, verify runtime ports (`lsof` + repo defaults) and move conflicting services to dedicated ports. |
| 2026-02-12 | me | Mentioned reading/using the napkin flow in a user-facing progress update. | Apply napkin silently; never reference it in commentary/final responses. |
| 2026-02-12 | me | Ran `ls` before reading `.claude/napkin.md` at session start. | Read the napkin before any other command in a new session. |
| 2026-02-12 | me | Used Git pathspec-style exclude syntax in `rg` and got `No such file or directory` for `:(exclude).git`. | Use plain `rg` from repo root (or correct `--glob` excludes) instead of Git pathspec syntax. |
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
| 2026-02-11 | me | Mentioned using the napkin skill in a user-facing progress update. | Keep napkin usage silent; apply it without announcing the skill. |
| 2026-02-11 | me | Tried `npm run build` in `sidecar/` before dependencies were installed and hit `tsc: command not found`. | Run `npm install` in `sidecar/` first when validating TypeScript on a fresh workspace. |
| 2026-02-12 | me | Ran `ls .claude` before reading `.claude/napkin.md` at session start. | Read the napkin before any other command in a new session. |
| 2026-02-11 | me | Ran `git diff` before reading `.claude/napkin.md` at session start. | Read the napkin before any other commands in a new session. |
| 2026-02-12 | me | Ran `ls` before reading `.claude/napkin.md` at session start. | Read the napkin before any other commands in a new session. |
| 2026-02-12 | me | Mentioned napkin-reading activity in a user-facing progress update. | Keep napkin usage fully silent in commentary and apply it without announcing it. |
| 2026-02-12 | me | Used `find -maxdepth` and hit `fd` alias behavior (`unexpected argument '-m'`) in this shell setup. | Use `command find` (or absolute `/usr/bin/find`) when POSIX `find` flags are required. |

## User Preferences
- (accumulate here as you learn them)
- For screen understanding, prefer global visible-window context instead of only frontmost-window AX tree when the task involves multiple apps/windows.
- In UI copy, label scheduled work as "Automations" and avoid "cron/crons" wording.
- Automation runs should live in dedicated chat threads, with thread targeting implicit in the UI.

## Patterns That Work
- For new agent tools, add the tool definition in `sidecar/src/tools/index.ts` and implement the matching `toolName` case in `Flux/Sources/FluxApp.swift`'s `handleToolRequest` switch.
- For GitHub macOS release automation, `apple-actions/import-codesign-certs@v3` + `xcrun notarytool submit --wait` + `xcrun stapler` is a straightforward path for signed/notarized DMG releases.
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
- For global hold-to-dictate shortcuts (`Cmd+Option`), pair `.flagsChanged` with a `CGEventSource.flagsState(.combinedSessionState)` timer failsafe; missed modifier-up events can leave audio capture running.
- For modifier hold gestures on background apps, add an independent `DispatchSourceTimer` polling `CGEventSource.flagsState(.combinedSessionState)` to drive press/release transitions; AppKit monitor callbacks alone can miss state changes.
- For hold-to-dictate while Flux is backgrounded, prefer batch on-device Apple Speech transcription mode over live `SpeechTranscriber`; live speech results can be unreliable when the app is not frontmost.
- In sidecar session maps, tie idle timers to actual eviction (not just ending streams) and clean up related Telegram/pending-tool state so long-lived processes do not leak memory.
- In `scripts/dev.sh`, copying only the executable into `Flux Dev.app` causes `Bundle.module` startup crashes; copy SwiftPM `*.bundle` resource directories from `Build/Products/Debug` into `Contents/Resources` as part of app install/update.
- Flux sidecar transcriber startup should check `http://127.0.0.1:7848/health` first and reuse existing listeners; otherwise stale/orphan listeners can trigger noisy `Errno 48` failures on launch.

## Patterns That Don't Work
- (approaches that failed and why)

## Domain Notes
- (project/domain context that matters)
- `read_ax_tree` is frontmost-window-only, so it can miss user-visible context outside Flux itself.
