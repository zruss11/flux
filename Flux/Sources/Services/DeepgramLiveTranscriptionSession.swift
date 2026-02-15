import Foundation
import os

final class DeepgramLiveTranscriptionSession: @unchecked Sendable {
    private let session: URLSession
    private let socketTask: URLSessionWebSocketTask

    /// Accumulated transcript segments from Deepgram.
    private let transcriptLock = OSAllocatedUnfairLock(initialState: [String]())

    /// Called on the caller's queue when the WebSocket encounters a fatal error.
    var onError: ((Error) -> Void)?

    /// Continuation used to signal that the final transcript has arrived after a Finalize message.
    private let finalizeContinuation = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)

    private init(session: URLSession, socketTask: URLSessionWebSocketTask) {
        self.session = session
        self.socketTask = socketTask
    }

    static func connect(apiKey: String) throws -> DeepgramLiveTranscriptionSession {
        guard var components = URLComponents(string: "wss://api.deepgram.com/v1/listen") else {
            throw DeepgramError.invalidURL
        }

        components.queryItems = [
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "channels", value: "1"),
            .init(name: "interim_results", value: "true"),
            .init(name: "punctuate", value: "true"),
            .init(name: "endpointing", value: "300")
        ]

        guard let url = components.url else {
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        let deepgramSession = DeepgramLiveTranscriptionSession(session: session, socketTask: task)
        task.resume()
        deepgramSession.receiveLoop()
        return deepgramSession
    }

    func sendAudio(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        try await socketTask.send(.data(data))
    }

    func finish() async -> String {
        // Send finalize as a text frame per Deepgram's WebSocket API.
        try? await socketTask.send(.string("{\"type\":\"Finalize\"}"))

        // Wait for Deepgram to send the final transcript (up to 3 s timeout).
        await withCheckedContinuation { continuation in
            finalizeContinuation.withLock { $0 = continuation }

            // Safety timeout so we never block indefinitely.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.resumeFinalizeContinuationIfNeeded()
            }
        }

        socketTask.cancel(with: .normalClosure, reason: nil)
        session.finishTasksAndInvalidate()

        return transcriptLock.withLock { segments in
            segments.joined(separator: " ")
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Invalidates the URLSession (for error paths where `finish()` is never called).
    func invalidate() {
        socketTask.cancel(with: .abnormalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    private func receiveLoop() {
        socketTask.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if let jsonData = message.payloadData,
                   let response = try? JSONDecoder().decode(DeepgramMessage.self, from: jsonData) {

                    // Check if this is a final result (is_final == true) which
                    // indicates the end of an utterance segment.
                    if let transcript = response.channel?.alternatives?.first?.transcript,
                       !transcript.isEmpty {
                        if response.isFinal == true {
                            transcriptLock.withLock { $0.append(transcript) }

                            // If we were waiting for a finalize response, resume.
                            if response.speechFinal == true || response.type == "Finalize" {
                                resumeFinalizeContinuationIfNeeded()
                            }
                        }
                    }

                    // A Finalize response from Deepgram signals all data has been flushed.
                    if response.type == "Finalize" {
                        resumeFinalizeContinuationIfNeeded()
                    }
                }
                receiveLoop()

            case .failure(let error):
                Log.voice.error("Deepgram receive loop ended: \(error.localizedDescription, privacy: .public)")
                session.invalidateAndCancel()
                onError?(error)
            }
        }
    }

    private func resumeFinalizeContinuationIfNeeded() {
        finalizeContinuation.withLock { cont in
            cont?.resume()
            cont = nil
        }
    }
}

private extension URLSessionWebSocketTask.Message {
    var payloadData: Data? {
        switch self {
        case .data(let data):
            return data
        case .string(let string):
            return string.data(using: .utf8)
        @unknown default:
            return nil
        }
    }
}

private struct DeepgramMessage: Decodable {
    struct Channel: Decodable {
        struct Alternative: Decodable {
            let transcript: String
        }

        let alternatives: [Alternative]?
    }

    let channel: Channel?
    let type: String?
    let isFinal: Bool?
    let speechFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case channel
        case type
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }
}

enum DeepgramError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Deepgram live transcription URL."
        }
    }
}
