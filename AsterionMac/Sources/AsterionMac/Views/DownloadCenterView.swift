import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var model: AppModel

    private var activeCount: Int {
        model.offlineDownloads.count(where: { $0.isDownloading })
    }

    private var completedCount: Int {
        model.offlineDownloads.count(where: { $0.phase == .completed })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Downloads")
                        .font(.asterionDisplay(18, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(downloadSummary)
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }
                Spacer()
                if activeCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.asterionAccent)
                }
            }
            .padding(18)

            Divider()

            if model.offlineDownloads.isEmpty {
                ContentUnavailableView {
                    Label("No offline novels", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download a novel to read it offline.")
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.offlineDownloads) { download in
                            DownloadRow(download: download)
                            if download.id != model.offlineDownloads.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 360)
        .background(.background)
    }

    private var downloadSummary: String {
        if activeCount > 0 {
            return "\(activeCount) downloading · \(completedCount) available offline"
        }
        return completedCount == 1 ? "1 novel available offline" : "\(completedCount) novels available offline"
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var model: AppModel
    let download: OfflineDownload
    @State private var actionError: String?
    @State private var isRemoving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(download.novelTitle)
                        .font(.asterionDisplay(14, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(download.phase == .failed ? Color.red : Color.asterionMuted)
                        .lineLimit(2)
                }

                Spacer()

                if download.phase == .downloading, download.totalChapters > 0 {
                    Text(download.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.asterionAccent)
                } else if download.phase == .failed,
                          let novel = model.novel(id: download.novelID) {
                    Button("Retry") {
                        Task { await retry(novel: novel) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if download.phase == .completed {
                    Button {
                        Task { await removeDownload() }
                    } label: {
                        if isRemoving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Remove downloaded copy")
                    .disabled(isRemoving)
                }
            }

            if download.phase == .downloading {
                ProgressView(value: download.progress)
                    .tint(Color.asterionAccent)
            }

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var phaseIcon: String {
        switch download.phase {
        case .downloading: "arrow.down.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var phaseColor: Color {
        switch download.phase {
        case .downloading: Color.asterionAccent
        case .completed: Color.green
        case .failed: Color.red
        }
    }

    private var statusText: String {
        switch download.phase {
        case .downloading:
            if download.totalChapters == 0 { return "Preparing chapters…" }
            return "\(download.completedChapters) of \(download.totalChapters) chapters"
        case .completed:
            return "Available offline"
        case .failed:
            return download.errorMessage ?? "Download failed"
        }
    }

    private func retry(novel: Novel) async {
        actionError = nil
        do {
            try await model.downloadForOffline(novel: novel)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func removeDownload() async {
        isRemoving = true
        actionError = nil
        defer { isRemoving = false }
        do {
            try await model.removeOfflineDownload(novelID: download.novelID)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
