import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @EnvironmentObject private var tabBarState: TabBarState
    @State private var collections: [DownloadedNovelCollection] = []
    @State private var isLoading = true
    @State private var selectedPlayback: PlaybackRequest?

    private var hasDownloads: Bool {
        !collections.isEmpty
            || !offlineVideoDownloadService.records.isEmpty
            || !offlineVideoDownloadService.transfers.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if let error = offlineVideoDownloadService.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.asterionSerif(14))
                            .foregroundStyle(Color.asterionMuted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if isLoading {
                        ProgressView()
                            .tint(Color.goldAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if !hasDownloads {
                        emptyState
                    } else {
                        downloadedContent
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .background { AsterionBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadDownloads() }
            .task { await loadDownloads() }
            .navigationDestination(for: DownloadedNovelCollection.self) { collection in
                DownloadedNovelView(collection: collection)
            }
            .fullScreenCover(item: $selectedPlayback, onDismiss: PlaybackOrientationLock.endVideo) { request in
                NativeMediaPlayerView(request: request)
            }
        }
    }

    private var header: some View {
        AsterionPageHeader(title: "Downloads")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nothing here yet")
                .font(.asterionDisplay(26, weight: .medium))
                .foregroundStyle(Color.asterionText)

            Button {
                tabBarState.selectedTab = .browse
            } label: {
                Text("Browse the catalog")
                    .font(.asterionReading(16, weight: .semibold))
                    .foregroundStyle(Color.asterionOnInk)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.asterionInk, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private var downloadedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !offlineVideoDownloadService.transfers.isEmpty {
                videoTransfersSection
            }

            if !offlineVideoDownloadService.records.isEmpty {
                offlineVideoSection
            }

            if !collections.isEmpty {
                chapterDownloadsSection
            }
        }
    }

    private var videoTransfersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionSectionLabel(title: "Downloading")

            ForEach(offlineVideoDownloadService.transfers) { transfer in
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.goldAccent)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(transfer.title)
                            .font(.asterionSerif(16, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(2)
                        ProgressView(value: transfer.progress)
                            .tint(Color.goldAccent)
                        Text("\(Int(transfer.progress * 100))%")
                            .font(.asterionMono(9))
                            .foregroundStyle(Color.asterionMuted)
                    }
                    Button {
                        offlineVideoDownloadService.cancel(requestID: transfer.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.asterionMuted)
                    .accessibilityLabel("Cancel download")
                }
                .padding(14)
                .asterionGlassSurface(cornerRadius: 18)
            }
        }
    }

    private var offlineVideoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionSectionLabel(title: "Offline Video")

            ForEach(offlineVideoDownloadService.records) { record in
                HStack(spacing: 14) {
                    Button {
                        selectedPlayback = offlineVideoDownloadService.playbackRequest(for: record)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.goldAccent)
                                .frame(width: 46, height: 58)
                                .background(Color.goldAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title)
                                    .font(.asterionSerif(17, weight: .semibold))
                                    .foregroundStyle(Color.asterionText)
                                    .lineLimit(2)
                                Text("Downloaded \(record.downloadedAt, format: .relative(presentation: .named))")
                                    .font(.asterionMono(9))
                                    .foregroundStyle(Color.asterionMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        offlineVideoDownloadService.remove(record)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.asterionMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove download")
                }
                .padding(14)
                .asterionGlassSurface(cornerRadius: 18)
            }
        }
    }

    private var chapterDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionSectionLabel(title: "Novels")

            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                HStack(spacing: 15) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.goldAccent)
                        .frame(width: 46, height: 58)
                        .background(Color.goldAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.title)
                            .font(.asterionSerif(17, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(2)

                        Text("\(collection.chapterCount) \(collection.chapterCount == 1 ? "chapter" : "chapters") · \(collection.formattedSize)")
                            .font(.asterionMono(10))
                            .foregroundStyle(Color.asterionMuted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.goldAccent)
                        .accessibilityLabel("Available offline")
                }
                .padding(14)
                .asterionGlassSurface(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadDownloads() async {
        isLoading = true
        defer { isLoading = false }

        collections = await OfflineChapterStore.shared.downloadedCollections()
    }
}
