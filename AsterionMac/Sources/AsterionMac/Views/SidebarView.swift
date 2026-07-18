import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    let mode: AppMode
    @Binding var novelSelection: AppSection
    @Binding var animeSelection: AnimeSection
    @Binding var movieSelection: MovieSection
    @Binding var footballSelection: FootballSection
    @Binding var showsAccount: Bool
    @Binding var showsDownloads: Bool

    private var listSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if showsAccount { return .account }
                if showsDownloads { return .downloads }
                return switch mode {
                case .novels: .novel(novelSelection)
                case .anime: .anime(animeSelection)
                case .movies: .movie(movieSelection)
                case .football: .football(footballSelection)
                }
            },
            set: { newValue in
                guard let newValue else { return }
                switch newValue {
                case .account:
                    showsAccount = true
                    showsDownloads = false
                case .downloads:
                    showsAccount = false
                    showsDownloads = true
                case .novel(let section):
                    showsAccount = false
                    showsDownloads = false
                    novelSelection = section
                case .anime(let section):
                    showsAccount = false
                    showsDownloads = false
                    animeSelection = section
                case .movie(let section):
                    showsAccount = false
                    showsDownloads = false
                    movieSelection = section
                case .football(let section):
                    showsAccount = false
                    showsDownloads = false
                    footballSelection = section
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)

            List(selection: listSelection) {
                Section(mode.title) {
                    if mode == .novels {
                        ForEach(AppSection.allCases, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(SidebarSelection.novel(section))
                                .help(section.title)
                        }
                    } else if mode == .anime {
                        ForEach(AnimeSection.allCases, id: \.self) { section in
                            sidebarRow(
                                title: section.title,
                                systemImage: section.systemImage,
                                count: section == .bookmarks ? animeBookmarkCount : nil
                            )
                                .tag(SidebarSelection.anime(section))
                                .help(section.title)
                        }
                    } else if mode == .movies {
                        ForEach(MovieSection.allCases, id: \.self) { section in
                            sidebarRow(
                                title: section.title,
                                systemImage: section.systemImage,
                                count: section == .bookmarks ? movieBookmarkCount : nil
                            )
                                .tag(SidebarSelection.movie(section))
                                .help(section.title)
                        }
                    } else {
                        ForEach(FootballSection.allCases, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(SidebarSelection.football(section))
                                .help(section.title)
                        }
                    }
                }

                Section {
                    sidebarRow(
                        title: "Downloads",
                        systemImage: "arrow.down.circle.fill",
                        count: completedDownloadCount
                    )
                        .tag(SidebarSelection.downloads)
                        .help("Downloaded novels, anime, and movies")

                    Label("Account", systemImage: "person.crop.circle")
                        .tag(SidebarSelection.account)
                        .help("Account")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Asterion")
    }

    private var animeBookmarkCount: Int {
        model.mediaBookmarks.count { $0.mediaType == .anime }
    }

    private var movieBookmarkCount: Int {
        model.mediaBookmarks.count { $0.mediaType == .movie }
    }

    private var completedDownloadCount: Int {
        model.offlineDownloads.count { $0.phase == .completed }
            + mediaDownloads.completedCount
    }

    private func sidebarRow(
        title: String,
        systemImage: String,
        count: Int?
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var brand: some View {
        HStack(alignment: .center, spacing: 9) {
            logoMark
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 31)

            VStack(alignment: .leading, spacing: 2) {
                Text("ASTERION")
                    .font(.asterionDisplay(16, weight: .semibold))
                    .tracking(2.3)
                    .lineLimit(1)
                Text("Stories that transcend time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var logoMark: Image {
        guard let url = Bundle.module.url(
            forResource: "AsterionMark",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Asterion logo mark")
        }
        return Image(nsImage: image)
    }
}

private enum SidebarSelection: Hashable {
    case novel(AppSection)
    case anime(AnimeSection)
    case movie(MovieSection)
    case football(FootballSection)
    case downloads
    case account
}
