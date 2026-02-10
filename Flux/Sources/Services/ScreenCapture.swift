@preconcurrency import ScreenCaptureKit
import AppKit

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

    func captureMainDisplay() async -> String? {
        do {
            if let last = lastCaptureAt, Date().timeIntervalSince(last) < minSecondsBetweenCaptures {
                return "Capture throttled (too frequent)"
            }
            lastCaptureAt = Date()

            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            return cgImageToBase64JPEG(image, maxDimension: 1600, quality: 0.7)
        } catch {
            print("Screen capture error: \(error)")
            return nil
        }
    }

    func captureFrontmostWindow() async -> String? {
        do {
            if let last = lastCaptureAt, Date().timeIntervalSince(last) < minSecondsBetweenCaptures {
                return "Capture throttled (too frequent)"
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

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            return cgImageToBase64JPEG(image, maxDimension: 1600, quality: 0.7)
        } catch {
            print("Window capture error: \(error)")
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
}
