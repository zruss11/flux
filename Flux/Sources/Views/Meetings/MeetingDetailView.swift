import AppKit
import SwiftUI

struct MeetingDetailView: View {
    @Bindable var meetingStore: MeetingStore
    let meetingId: UUID
    @State private var exportError: String?

    private var meeting: Meeting? {
        meetingStore.meeting(id: meetingId)
    }

    var body: some View {
        Group {
            if let meeting {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(meeting)

                        if meeting.utterances.isEmpty {
                            Text("No transcript yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                        } else {
                            ForEach(meeting.utterances) { utterance in
                                utteranceRow(utterance)
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Meeting not found")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
            }
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Text(meeting.startedAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))

                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))

                Text("\(String(format: "%.0f", meeting.duration))s")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))

                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))

                Text(meeting.status.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(for: meeting.status))
            }

            HStack(spacing: 8) {
                Button("Copy Transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(meeting.transcriptText, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Export .txt") {
                    export(meeting: meeting, fileExtension: "txt") { url in
                        try MeetingExportService.shared.exportTranscriptTXT(for: meeting, to: url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Export .rttm") {
                    export(meeting: meeting, fileExtension: "rttm") { url in
                        try MeetingExportService.shared.exportRTTM(for: meeting, to: url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let exportError {
                Text(exportError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
    }

    private func utteranceRow(_ utterance: MeetingUtterance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Speaker \(utterance.speakerIndex + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.08)))

                Text("\(String(format: "%.1f", utterance.startTime))s - \(String(format: "%.1f", utterance.endTime))s")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(utterance.text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private func export(
        meeting: Meeting,
        fileExtension: String,
        writer: (URL) throws -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(meeting.title.replacingOccurrences(of: " ", with: "-")).\(fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try writer(url)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func statusColor(for status: MeetingStatus) -> Color {
        switch status {
        case .recording:
            return .red.opacity(0.9)
        case .processing:
            return .orange.opacity(0.85)
        case .completed:
            return .green.opacity(0.8)
        case .failed:
            return .red.opacity(0.8)
        }
    }
}
