@preconcurrency import ScreenCaptureKit
import AppKit
import os

@Observable
@MainActor
final class ScreenCapture {
    var isPermissionGranted = false
    private var lastCaptureAt: Date?
    private let minSecondsBetweenCaptures: TimeInterval = 1.0

    func checkPermission() -> Bool {
        let hasAccess = CGPreflightScreenCaptureAccess()
        if !hasAccess {
            CGRequestScreenCaptureAccess()
        }
        isPermissionGranted = hasAccess
        return hasAccess
    }

    func captureMainDisplay(caretRect: CGRect? = nil) async -> String? {
        do {
            guard CGPreflightScreenCaptureAccess() else { return nil }
            if let last = lastCaptureAt, Date().timeIntervalSince(last) < minSecondsBetweenCaptures {
                return nil
            }
            lastCaptureAt = Date()

            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.pixelFormat = kCVPixelFormatType_32BGRA

            var image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            if let caretRect {
                let displayBounds = CGRect(
                    x: 0, y: 0,
                    width: CGFloat(display.width),
                    height: CGFloat(display.height)
                )
                image = annotateImage(image, caretRect: caretRect, displayBounds: displayBounds)
            }

            return cgImageToBase64JPEG(image, maxDimension: 1600, quality: 0.7)
        } catch {
            Log.screen.error("Screen capture error: \(error)")
            return nil
        }
    }

    func captureFrontmostWindow(caretRect: CGRect? = nil) async -> String? {
        do {
            guard CGPreflightScreenCaptureAccess() else { return nil }
            if let last = lastCaptureAt, Date().timeIntervalSince(last) < minSecondsBetweenCaptures {
                return nil
            }
            lastCaptureAt = Date()

            let content = try await SCShareableContent.current
            guard content.displays.first != nil else { return nil }

            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
            let pid = frontApp.processIdentifier

            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == pid && $0.isOnScreen
            }) else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.pixelFormat = kCVPixelFormatType_32BGRA

            var image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            if let caretRect {
                let windowBounds = windowFrameToScreenCoords(window.frame)
                image = annotateImage(image, caretRect: caretRect, displayBounds: windowBounds)
            }

            return cgImageToBase64JPEG(image, maxDimension: 1600, quality: 0.7)
        } catch {
            Log.screen.error("Window capture error: \(error)")
            return nil
        }
    }

    private func cgImageToBase64JPEG(_ cgImage: CGImage, maxDimension: Int, quality: Double) -> String? {
        autoreleasepool {
            let scaled = downscaledImage(cgImage, maxDimension: maxDimension) ?? cgImage
            let bitmapRep = NSBitmapImageRep(cgImage: scaled)
            let props: [NSBitmapImageRep.PropertyKey: Any] = [
                .compressionFactor: quality
            ]
            guard let jpegData = bitmapRep.representation(using: .jpeg, properties: props) else { return nil }
            return jpegData.base64EncodedString()
        }
    }

    private func downscaledImage(_ cgImage: CGImage, maxDimension: Int) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let longest = max(width, height)
        guard longest > maxDimension else { return nil }

        let scale = Double(maxDimension) / Double(longest)
        let newWidth = max(1, Int(Double(width) * scale))
        let newHeight = max(1, Int(Double(height) * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return ctx.makeImage()
    }

    private func annotateImage(
        _ image: CGImage,
        caretRect: CGRect,
        displayBounds: CGRect
    ) -> CGImage {
        let imgWidth = image.width
        let imgHeight = image.height

        let scaleX = CGFloat(imgWidth) / displayBounds.width
        let scaleY = CGFloat(imgHeight) / displayBounds.height

        let rectInImage = CGRect(
            x: (caretRect.origin.x - displayBounds.origin.x) * scaleX,
            y: (caretRect.origin.y - displayBounds.origin.y) * scaleY,
            width: caretRect.width * scaleX,
            height: caretRect.height * scaleY
        )

        let clampedRect = rectInImage.intersection(
            CGRect(x: 0, y: 0, width: CGFloat(imgWidth), height: CGFloat(imgHeight))
        )
        guard !clampedRect.isNull && clampedRect.width > 1 && clampedRect.height > 1 else {
            return image
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: imgWidth,
            height: imgHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return image }

        // Flip to top-left origin to match screen coordinates
        ctx.translateBy(x: 0, y: CGFloat(imgHeight))
        ctx.scaleBy(x: 1, y: -1)

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))

        let lineWidth: CGFloat = 3.0 * max(scaleX, scaleY)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        ctx.setLineWidth(lineWidth)
        let strokeRect = clampedRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        ctx.stroke(strokeRect)

        return ctx.makeImage() ?? image
    }

    nonisolated static func windowFrameToScreenCoords(_ windowFrame: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: windowFrame.origin.x - screenFrame.origin.x,
            y: screenFrame.maxY - windowFrame.origin.y - windowFrame.height,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    private func windowFrameToScreenCoords(_ windowFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(windowFrame) })
            ?? NSScreen.screens.first
        guard let screen else { return windowFrame }
        return Self.windowFrameToScreenCoords(windowFrame, screenFrame: screen.frame)
    }
}
