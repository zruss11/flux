import Foundation
import os

final class DeepgramLiveTranscriptionSession {
    private let session: URLSession
    private let socketTask: URLSessionWebSocketTask
    private let transcriptLock = OSAllocatedUnfairLock(initialState: "")

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
        let finalizePayload = "{\"type\":\"Finalize\"}"
        if let data = finalizePayload.data(using: .utf8) {
            try? await socketTask.send(.data(data))
        }

        // Let Deepgram flush final hypothesis before closure.
        try? await Task.sleep(for: .milliseconds(250))

        socketTask.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()

        return transcriptLock.withLock { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func receiveLoop() {
        socketTask.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if let jsonData = message.payloadData,
                   let response = try? JSONDecoder().decode(DeepgramMessage.self, from: jsonData),
                   let transcript = response.channel?.alternatives?.first?.transcript,
                   !transcript.isEmpty {
                    transcriptLock.withLock { $0 = transcript }
                }
                receiveLoop()

            case .failure(let error):
                Log.voice.error("Deepgram receive loop ended: \(error.localizedDescription, privacy: .public)")
            }
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
