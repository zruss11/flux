import AppKit
import Combine
import SwiftUI
import CoreGraphics

// MARK: - Keyable Panel (accepts keyboard focus for text input)

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Pass-through hosting view

class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestRect().contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}

// MARK: - Island Window Manager

@MainActor
final class IslandWindowManager: ObservableObject {
    static let shared = IslandWindowManager()

    private var panel: NSPanel?
    private var hostingView: PassThroughHostingView<IslandView>?
    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var expandedContentSize = CGSize(width: 480, height: 100)
    private var targetScreen: NSScreen?
    private var notchGeometry: NotchGeometry?

    private let windowHeight: CGFloat = 750

    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: DispatchWorkItem?

    private init() {}

    var isShown: Bool { panel != nil }

    var notchSize: CGSize {
        guard let screen = targetScreen ?? preferredNotchScreen() ?? NSScreen.main else {
            return CGSize(width: 224, height: 38)
        }
        let safeTop = screen.safeAreaInsets.top
        guard safeTop > 0 else {
            return CGSize(width: 224, height: 38)
        }
        let fullWidth = screen.frame.width
        let leftPad = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightPad = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = fullWidth - leftPad - rightPad + 4
        return CGSize(width: notchWidth, height: safeTop)
    }

    func showIsland(conversationStore: ConversationStore, agentBridge: AgentBridge) {
        guard panel == nil else { return }
        guard let screen = preferredNotchScreen() ?? NSScreen.main else { return }
        self.targetScreen = screen

        let screenFrame = screen.frame
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Compute notch geometry for hit testing
        let nSize = notchSize
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - nSize.width) / 2,
            y: 0,
            width: nSize.width,
            height: nSize.height
        )
        self.notchGeometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight
        )

        let panel = KeyablePanel(
            contentRect: windowFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let islandView = IslandView(
            conversationStore: conversationStore,
            agentBridge: agentBridge,
            notchSize: nSize,
            windowManager: self
        )

        let hosting = PassThroughHostingView(rootView: islandView)
        hosting.hitTestRect = { [weak self] in
            self?.currentHitRect() ?? .zero
        }

        panel.contentView = hosting
        panel.orderFrontRegardless()
        panel.setFrame(windowFrame, display: true)

        self.panel = panel
        self.hostingView = hosting

        setupEventMonitors()
    }

    func hideIsland() {
        cancellables.removeAll()
        hoverTimer?.cancel()
        hoverTimer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostingView = nil
        isExpanded = false
        isHovering = false
        targetScreen = nil
        notchGeometry = nil
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        panel?.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    /// Ensure the panel is key and app is active (for text field focus)
    func makeKeyIfNeeded() {
        guard isExpanded else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isHovering = false
        panel?.ignoresMouseEvents = true
    }

    // MARK: - Event Monitors

    private func setupEventMonitors() {
        guard let geometry = notchGeometry else { return }

        // Hover detection: mouse enters notch area → start timer → expand
        EventMonitors.shared.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mouseLocation in
                guard let self else { return }

                if self.isExpanded {
                    return
                }

                let inNotch = geometry.isPointInNotch(mouseLocation)

                if inNotch && !self.isHovering {
                    self.isHovering = true
                    let timer = DispatchWorkItem { [weak self] in
                        guard let self, self.isHovering, !self.isExpanded else { return }
                        self.expand()
                    }
                    self.hoverTimer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timer)
                } else if !inNotch && self.isHovering {
                    self.isHovering = false
                    self.hoverTimer?.cancel()
                    self.hoverTimer = nil
                }
            }
            .store(in: &cancellables)

        // Click detection
        EventMonitors.shared.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }

                // If the click is inside our own panel, don't run collapse logic
                if event.window === self.panel {
                    return
                }

                let mouseLocation = NSEvent.mouseLocation

                if !self.isExpanded {
                    // Click in notch → expand immediately
                    if geometry.isPointInNotch(mouseLocation) {
                        self.hoverTimer?.cancel()
                        self.hoverTimer = nil
                        self.expand()
                    }
                } else {
                    // Click outside panel → collapse and re-post click
                    if geometry.isPointOutsidePanel(mouseLocation, size: self.expandedContentSize) {
                        self.collapse()
                        self.repostClick(at: mouseLocation)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func repostClick(at screenLocation: NSPoint) {
        guard let screen = targetScreen ?? NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let cgPoint = CGPoint(
            x: screenLocation.x,
            y: screenHeight - screenLocation.y + screen.frame.origin.y
        )

        if let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) {
            cgEvent.post(tap: .cghidEventTap)
        }

        if let cgEventUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) {
            cgEventUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Hit Rect

    private func currentHitRect() -> CGRect {
        guard let screen = targetScreen ?? preferredNotchScreen() ?? NSScreen.main else { return .zero }

        let screenWidth = screen.frame.width
        let nSize = notchSize

        if isExpanded {
            let expandedWidth = expandedContentSize.width + 40
            let expandedHeight = expandedContentSize.height + 20
            let x = (screenWidth - expandedWidth) / 2
            let y = windowHeight - expandedHeight
            return CGRect(x: x, y: y, width: expandedWidth, height: expandedHeight)
        } else {
            let closedWidth = nSize.width + 20
            let closedHeight = nSize.height + 10
            let x = (screenWidth - closedWidth) / 2
            let y = windowHeight - closedHeight - 5
            return CGRect(x: x, y: y, width: closedWidth, height: closedHeight)
        }
    }

    private func preferredNotchScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }

        if let builtin = NSScreen.screens.first(where: { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(num.uint32Value) != 0
        }) {
            return builtin
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}
