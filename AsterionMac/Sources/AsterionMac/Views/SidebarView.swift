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
        .continueActivity,
        .bookmarks,
        .downloads,
        .history,
    ]

    private var listSelection: Binding<AppDestination?> {
        Binding(
            get: { selection == .account ? nil : selection },
            set: { destination in
                guard let destination else { return }
                selection = destination
            }
        )
    }

    private var canSearchSelection: Bool {
        selection != .downloads && selection != .account
    }

    var body: some View {
        List(selection: listSelection) {
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
            VStack(spacing: 0) {
                Divider()
                accountButton
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var searchRow: some View {
        if canSearchSelection {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)

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
            .frame(minHeight: 24)
        } else {
            Button {
                selection = .home
                Task { @MainActor in
                    await Task.yield()
                    searchIsFocused = true
                }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search Asterion")
        }
    }

    private func destinationRow(_ destination: AppDestination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .tag(destination)
            .help(destination.title)
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
