import Foundation
import Speech
import AVFoundation

enum PermissionRequests {
    /// `SFSpeechRecognizer.requestAuthorization` may invoke its callback on a non-main queue.
    /// We hop back to `@MainActor` before calling `completion` to avoid Swift runtime
    /// executor assertions when callers originate from SwiftUI / main-actor contexts.
    static func requestSpeechAuthorization(_ completion: @MainActor @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                completion(status)
            }
        }
    }

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

