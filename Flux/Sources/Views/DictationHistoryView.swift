import SwiftUI

struct DictationHistoryView: View {
    @Bindable var historyStore: DictationHistoryStore

    @State private var expandedEntryId: UUID?

    var body: some View {
        if historyStore.entries.isEmpty {
            VStack {
                Spacer()
                Text("No dictation history yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(historyStore.entries) { entry in
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.finalText)
                                        .lineLimit(2)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.9))

                                    HStack(spacing: 6) {
                                        Text(entry.timestamp, style: .relative)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.4))

                                        Text("\(String(format: "%.0f", entry.duration))s")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.4))

                                        if let targetApp = entry.targetApp {
                                            Text(targetApp)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.4))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(.white.opacity(0.06)))
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.finalText, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.0001)))
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedEntryId == entry.id {
                                        expandedEntryId = nil
                                    } else {
                                        expandedEntryId = entry.id
                                    }
                                }
                            }

                            if expandedEntryId == entry.id {
                                VStack(alignment: .leading, spacing: 8) {
                                    if entry.rawTranscript != entry.cleanedText {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Raw")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.3))
                                            Text(entry.rawTranscript)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }

                                    if entry.cleanedText != entry.finalText {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Cleaned")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.3))
                                            Text(entry.cleanedText)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Final")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.3))
                                        Text(entry.finalText)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }

                                    Text(entry.enhancementMethod.rawValue)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.white.opacity(0.04))
                                )
                                .padding(.horizontal, 12)
                            }
                        }
                    }

                    // Clear All button
                    Button {
                        historyStore.clearAll()
                    } label: {
                        Text("Clear All History")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }
}
