import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    @Binding var selection: AppDestination

    private var listSelection: Binding<AppDestination?> {
        Binding(
            get: { selection == .account ? nil : selection },
            set: { destination in
                guard let destination else { return }
                selection = destination
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
                Label(AppDestination.home.title, systemImage: AppDestination.home.systemImage)
                    .tag(AppDestination.home)
                    .help("Home")

                Section("Browse") {
                    destinationRow(.novels)
                    destinationRow(.anime)
                    destinationRow(.movies)
                    destinationRow(.football)
                }

                Section("Your Asterion") {
                    destinationRow(.continueActivity, count: continueCount)
                    destinationRow(.bookmarks, count: bookmarkCount)
                    destinationRow(.downloads, count: completedDownloadCount)
                    destinationRow(.history, count: historyCount)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            VStack(spacing: 4) {
                Button {
                    selection = .account
                } label: {
                    footerLabel("Account", systemImage: "person.crop.circle")
                }
                .buttonStyle(.plain)
                .modifier(SelectedSidebarFooter(isSelected: selection == .account))
                .help("Account")

                SettingsLink {
                    footerLabel("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .navigationTitle("Asterion")
    }

    private func destinationRow(
        _ destination: AppDestination,
        count: Int? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Label(destination.title, systemImage: destination.systemImage)
            Spacer(minLength: 8)
            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(destination)
        .help(destination.title)
    }

    private func footerLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
    }

    private var continueCount: Int {
        model.continueReadingEntries.count + model.continueWatching.count
    }

    private var bookmarkCount: Int {
        model.libraryNovelIDs.count + model.mediaBookmarks.count
    }

    private var completedDownloadCount: Int {
        model.offlineDownloads.count { $0.phase == .completed }
            + mediaDownloads.completedCount
    }

    private var historyCount: Int {
        model.continueReadingEntries.count + model.mediaHistory.count
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

private struct SelectedSidebarFooter: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
        } else {
            content
        }
    }
}
