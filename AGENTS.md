# AGENTS.md — Flux

## Project
Flux — a macOS-native AI desktop copilot with a Dynamic Island-style notch overlay. It captures screen context via Accessibility APIs and ScreenCaptureKit, processes it through Claude (Agent SDK), and lets users build custom AI-powered tools.

## Architecture
- **SwiftUI + AppKit** for macOS 26 (Tahoe)
- **Dynamic Island UI** anchored to MacBook notch (NSPanel)
- **Liquid Glass** (`.glassEffect`) for overlay materials
- **AXUIElement** for reading window contents (primary context)
- **ScreenCaptureKit** for screenshots (supplementary context)
- **Claude Agent SDK** via Node.js sidecar (Sonnet model)
- **Apple Speech APIs** (`SpeechAnalyzer` + `SpeechTranscriber`) for on-device voice transcription
- Local persistence via UserDefaults + JSON files

## Build & Run
```bash
# Build Swift app
cd Flux && xcodebuild -scheme Flux -configuration Debug -destination "platform=macOS" build

# Run Node sidecar
cd sidecar && npm install && npm start

# Or run both (sidecar + build + launch) via helper script
./scripts/dev.sh
```

## Test Commands (Backpressure)
```bash
cd Flux && xcodebuild -scheme Flux -configuration Debug -destination "platform=macOS" build 2>&1 | tail -5
```

## Key References
- **Liquid Glass:** https://github.com/conorluddy/LiquidGlassReference
- **Claude Agent SDK:** `@anthropic-ai/claude-agent-sdk` (npm)
- **ScreenCaptureKit:** https://developer.apple.com/documentation/screencapturekit
- **AXUIElement:** https://developer.apple.com/documentation/applicationservices/axuielement

## Build Order
1. Xcode project skeleton + SwiftUI app shell
2. Dynamic Island notch UI (NSPanel + Liquid Glass)
3. AXUIElement tree extraction
4. ScreenCaptureKit screenshots
5. Node.js sidecar (Agent SDK + custom tools)
6. WebSocket bridge (Swift ↔ Node)
7. Chat UI in island overlay
8. Voice input (Apple Speech on-device transcription)
9. Tool builder GUI
10. Tool execution engine (shortcuts/scripts/applescript)
11. Channel setup GUI (Discord/Slack/WhatsApp)
12. Onboarding + permissions wizard

## Conventions
- Swift: Apple's Swift style guide
- SwiftUI views in `Views/`
- Models in `Models/`
- Services in `Services/`
- Use `@Observable` (macOS 14+) for state management
- Keep views small and composable
- Use async/await for all async work
- Node sidecar: TypeScript, ES modules
