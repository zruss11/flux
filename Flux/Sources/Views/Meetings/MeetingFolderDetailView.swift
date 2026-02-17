import SwiftUI

struct MeetingFolderDetailView: View {
    @Bindable var meetingStore: MeetingStore
    let folder: MeetingFolder
    var onOpenMeeting: (UUID) -> Void

    private var summaries: [MeetingSummary] {
        meetingStore.summaries(forFolder: folder.id)
    }

    var body: some View {
        Group {
            if summaries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.14))
                    Text("No meetings in this folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(summaries) { summary in
                            Button {
                                onOpenMeeting(summary.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(summary.title)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.9))

                                        Text(summary.updatedAt, style: .relative)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.35))
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
                                Button("Remove from Folder") {
                                    meetingStore.moveMeeting(summary.id, toFolder: nil)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}
