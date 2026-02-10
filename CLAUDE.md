# CLAUDE.md — Flux

## Project
Flux is a macOS-native AI desktop copilot. It sees your screen, hears your voice, and lets you build custom AI-powered tools — all from a Dynamic Island-style notch overlay.

**Target:** macOS 26 (Tahoe)
**Language:** Swift (SwiftUI + AppKit)
**AI Backend:** Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`) via Node.js sidecar, Sonnet model
**License:** Apache 2.0

## Architecture

### Swift App (main process)
- Dynamic Island notch UI (SwiftUI + AppKit NSPanel)
- Liquid Glass (`.glassEffect`) for overlay materials
- ScreenCaptureKit for screenshots
- AXUIElement (Accessibility API) for reading window contents
- `parakeet-mlx` for local voice transcription
- Tool builder GUI + settings

### Node.js Sidecar (agent process)
- Claude Agent SDK with custom tools
- Communicates with Swift app via local WebSocket or Unix socket
- Custom tools: screen capture, AX tree read, file ops, run shortcuts, shell scripts, AppleScript

## Build & Run
```bash
# Swift app
xcodebuild -scheme Flux -configuration Debug build

# Node sidecar
cd sidecar && npm install && npm start
```

## Key APIs

### Context Capture (3 layers)
1. **AXUIElement** (primary) — reads actual text, buttons, labels, links from ANY window (AppKit, SwiftUI, Electron). Structured data, not OCR.
2. **ScreenCaptureKit** (supplementary) — visual screenshots for images, charts, canvas content
3. **Selected text** — what the user has highlighted, via AX API

### Liquid Glass (macOS 26)
```swift
// Basic glass effect
.glassEffect(.regular, in: .capsule)

// Interactive (scales, bounces, shimmers on press)
.glassEffect(.regular.interactive())

// Tinted for semantic meaning
.glassEffect(.regular.tint(.blue))

// Group multiple elements
GlassEffectContainer { ... }
```
Reference: https://github.com/conorluddy/LiquidGlassReference

### Custom Tools (JSON schema)
```json
{
  "name": "Summarize Page",
  "icon": "doc.text.magnifyingglass",
  "description": "Capture screen and summarize visible content",
  "prompt": "Summarize what's on screen: {{screen}}",
  "variables": ["screen", "clipboard", "selected_text"],
  "actions": [
    {"type": "shortcut", "name": "My Shortcut"},
    {"type": "shell", "script": "echo 'done'"},
    {"type": "applescript", "script": "tell app \"Notes\" to ..."},
    {"type": "claude", "instructions": "..."}
  ],
  "trigger": {"type": "hotkey", "keys": "cmd+shift+s"}
}
```
Tools stored in `~/.flux/tools/`

## Directory Structure
```
Flux/
├── Flux.xcodeproj/
├── Flux/
│   ├── FluxApp.swift              # App entry point
│   ├── Views/
│   │   ├── IslandView.swift        # Dynamic Island notch overlay
│   │   ├── ChatView.swift          # Conversation UI
│   │   ├── ToolBuilderView.swift   # Custom tool creator
│   │   ├── SettingsView.swift      # App settings + channel config
│   │   └── OnboardingView.swift    # Permissions wizard
│   ├── Models/
│   │   ├── Conversation.swift      # Chat message models
│   │   ├── Tool.swift              # Custom tool model
│   │   └── ScreenContext.swift     # AX tree + screenshot context
│   ├── Services/
│   │   ├── ScreenCapture.swift     # ScreenCaptureKit wrapper
│   │   ├── AccessibilityReader.swift # AXUIElement tree extraction
│   │   ├── VoiceInput.swift        # Parakeet MLX integration
│   │   ├── AgentBridge.swift       # WebSocket bridge to Node sidecar
│   │   └── ToolRunner.swift        # Execute shortcuts/scripts/applescript
│   └── Resources/
├── sidecar/
│   ├── package.json
│   ├── src/
│   │   ├── index.ts                # Agent SDK entry point
│   │   ├── tools/                  # Custom tool definitions
│   │   └── bridge.ts               # WebSocket server for Swift app
│   └── tsconfig.json
└── CLAUDE.md
```

## Conventions
- Swift: follow Apple's Swift style guide
- Use `@Observable` (macOS 14+) for state management
- Keep views small and composable
- Use async/await for all async work
- Node sidecar: TypeScript, ES modules

## Permissions Required
- **Accessibility** — for AXUIElement (reading window contents)
- **Screen Recording** — for ScreenCaptureKit (screenshots)
- **Microphone** — for voice input (Parakeet)

## Build Order
1. Xcode project skeleton + SwiftUI app shell
2. Dynamic Island notch UI (NSPanel anchored to notch, Liquid Glass)
3. AXUIElement tree extraction (read frontmost window contents)
4. ScreenCaptureKit integration (screenshot on demand)
5. Node.js sidecar with Claude Agent SDK + custom tools
6. WebSocket bridge between Swift app and sidecar
7. Chat UI in island overlay
8. Parakeet voice input (record → transcribe → send)
9. Tool builder GUI (create/edit/delete custom tools)
10. Tool execution engine (shortcuts, scripts, applescript)
11. Channel setup GUI (Discord/Slack/WhatsApp)
12. Onboarding flow (permissions wizard)
