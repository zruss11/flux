import Foundation
import os

private struct DeepgramSpeechEvent: Decodable {
    let type: String?
    let isFinal: Bool?
    let speechFinal: Bool?
    let channel: DeepgramSpeechChannel?
}

private struct DeepgramSpeechChannel: Decodable {
    let alternatives: [DeepgramSpeechAlternative]?
}

private struct DeepgramSpeechAlternative: Decodable {
    let transcript: String?
}

private struct DeepgramStreamingState {
    var finalTranscript = ""
    var interimTranscript = ""
    var isStopping = false
    var hasReportedFailure = false
}

/// Lightweight wrapper around Deepgram live streaming websocket transcription.
final class DeepgramStreamingSession: @unchecked Sendable {
    private let apiKey: String
    private let onTranscriptUpdate: @MainActor (String) -> Void
    private let onFailure: @MainActor (String) -> Void

    private let requestDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let state = OSAllocatedUnfairLock(initialState: DeepgramStreamingState())
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(
        apiKey: String,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        self.apiKey = apiKey
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onFailure = onFailure
        self.session = URLSession(configuration: .default)
    }

    @discardableResult
    func start() -> Bool {
        guard var components = URLComponents(string: "wss://api.deepgram.com/v1/listen") else {
            Task { @MainActor in
                self.onFailure("Invalid Deepgram endpoint URL.")
            }
            return false
        }

        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true")
        ]

        guard let url = components.url else {
            Task { @MainActor in
                self.onFailure("Invalid Deepgram endpoint URL.")
            }
            return false
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let socketTask = session.webSocketTask(with: request)
        socketTask.resume()
        task = socketTask

        state.withLock { state in
            state.isStopping = false
            state.hasReportedFailure = false
        }

        startReceiveLoop()
        return true
    }

    func appendPCMChunk(_ data: Data) {
        let shouldSend = state.withLock { state in
            !state.isStopping
        }
        guard shouldSend else { return }

        let socketTask = task
        guard let socketTask else { return }

        socketTask.send(.data(data)) { _ in }
    }

    func stop() async -> String {
        state.withLock { state in
            state.isStopping = true
        }

        guard let socketTask = task else {
            return getCombinedTranscript()
        }

        if let closeData = "{\"type\":\"CloseStream\"}".data(using: .utf8) {
            await withCheckedContinuation { continuation in
                socketTask.send(.string(String(data: closeData, encoding: .utf8) ?? "")) { _ in
                    continuation.resume()
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(250))
        socketTask.cancel(with: .goingAway, reason: nil)
        task = nil

        return getCombinedTranscript()
    }

    func cancel() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func startReceiveLoop() {
        guard let socketTask = task else { return }

        socketTask.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                self.handleSocketError(error)
            case .success(let message):
                self.handleMessage(message)
                self.startReceiveLoop()
            }
        }
    }

    private func handleSocketError(_ error: Error) {
        let shouldReport = state.withLock { state in
            if state.isStopping || state.hasReportedFailure {
                return false
            }
            state.hasReportedFailure = true
            return true
        }

        guard shouldReport else { return }
        Task { @MainActor in
            self.onFailure("Deepgram connection error: \(error.localizedDescription)")
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let raw):
            data = raw
        case .string(let text):
            data = text.data(using: .utf8)
        @unknown default:
            return
        }

        guard let data else { return }
        guard let event = try? requestDecoder.decode(DeepgramSpeechEvent.self, from: data) else { return }
        guard let transcript = event.channel?.alternatives?.first?.transcript else { return }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isFinal = event.isFinal == true || event.speechFinal == true

        let combined = state.withLock { state in
            if isFinal {
                if state.finalTranscript.isEmpty {
                    state.finalTranscript = trimmed
                } else {
                    state.finalTranscript = Self.concatSegments(
                        base: state.finalTranscript,
                        next: trimmed
                    )
                }
                state.interimTranscript = ""
                return state.finalTranscript
            }

            state.interimTranscript = trimmed
            return Self.concatSegments(base: state.finalTranscript, next: state.interimTranscript)
        }

        Task { @MainActor in
            self.onTranscriptUpdate(combined)
        }
    }

    private func getCombinedTranscript() -> String {
        let combined = state.withLock { state in
            Self.concatSegments(base: state.finalTranscript, next: state.interimTranscript)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return combined
    }

    private static func concatSegments(base: String, next: String) -> String {
        let baseTrimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseTrimmed.isEmpty else { return nextTrimmed }
        guard !nextTrimmed.isEmpty else { return baseTrimmed }

        if baseTrimmed.hasSuffix(".") || baseTrimmed.hasSuffix(",") || baseTrimmed.hasSuffix("?") || baseTrimmed.hasSuffix("!") {
            return "\(baseTrimmed) \(nextTrimmed)"
        }

        return "\(baseTrimmed) \(nextTrimmed)"
    }
}
