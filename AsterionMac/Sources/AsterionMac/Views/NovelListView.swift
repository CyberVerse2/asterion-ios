import SwiftUI

struct NovelListView: View {
    @EnvironmentObject private var model: AppModel
    let section: AppSection
    let novels: [Novel]
    @Binding var selectedNovelID: String

    var body: some View {
        Group {
            if model.isLoadingCatalog, novels.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if novels.isEmpty {
                emptyState
            } else {
                List(novels, selection: $selectedNovelID) { novel in
                    NovelRow(novel: novel, showsRank: section == .rankings)
                        .tag(novel.id)
                        .contextMenu {
                            Button(model.libraryNovelIDs.contains(novel.id) ? "Remove from Library" : "Add to Library") {
                                Task { await model.toggleLibrary(novelID: novel.id) }
                            }
                            .disabled(!model.isSignedIn)
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(section.title)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.loadCatalog() }
                } label: {
                    Label("Refresh Catalog", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                section == .library ? "Your library is empty" : "No novels found",
                systemImage: section == .library ? "books.vertical" : "magnifyingglass"
            )
        } description: {
            if section == .library, !model.isSignedIn {
                Text("Sign in from Account to sync your library.")
            } else if section == .library {
                Text("Save a novel from its detail page and it will appear here.")
            } else {
                Text("Try a different search.")
            }
        }
    }
}

private struct NovelRow: View {
    let novel: Novel
    let showsRank: Bool

    var body: some View {
        HStack(spacing: 10) {
            CoverView(novel: novel, width: 42, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if showsRank, novel.numericRank != .max {
                        Text("#\(novel.numericRank)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.asterionGold)
                    }
                    Text(novel.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                }

                Text(novel.authorDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
