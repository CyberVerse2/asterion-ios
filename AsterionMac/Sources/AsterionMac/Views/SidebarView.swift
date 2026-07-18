import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let mode: AppMode
    @Binding var novelSelection: AppSection
    @Binding var animeSelection: AnimeSection
    @Binding var movieSelection: MovieSection
    @Binding var footballSelection: FootballSection

    private var novelListSelection: Binding<AppSection?> {
        Binding(
            get: { novelSelection },
            set: { newValue in
                if let newValue {
                    novelSelection = newValue
                }
            }
        )
    }

    private var animeListSelection: Binding<AnimeSection?> {
        Binding(
            get: { animeSelection },
            set: { newValue in
                if let newValue {
                    animeSelection = newValue
                }
            }
        )
    }

    private var movieListSelection: Binding<MovieSection?> {
        Binding(
            get: { movieSelection },
            set: { newValue in
                if let newValue { movieSelection = newValue }
            }
        )
    }

    private var footballListSelection: Binding<FootballSection?> {
        Binding(
            get: { footballSelection },
            set: { newValue in
                if let newValue { footballSelection = newValue }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if mode == .novels {
                List(selection: novelListSelection) {
                    Section("Novels") {
                        ForEach(AppSection.allCases, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                                .help(section.title)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else if mode == .anime {
                List(selection: animeListSelection) {
                    Section("Anime") {
                        ForEach(AnimeSection.allCases, id: \.self) { section in
                            sidebarRow(
                                title: section.title,
                                systemImage: section.systemImage,
                                count: section == .bookmarks ? animeBookmarkCount : nil
                            )
                                .tag(section)
                                .help(section.title)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else if mode == .movies {
                List(selection: movieListSelection) {
                    Section("Movies") {
                        ForEach(MovieSection.allCases, id: \.self) { section in
                            sidebarRow(
                                title: section.title,
                                systemImage: section.systemImage,
                                count: section == .bookmarks ? movieBookmarkCount : nil
                            )
                                .tag(section)
                                .help(section.title)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                List(selection: footballListSelection) {
                    Section("Football") {
                        ForEach(FootballSection.allCases, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                                .help(section.title)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Asterion")
    }

    private var animeBookmarkCount: Int {
        model.mediaBookmarks.count { $0.mediaType == .anime }
    }

    private var movieBookmarkCount: Int {
        model.mediaBookmarks.count { $0.mediaType == .movie }
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
