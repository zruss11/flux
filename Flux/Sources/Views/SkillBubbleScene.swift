import SpriteKit
import SwiftUI
import AppKit

final class SkillBubbleScene: SKScene {
    var skills: [Skill] = [] {
        didSet {
            // If the scene is already on-screen, refresh immediately. This avoids relying on
            // the per-frame update loop, which can be paused/throttled in some panel contexts.
            hasSpawned = false
            spawnIfReady()
        }
    }
    var onSkillTapped: ((Skill) -> Void)?
    var reduceMotion: Bool = false

    private var skillNodeMap: [String: Skill] = [:] // node name -> Skill

    private var dynamicRadius: CGFloat {
        switch skills.count {
        case 0...8: return 42
        case 9...16: return 34
        default: return 28
        }
    }

    private var columns: Int {
        switch skills.count {
        case 0...8: return 4
        case 9...16: return 5
        default: return 6
        }
    }

    private var hasSpawned = false

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true

        physicsWorld.gravity = CGVector(dx: 0, dy: -4)
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        physicsBody?.friction = 0.3

        // Spawn immediately on presentation; do not wait for `update(_:)`.
        // In some SwiftUI/SpriteView setups (especially non-activating panels),
        // the update loop can be paused, resulting in an empty scene.
        hasSpawned = false
        spawnIfReady()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        physicsBody?.friction = 0.3

        // If we're already showing bubbles, re-lay them out for the new size.
        // If not, attempt first spawn.
        hasSpawned = false
        spawnIfReady()
    }

    override func update(_ currentTime: TimeInterval) {
        // Spawn bubbles on first frame when we have skills and a valid size
        spawnIfReady()
    }

    func updateGravity(_ vector: CGVector) {
        physicsWorld.gravity = vector
    }

    private func spawnIfReady() {
        guard !hasSpawned else { return }
        guard view != nil else { return }
        guard !skills.isEmpty else { return }
        guard size.width > 1, size.height > 1 else { return }

        spawnBubbles()
        hasSpawned = true
    }

    private func spawnBubbles() {
        removeAllChildren()
        skillNodeMap.removeAll()

        let radius = dynamicRadius
        let cols = columns
        let spacing = radius * 2.2
        let totalWidth = CGFloat(cols) * spacing
        let startX = (size.width - totalWidth) / 2 + spacing / 2

        for (index, skill) in skills.enumerated() {
            let col = index % cols
            let row = index / cols

            let x: CGFloat
            let y: CGFloat

            if reduceMotion {
                x = startX + CGFloat(col) * spacing
                y = size.height - 60 - CGFloat(row) * spacing
            } else {
                // Start *within* the visible bounds for reliability. In some embedding contexts,
                // SpriteKit physics/time can be throttled, and spawning off-screen can look empty.
                x = startX + CGFloat(col) * spacing + CGFloat.random(in: -10...10)
                y = size.height - 60 - CGFloat(row) * spacing + CGFloat.random(in: -8...8)
            }

            let bubbleNode = createBubbleNode(for: skill, radius: radius, at: CGPoint(x: x, y: y))
            if !reduceMotion, let body = bubbleNode.physicsBody {
                // A small impulse makes the layout feel alive when physics is running,
                // but still leaves bubbles visible if physics is paused.
                body.velocity = CGVector(dx: CGFloat.random(in: -30...30), dy: CGFloat.random(in: -10...10))
            }
            addChild(bubbleNode)
        }
    }

    private func createBubbleNode(for skill: Skill, radius: CGFloat, at position: CGPoint) -> SKNode {
        let container = SKNode()
        container.position = position
        container.name = skill.id.uuidString
        skillNodeMap[skill.id.uuidString] = skill

        // Circle background — ghosted for uninstalled
        let circle = SKShapeNode(circleOfRadius: radius)
        if skill.isInstalled {
            circle.fillColor = NSColor(skill.color).withAlphaComponent(0.25)
            circle.strokeColor = NSColor(skill.color).withAlphaComponent(0.5)
            circle.lineWidth = 1.5
        } else {
            circle.fillColor = NSColor(skill.color).withAlphaComponent(0.08)
            circle.strokeColor = NSColor(skill.color).withAlphaComponent(0.25)
            circle.lineWidth = 1.0
        }
        container.addChild(circle)

        // SF Symbol icon — scale with bubble size, muted for uninstalled
        let iconSize: CGFloat = radius < 35 ? 14 : 18
        let iconAlpha: CGFloat = skill.isInstalled ? 0.9 : 0.4
        if let iconImage = sfSymbolImage(named: skill.icon, size: iconSize, color: skill.color, alpha: iconAlpha) {
            let texture = SKTexture(image: iconImage)
            let iconNode = SKSpriteNode(texture: texture)
            iconNode.position = CGPoint(x: 0, y: radius < 35 ? 6 : 8)
            container.addChild(iconNode)
        }

        // Label — truncate long names, scale font, muted for uninstalled
        let displayName: String
        if skill.name.count > 10 {
            displayName = String(skill.name.prefix(9)) + "\u{2026}"
        } else {
            displayName = skill.name
        }
        let label = SKLabelNode(text: displayName)
        label.fontName = ".AppleSystemUIFont"
        label.fontSize = radius < 35 ? 8 : 10
        label.fontColor = skill.isInstalled ? .white : NSColor.white.withAlphaComponent(0.5)
        label.position = CGPoint(x: 0, y: radius < 35 ? -10 : -14)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        container.addChild(label)

        // "+" badge for uninstalled skills
        if !skill.isInstalled {
            let badge = SKLabelNode(text: "+")
            badge.fontName = ".AppleSystemUIFontBold"
            badge.fontSize = radius < 35 ? 10 : 12
            badge.fontColor = NSColor(skill.color).withAlphaComponent(0.8)
            badge.position = CGPoint(x: radius * 0.55, y: radius * 0.45)
            badge.horizontalAlignmentMode = .center
            badge.verticalAlignmentMode = .center
            container.addChild(badge)
        }

        // Physics body
        if !reduceMotion {
            let body = SKPhysicsBody(circleOfRadius: radius)
            body.restitution = 0.4
            body.friction = 0.3
            body.linearDamping = 0.5
            body.allowsRotation = false
            body.mass = 0.1
            container.physicsBody = body
        }

        return container
    }

    private func sfSymbolImage(named name: String, size: CGFloat, color: Color, alpha: CGFloat = 0.9) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return nil
        }

        let nsColor = NSColor(color)
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            nsColor.withAlphaComponent(alpha).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return tinted
    }

    // MARK: - Mouse interaction

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        let nodes = self.nodes(at: location)

        for node in nodes {
            if let name = node.name, let skill = skillNodeMap[name] {
                onSkillTapped?(skill)
                return
            }
            if let parentName = node.parent?.name, let skill = skillNodeMap[parentName] {
                onSkillTapped?(skill)
                return
            }
        }
    }
}
