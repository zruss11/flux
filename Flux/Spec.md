# Flux — Product Specification

## Product Vision

Flux is a macOS-native AI desktop copilot that lives in a Dynamic Island-style notch overlay. It sees your screen (via Accessibility APIs and ScreenCaptureKit), hears your voice (via Apple Speech framework), and lets you build custom AI-powered tools — all from a glass capsule anchored to the MacBook notch.

**Target User:** Power users and developers who want AI assistance directly integrated into their desktop workflow.

**Target Platform:** macOS 26 (Tahoe)

### UX Principles

- **Always accessible** — one click on the notch capsule
- **Non-intrusive** — doesn't steal focus or cover content unless expanded
- **Context-aware** — automatically understands what's on screen via AX tree + screenshots
- **Extensible** — users create custom tools with no code using a visual builder

---

## Feature Matrix

| Feature | Technology | Description |
|---------|-----------|-------------|
| Screen Capture | AXUIElement + ScreenCaptureKit | Read window contents as structured text; capture screenshots as images |
| Voice Input | SFSpeechRecognizer + AVAudioEngine | Record audio, transcribe locally, send to chat |
| Chat Interface | SwiftUI + WebSocket streaming | Real-time conversation with Claude, streamed responses |
| Custom Tools | JSON schema + template variables | User-defined tools with prompts, variables, and actions |
| Tool Execution | Shortcuts, shell, AppleScript, Claude | Execute actions from custom tools |
| Onboarding | Permission wizard | Guides users through granting Accessibility, Screen Recording, Microphone |

---

## Architecture

```
┌──────────────────────────────┐     WebSocket      ┌─────────────────────────┐
│       Swift App (Main)       │◄──────────────────►│   Node.js Sidecar       │
│                              │   ws://localhost:   │                         │
│  ┌─────────────────────┐     │       3000          │  ┌───────────────────┐  │
│  │ IslandView (SwiftUI) │     │                     │  │ Claude Agent SDK  │  │
│  │ - Liquid Glass       │     │                     │  │ (@anthropic-ai/   │  │
│  │ - Chat UI            │     │                     │  │  sdk)             │  │
│  │ - Tool Builder       │     │                     │  └───────────────────┘  │
│  └─────────────────────┘     │                     │                         │
│                              │                     │  ┌───────────────────┐  │
│  ┌─────────────────────┐     │                     │  │ Tool Definitions  │  │
│  │ Services             │     │                     │  │ - capture_screen  │  │
│  │ - AccessibilityReader│     │                     │  │ - read_ax_tree    │  │
│  │ - ScreenCapture      │     │                     │  │ - read_selected   │  │
│  │ - VoiceInput         │     │                     │  │ - applescript     │  │
│  │ - AgentBridge        │     │                     │  │ - shell_command   │  │
│  │ - ToolRunner         │     │                     │  └───────────────────┘  │
│  └─────────────────────┘     │                     │                         │
└──────────────────────────────┘                     └─────────────────────────┘
```

### Swift App (Main Process)
- **SwiftUI + AppKit** for UI
- **NSPanel** for the Dynamic Island overlay (non-activating, above all windows)
- **Liquid Glass** (`.glassEffect`) for overlay materials on macOS 26
- **AXUIElement** for reading window contents (primary context source)
- **ScreenCaptureKit** for screenshots (supplementary context)
- **SFSpeechRecognizer** for voice transcription
- **URLSessionWebSocketTask** for communication with sidecar

### Node.js Sidecar (Agent Process)
- **Anthropic SDK** (`@anthropic-ai/sdk`) for Claude API
- **WebSocket server** (`ws`) for bidirectional communication
- **Tool definitions** sent to Claude for tool-use conversations
- **Per-conversation message history** for context continuity

---

## API Contracts

### WebSocket JSON Protocol

**Swift → Node:**
```json
// Send a chat message
{ "type": "chat", "conversationId": "uuid", "content": "What's on my screen?" }

// Return a tool execution result
{ "type": "tool_result", "conversationId": "uuid", "toolUseId": "toolu_xxx", "toolName": "read_ax_tree", "toolResult": "{...}" }
```

**Node → Swift:**
```json
// Complete assistant response
{ "type": "assistant_message", "conversationId": "uuid", "content": "Here's what I see..." }

// Request tool execution from Swift
{ "type": "tool_request", "conversationId": "uuid", "toolUseId": "toolu_xxx", "toolName": "capture_screen", "input": { "target": "window" } }

// Streaming text chunk
{ "type": "stream_chunk", "conversationId": "uuid", "content": "Here's" }
```

### Tool Schema (Custom Tools)
```json
{
  "name": "Summarize Page",
  "icon": "doc.text.magnifyingglass",
  "description": "Capture screen and summarize visible content",
  "prompt": "Summarize what's on screen: {{screen}}",
  "variables": ["screen", "clipboard", "selected_text"],
  "actions": [
    { "type": "shortcut", "name": "My Shortcut" },
    { "type": "shell", "script": "echo 'done'" },
    { "type": "applescript", "script": "tell app \"Notes\" to ..." },
    { "type": "claude", "instructions": "Analyze and summarize" }
  ],
  "trigger": { "type": "hotkey", "keys": "cmd+shift+s" }
}
```

### AX Tree Format
```json
{
  "role": "AXWindow",
  "title": "My Document",
  "value": null,
  "description": null,
  "children": [
    {
      "role": "AXGroup",
      "title": null,
      "value": null,
      "description": "toolbar",
      "children": [
        { "role": "AXButton", "title": "Save", "value": null, "description": null, "children": null }
      ]
    }
  ]
}
```

---

## Permission Model

| Permission | API | Purpose |
|-----------|-----|---------|
| Accessibility | `AXIsProcessTrustedWithOptions` | Read window contents (AX tree), selected text |
| Screen Recording | `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` | Capture screenshots |
| Microphone | `AVCaptureDevice.requestAccess(for: .audio)` | Voice input recording |

All permissions are requested during onboarding. The app polls for status changes after the user grants each permission in System Settings.

---

## Data Storage

| Data | Location | Format |
|------|----------|--------|
| Custom tools | `~/.flux/tools/{uuid}.json` | JSON (CustomTool schema) |
| App settings | `UserDefaults` | Key-value |
| API key | Keychain (via `SecureField`) | Encrypted |
| Conversations | In-memory | Not persisted between sessions |

---

## Build & Run

```bash
# Build and run Swift app
cd Flux && swift build
# Or with Xcode
xcodebuild -scheme Flux -configuration Debug build

# Install and start Node sidecar
cd sidecar && npm install && npm start
```

Both processes must be running for full functionality. The Swift app will attempt to connect to the sidecar's WebSocket server on launch and reconnect with exponential backoff if the connection is lost.
