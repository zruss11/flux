import Foundation
import AVFoundation

enum PermissionRequests {
    /// `AVCaptureDevice.requestAccess` may invoke its callback on a non-main queue.
    /// We hop back to `@MainActor` before calling `completion`.
    static func requestMicrophoneAccess(_ completion: @MainActor @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                completion(granted)
            }
        }
    }
}

