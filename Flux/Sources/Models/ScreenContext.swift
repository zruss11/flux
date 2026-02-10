import Foundation

struct ScreenContext: Sendable {
    var axTree: AXNode?
    var screenshot: String?
    var selectedText: String?
    var frontmostApp: String?
}

struct AXNode: Codable, Sendable {
    var role: String
    var title: String?
    var value: String?
    var nodeDescription: String?
    var children: [AXNode]?
}
