import SwiftUI

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tr = topCornerRadius
        let br = bottomCornerRadius

        // Start at top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left corner — concave (curves inward to hug the physical notch)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control: CGPoint(x: rect.minX + tr, y: rect.minY)
        )

        // Left edge down to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))

        // Bottom-left corner — convex (standard rounded corner)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))

        // Bottom-right corner — convex (standard rounded corner)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY)
        )

        // Right edge up to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))

        // Top-right corner — concave (curves inward to hug the physical notch)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
