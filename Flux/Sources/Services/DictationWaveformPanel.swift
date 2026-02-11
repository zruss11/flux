import AppKit
import SwiftUI

@MainActor
final class DictationWaveformPanel {

    private var panel: NSPanel?
    private let state = WaveformState()

    private let panelWidth: CGFloat = 112
    private let panelHeight: CGFloat = 40

    // MARK: - Show

    func show(leftOfNotchX: CGFloat, screenTopY: CGFloat, height: CGFloat) {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(
                x: leftOfNotchX,
                y: screenTopY - height,
                width: panelWidth,
                height: panelHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: WaveformView(state: state))
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        self.panel = panel

        // Animate slide-in from behind the notch edge
        let finalX = leftOfNotchX - panelWidth - 4
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrameOrigin(NSPoint(x: finalX, y: screenTopY - height))
        }
    }

    // MARK: - Update Levels

    func updateLevels(_ levels: [Float]) {
        state.barLevels = levels
    }

    // MARK: - Show Processing

    func showProcessing() {
        state.isProcessing = true
    }

    // MARK: - Dismiss (animated)

    func dismiss() {
        guard let panel else { return }

        // Calculate the notch edge position (reverse of the slide-in offset)
        let currentX = panel.frame.origin.x
        let hiddenX = currentX + panelWidth + 4
        let originY = panel.frame.origin.y

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().setFrameOrigin(NSPoint(x: hiddenX, y: originY))
        }, completionHandler: { [weak self] in
            self?.cleanup()
        })
    }

    // MARK: - Force Hide (immediate)

    func forceHide() {
        cleanup()
    }

    // MARK: - Private

    private func cleanup() {
        panel?.orderOut(nil)
        panel = nil
        state.barLevels = Array(repeating: 0, count: 16)
        state.isProcessing = false
    }
}
