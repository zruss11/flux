# Flux ⚡

**AI Desktop Copilot for macOS** — sees your screen, hears your voice, builds custom tools.

A native macOS app with a Dynamic Island-style notch overlay powered by Claude and Liquid Glass.

## Features

### 🖥️ Screen-Aware AI
Reads window contents via Accessibility API and captures screenshots via ScreenCaptureKit. No OCR, no guessing — actual structured data from any app.

### 🎙️ Advanced Voice Input
Multiple speech-to-text engines with intelligent post-processing:
- **Apple Speech** — Built-in on-device transcription via `SFSpeechRecognizer`
- **Parakeet TDT v3** — NVIDIA's 0.6B parameter on-device model via CoreML for higher accuracy (~6 GB download, cached locally)
- **Deepgram** — Cloud-based live streaming transcription with API key
- **Post-Processing Pipeline** — Multi-stage transcript cleanup: fragment repair (`"wan- want"` → `"want"`), intent correction (`"wait, actually..."` handling), number conversion (`"twenty three"` → `"23"`), and repeat removal
- **Live Transcript Dropdown** — Real-time transcription text displayed below the notch as you speak, with Liquid Glass styling

### 🏝️ Dynamic Island UI
Notch-anchored overlay with Liquid Glass materials. Expands contextually, stays out of your way.
- **CI Status Chips** — Aggregate CI/build health from watched repos with popover details and quick actions
- **Watcher Alert Chips** — Notification alerts with priority levels and management options
- **CI Ticker Notifications** — Animated ticker bar for CI status transitions (e.g., failing → passing)
- **Git Branch Pill** — View and switch branches via a searchable popover, right from the chat UI

### 🔧 Custom Tool Builder
Create AI-powered tools that combine LLM prompts with Shortcuts, shell scripts, and custom instructions. Tools require explicit user approval for dangerous operations (`rm`, destructive `git` commands).

### 🧠 Claude Agent SDK
Powered by Claude Sonnet with custom tools for screen capture, file ops, and automation.
- **Session Forking** — Branch any conversation into an independent fork to explore alternatives without losing context
- **Slash Commands** — Type `/` to access built-in commands (`/new`, `/clear`, `/compact`, `/help`, `/cost`) and custom commands from `.claude/commands/`
- **Tool Approval UI** — In-chat permission cards for risky operations with Allow/Deny actions and clarifying questions

### 👁️ Watchers
Background monitors that poll external sources (email, repos, etc.) and route alerts into a dedicated Island conversation. Hardened with sendable state, bounded scheduling, stable digest-based dedupe, and lifecycle cleanup.

### ⚙️ Developer Experience
- **Editable Workspace Path** — Click the breadcrumb path to type or paste any directory
- **Onboarding Flow** — Full-size content window with live permission state, themed visuals, and one-click restart

## Requirements

- macOS 26 (Tahoe)
- Apple Silicon Mac with notch
- Node.js 20+
- Anthropic API key
- Deepgram API key *(optional, for Deepgram STT)*

## Quick Start

```bash
# Clone
git clone https://github.com/zruss11/flux.git
cd flux

# Build the app
xcodebuild -scheme Flux -configuration Debug build

# Start the AI sidecar
cd sidecar && npm install && npm start
```

Or use the conductor scripts:

```bash
./scripts/conductor-setup.sh   # bootstrap environment
./scripts/conductor-run.sh     # launch app
```

## Testing

```bash
# Swift tests
swift test --package-path Flux

# Sidecar tests
cd sidecar && npm install && npm test
```

## Releasing signed DMGs

GitHub Actions workflow: `.github/workflows/release.yml`

Required repository secrets:
- `APPLE_CERTIFICATE_P12_BASE64` — base64-encoded Developer ID Application certificate (`.p12`)
- `APPLE_CERTIFICATE_PASSWORD` — password for that `.p12`
- `APPLE_SIGNING_IDENTITY` (optional) — explicit signing identity name; if omitted, first Developer ID Application identity is used
- `APPLE_API_KEY_ID` — App Store Connect API key ID
- `APPLE_API_ISSUER_ID` — App Store Connect issuer ID
- `APPLE_API_PRIVATE_KEY_BASE64` — base64-encoded private key (`AuthKey_*.p8`)

Create a tag to release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Or run manually with `workflow_dispatch` and provide a tag.

Release assets include:
- `flux-<version>.dmg`
- `flux-<version>.dmg.sha256`
- `sidecar-dist.tgz`

## Architecture

```
┌──────────────────────────────────────────┐
│          Flux (Swift/SwiftUI)            │
│                                          │
│  ┌──────────┐  ┌───────────────────────┐ │
│  │ Island   │  │   Screen Context      │ │
│  │   UI     │  │   • AXUIElement       │ │
│  │ (notch)  │  │   • ScreenCapture     │ │
│  │          │  │   • Selection          │ │
│  │ • CI     │  └───────────┬───────────┘ │
│  │   chips  │              │             │
│  │ • ticker │  ┌───────────┴───────────┐ │
│  │ • branch │  │   Voice Input         │ │
│  │   pill   │  │   • Apple Speech      │ │
│  │ • live   │  │   • Parakeet TDT v3   │ │
│  │   trans. │  │   • Deepgram Stream   │ │
│  │ • alerts │  │   • Post-Processing   │ │
│  └────┬─────┘  └───────────┬───────────┘ │
│       │                    │             │
│       └────────┬───────────┘             │
│                │ WebSocket               │
│       ┌────────▼────────────┐            │
│       │   Agent Bridge      │            │
│       │   • Tool Approval   │            │
│       │   • Session Forking │            │
│       │   • Slash Commands  │            │
│       └────────┬────────────┘            │
│                │              ┌────────┐ │
│                │              │Watchers│ │
│                │              │ Engine │ │
│                │              └────────┘ │
└────────────────┼─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│       Sidecar (Node.js/TypeScript)       │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │     Claude Agent SDK               │  │
│  │     (Sonnet + Custom Tools)        │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

## License

Apache 2.0
