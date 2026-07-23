import SwiftUI

struct SidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager

    @Binding var selection: AppDestination

    private let primaryDestinations: [AppDestination] = [
        .home,
        .novels,
        .anime,
        .movies,
        .football,
    ]

    private let libraryDestinations: [AppDestination] = [
        .bookmarks,
        .downloads,
        .history,
    ]

    private var activeDownloadCount: Int {
        model.offlineDownloads.count(where: \.isDownloading)
            + mediaDownloads.activeCount
    }

    var body: some View {
        List {
            ForEach(primaryDestinations, id: \.self) { destination in
                destinationRow(destination)
            }

            Section("Library") {
                ForEach(libraryDestinations, id: \.self) { destination in
                    destinationRow(destination)
                }
            }
        }
        .listStyle(.sidebar)
        .controlSize(.large)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            accountButton
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
        }
    }

    private func destinationRow(_ destination: AppDestination) -> some View {
        let isSelected = selection == destination

        return Button {
            selection = destination
        } label: {
            HStack(spacing: 9) {
                Image(systemName: destination.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)
                Text(destination.title)
                Spacer(minLength: 0)
                if destination == .downloads, activeDownloadCount > 0 {
                    Text(activeDownloadCount, format: .number)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.10 : 0))
                .padding(.horizontal, 8)
        )
        .animation(
            reduceMotion ? nil : AsterionMotion.sidebar,
            value: activeDownloadCount
        )
        .help(destinationHelp(destination))
        .accessibilityLabel(destinationAccessibilityLabel(destination))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func destinationHelp(_ destination: AppDestination) -> String {
        guard destination == .downloads, activeDownloadCount > 0 else {
            return destination.title
        }
        return "\(destination.title) · \(activeDownloadCount) active"
    }

    private func destinationAccessibilityLabel(_ destination: AppDestination) -> String {
        guard destination == .downloads, activeDownloadCount > 0 else {
            return destination.title
        }
        let item = activeDownloadCount == 1 ? "download" : "downloads"
        return "\(destination.title), \(activeDownloadCount) active \(item)"
    }

    private var accountButton: some View {
        let isSelected = selection == .account

        return Button {
            selection = .account
        } label: {
            HStack(spacing: 9) {
                SidebarAccountAvatar(user: model.signedInUser, size: 26)
                Text(model.signedInUser?.name ?? "Account")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(isSelected ? 0.10 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Account")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarAccountAvatar: View {
    let user: AppModel.SignedInUser?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: user?.imageURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
