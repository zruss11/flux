# Flux ⚡

**AI Desktop Copilot for macOS** — sees your screen, hears your voice, builds custom tools.

A native macOS app with a Dynamic Island-style notch overlay powered by Claude and Liquid Glass.

## Features

- 🖥️ **Screen-Aware AI** — Reads window contents via Accessibility API + captures screenshots via ScreenCaptureKit. No OCR, no guessing — actual structured data from any app.
- 🎙️ **Voice Input** — Local speech-to-text with Parakeet MLX. No API key, no cloud, runs entirely on Apple Silicon.
- 🔧 **Custom Tool Builder** — Create AI-powered tools that combine LLM prompts with Shortcuts, shell scripts, AppleScript, and custom instructions.
- 💬 **Multi-Channel** — Connect Discord, Slack, Telegram, WhatsApp so your AI copilot reaches you anywhere.
- 🏝️ **Dynamic Island UI** — Notch-anchored overlay with Liquid Glass materials. Expands contextually, stays out of your way.
- 🧠 **Claude Agent SDK** — Powered by Claude Sonnet with custom tools for screen capture, file ops, and automation.

## Requirements

- macOS 26 (Tahoe)
- Apple Silicon Mac with notch
- Node.js 20+
- Anthropic API key

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

## Architecture

```
┌─────────────────────────────────────┐
│         Flux (Swift/SwiftUI)        │
│                                     │
│  ┌─────────┐  ┌──────────────────┐  │
│  │ Island  │  │ Screen Context   │  │
│  │   UI    │  │ • AXUIElement    │  │
│  │ (notch) │  │ • ScreenCapture  │  │
│  │         │  │ • Selection      │  │
│  └────┬────┘  └────────┬─────────┘  │
│       │                │            │
│       └───────┬────────┘            │
│               │ WebSocket           │
│       ┌───────▼────────┐            │
│       │  Agent Bridge  │            │
│       └───────┬────────┘            │
└───────────────┼─────────────────────┘
                │
┌───────────────▼─────────────────────┐
│      Sidecar (Node.js/TypeScript)   │
│                                     │
│  ┌──────────────────────────────┐   │
│  │    Claude Agent SDK          │   │
│  │    (Sonnet + Custom Tools)   │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## Integrations

Connect Flux to your messaging platforms so your AI copilot can reach you anywhere.

- [Discord, Slack & Telegram Bot Setup Guide](docs/bot-setup.md)

## License

Apache 2.0
