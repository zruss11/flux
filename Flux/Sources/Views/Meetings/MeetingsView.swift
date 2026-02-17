import SwiftUI

struct MeetingsView: View {
    @Bindable var meetingStore: MeetingStore
    @Bindable var captureManager: MeetingCaptureManager
    var onOpenMeeting: (UUID) -> Void
    var onOpenFolder: (MeetingFolder) -> Void

    @State private var newFolderName = ""
    @State private var showNewFolderField = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            if captureManager.isRecording {
                                captureManager.stopMeeting()
                            } else if !captureManager.isProcessing {
                                _ = await captureManager.startMeeting()
                            }
                        }
                    } label: {
                        Label(
                            captureManager.isRecording ? "Stop Meeting" : "Start Meeting",
                            systemImage: captureManager.isRecording ? "stop.circle.fill" : "record.circle"
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(captureManager.isProcessing && !captureManager.isRecording)

                    Spacer()

                    if captureManager.isRecording {
                        Text("Recording…")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.9))
                    } else if captureManager.isProcessing {
                        Text("Processing…")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                }

                if let error = captureManager.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    foldersSection

                    sectionHeader("Recent Meetings")

                    if meetingStore.unfiledSummaries.isEmpty {
                        Text("No meetings yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(meetingStore.unfiledSummaries) { summary in
                            meetingRow(summary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Sections

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionHeader("Folders")
                Spacer()
                Button {
                    showNewFolderField = true
                    newFolderName = ""
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }

            if showNewFolderField {
                HStack(spacing: 8) {
                    TextField("Folder name...", text: $newFolderName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)

                    Button {
                        _ = meetingStore.createFolder(name: newFolderName)
                        showNewFolderField = false
                        newFolderName = ""
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showNewFolderField = false
                        newFolderName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                .padding(.horizontal, 4)
            }

            if meetingStore.folders.isEmpty {
                Text("No meeting folders")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            } else {
                ForEach(meetingStore.folders) { folder in
                    Button {
                        onOpenFolder(folder)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow.opacity(0.75))
                                .frame(width: 16)

                            Text(folder.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))

                            Spacer()

                            Text("\(folder.meetingIds.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.0001)))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete Folder", role: .destructive) {
                            meetingStore.deleteFolder(id: folder.id)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func meetingRow(_ summary: MeetingSummary) -> some View {
        Button {
            onOpenMeeting(summary.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: summary.status))
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor(for: summary.status))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(summary.updatedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))

                        Text("\(summary.utteranceCount) utterances")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.0001)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if summary.folderId != nil {
                Button("Remove from Folder") {
                    meetingStore.moveMeeting(summary.id, toFolder: nil)
                }
            }

            Menu("Move to Folder") {
                ForEach(meetingStore.folders) { folder in
                    Button(folder.name) {
                        meetingStore.moveMeeting(summary.id, toFolder: folder.id)
                    }
                }
            }

            Divider()

            Button("Delete Meeting", role: .destructive) {
                meetingStore.deleteMeeting(id: summary.id)
            }
        }
    }

    private func iconName(for status: MeetingStatus) -> String {
        switch status {
        case .recording:
            return "record.circle"
        case .processing:
            return "gearshape.2"
        case .completed:
            return "waveform"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func iconColor(for status: MeetingStatus) -> Color {
        switch status {
        case .recording:
            return .red.opacity(0.9)
        case .processing:
            return .orange.opacity(0.85)
        case .completed:
            return .white.opacity(0.5)
        case .failed:
            return .red.opacity(0.85)
        }
    }
}
