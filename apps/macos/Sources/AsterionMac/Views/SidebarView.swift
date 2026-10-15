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
            HStack(spacing: 10) {
                Image(systemName: isSelected ? selectedSymbol(for: destination) : destination.systemImage)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.asterionText : Color.asterionMuted)
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
                Text(destination.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.asterionText : Color.asterionText.opacity(0.82))
                Spacer(minLength: 0)
                if destination == .downloads, activeDownloadCount > 0 {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(activeDownloadCount, format: .number)
                            .font(.asterionMono(11, weight: .semibold))
                    }
                    .foregroundStyle(Color.asterionText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.09 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 0.06 : 0))
                }
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

    private func selectedSymbol(for destination: AppDestination) -> String {
        switch destination {
        case .home: "house.fill"
        case .novels: "book.closed.fill"
        case .anime: "play.tv.fill"
        case .movies: "film.fill"
        case .football: "soccerball.inverse"
        case .bookmarks: "bookmark.fill"
        case .downloads: "arrow.down.circle.fill"
        case .history: "clock.fill"
        case .continueActivity: "play.rectangle.fill"
        case .account: "person.crop.circle.fill"
        }
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
            HStack(spacing: 10) {
                SidebarAccountAvatar(
                    user: model.signedInUser,
                    isRestoring: model.accountSessionPresentation == .restoring,
                    size: 30
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(sidebarAccountTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    Text(sidebarAccountSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.asterionFaint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.09 : 0.04))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Account")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sidebarAccountSubtitle: String {
        switch model.accountSessionPresentation {
        case .signedIn: "Library synced"
        case .restoring: "Reconnecting…"
        case .restoreFailed: "Sign in again to sync"
        case .signedOut: "Sign in to sync"
        }
    }

    private var sidebarAccountTitle: String {
        if let name = model.signedInUser?.name {
            return name
        }
        switch model.accountSessionPresentation {
        case .restoring:
            return "Restoring"
        case .signedIn:
            return "Account"
        case .restoreFailed, .signedOut:
            return "Sign in"
        }
    }
}

private struct SidebarAccountAvatar: View {
    let user: AppModel.SignedInUser?
    var isRestoring = false
    let size: CGFloat

    var body: some View {
        Group {
            if isRestoring, user == nil {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: size, height: size)
            } else {
                AsyncImage(url: user?.imageURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(Color.asterionMuted)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
        .accessibilityHidden(true)
    }
}
