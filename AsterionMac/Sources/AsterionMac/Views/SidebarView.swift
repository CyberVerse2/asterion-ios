import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var selection: AppDestination
    @Binding var searchText: String
    @FocusState private var searchIsFocused: Bool

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

    private var canSearchSelection: Bool {
        selection != .downloads && selection != .account
    }

    private var searchPrompt: String {
        switch selection {
        case .home: "Search everything"
        case .novels: "Search novels"
        case .anime: "Search anime"
        case .movies: "Search movies & TV"
        case .football: "Search teams"
        case .continueActivity, .history: "Search activity"
        case .bookmarks: "Search bookmarks"
        case .downloads, .account: "Search"
        }
    }

    var body: some View {
        List {
            searchRow
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))

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
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            accountButton
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var searchRow: some View {
        if canSearchSelection {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(searchIsFocused ? Color.asterionAccent : .secondary)
                    .frame(width: 16)

                TextField(searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular))
                    .focused($searchIsFocused)
                    .focusEffectDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        searchIsFocused ? Color.asterionAccent.opacity(0.38) : .white.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.16), value: searchIsFocused)
        } else {
            Button {
                selection = .home
                Task { @MainActor in
                    await Task.yield()
                    searchIsFocused = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Search")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.primary.opacity(0.06))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Search Asterion")
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
            }
            .font(.system(size: 15, weight: .regular))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.primary.opacity(isSelected ? 0.10 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .font(.system(size: 15, weight: .regular))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
