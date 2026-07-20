import ClerkKit
import ClerkKitUI
import SwiftUI

enum AsterionClerkTheme {
    @MainActor
    static func make() -> ClerkTheme {
        ClerkTheme(
            colors: .init(
                primary: .asterionAccent,
                background: .asterionSurface,
                input: .asterionBackground,
                danger: .asterionAccent,
                success: Color(red: 0.20, green: 0.46, blue: 0.31),
                warning: Color(red: 0.68, green: 0.43, blue: 0.16),
                foreground: .asterionText,
                mutedForeground: .asterionMuted,
                primaryForeground: .white,
                inputForeground: .asterionText,
                neutral: .asterionMuted,
                ring: .asterionAccent,
                muted: .asterionCard,
                secondaryButtonBackground: .asterionBackground,
                secondaryButtonForeground: .asterionText,
                shadow: .black,
                border: .asterionBorder
            ),
            fonts: .init(
                largeTitle: .asterionDisplay(30, weight: .semibold),
                title: .asterionDisplay(26, weight: .semibold),
                title2: .asterionDisplay(22, weight: .semibold),
                title3: .asterionDisplay(19, weight: .semibold),
                headline: .system(size: 15, weight: .semibold),
                subheadline: .system(size: 13),
                body: .system(size: 14),
                callout: .system(size: 13),
                footnote: .system(size: 11),
                caption: .system(size: 10),
                caption2: .system(size: 9)
            ),
            design: .init(borderRadius: 10)
        )
    }
}

struct AccountSummaryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let user = model.signedInUser {
                signedInProfile(user)
            } else {
                signedOutProfile
            }
        }
        .background(Color.asterionMediaCanvas)
    }

    private func signedInProfile(_ user: AppModel.SignedInUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                profileHeader(user)
                profileStats
                currentlyReading
                continueWatching
                recentViewing
                savedMedia
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private func profileHeader(_ user: AppModel.SignedInUser) -> some View {
        HStack(spacing: 22) {
            ReaderAvatar(user: user, size: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text("ASTERION PROFILE")
                    .font(.asterionMono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.asterionAccent)

                Text(user.name)
                    .font(.asterionDisplay(32, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)

                if let email = user.email {
                    Text(email)
                        .font(.callout)
                        .foregroundStyle(Color.asterionMuted)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 12)

            Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.asterionAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.asterionAccentSoft, in: Capsule())
        }
        .padding(24)
        .stableAccountSurface(cornerRadius: 16)
    }

    private var profileStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Your Asterion", subtitle: "Everything you have saved, read, and watched.")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ProfileStatCard(
                    value: String(model.libraryNovelIDs.count),
                    label: model.libraryNovelIDs.count == 1 ? "Saved story" : "Saved stories",
                    icon: "books.vertical.fill"
                )
                ProfileStatCard(
                    value: String(model.mediaStats.savedAnime),
                    label: "Saved anime",
                    icon: "play.rectangle.on.rectangle.fill"
                )
                ProfileStatCard(
                    value: String(model.mediaStats.savedMovies),
                    label: "Saved movies",
                    icon: "film.fill"
                )
                ProfileStatCard(
                    value: String(model.mediaStats.savedMatches),
                    label: "Saved matches",
                    icon: "sportscourt.fill"
                )
                ProfileStatCard(
                    value: String(model.mediaStats.animeEpisodesCompleted + model.mediaStats.movieUnitsCompleted),
                    label: "Finished watches",
                    icon: "checkmark.circle.fill"
                )
                ProfileStatCard(
                    value: String(model.mediaStats.activityLast30Days),
                    label: "Items watched · last 30 days",
                    icon: "calendar.badge.clock"
                )
            }
        }
    }

    private var currentlyReading: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Currently reading", subtitle: "Continue from your latest synced chapter.")

            if model.continueReadingEntries.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundStyle(Color.asterionAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your next story is waiting")
                            .font(.asterionDisplay(17, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                        Text("Open a novel and start reading to see it here.")
                            .font(.callout)
                            .foregroundStyle(Color.asterionMuted)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .stableAccountSurface(cornerRadius: 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.continueReadingEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                        }
                        ReadingActivityRow(entry: entry) {
                            openWindow(
                                value: ReaderRoute(
                                    novelID: entry.novel.id,
                                    chapterID: entry.progress.chapterId
                                )
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .stableAccountSurface(cornerRadius: 14)
            }
        }
    }

    @ViewBuilder
    private var continueWatching: some View {
        if !model.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(
                    title: "Continue watching",
                    subtitle: "Resume the latest episode or movie saved to your account."
                )

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.continueWatching.prefix(4).enumerated()), id: \.element.id) { index, progress in
                        if index > 0 { Divider() }
                        MediaProgressRow(progress: progress) {
                            openPlayback(progress)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .stableAccountSurface(cornerRadius: 14)
            }
        }
    }

    @ViewBuilder
    private var recentViewing: some View {
        if !model.mediaHistory.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(
                    title: "Watch history",
                    subtitle: "Your latest anime episodes, series, and movies."
                )

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.mediaHistory.prefix(6).enumerated()), id: \.element.id) { index, history in
                        if index > 0 { Divider() }
                        MediaHistoryRow(history: history) {
                            openPlayback(history)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .stableAccountSurface(cornerRadius: 14)
            }
        }
    }

    @ViewBuilder
    private var savedMedia: some View {
        if !model.mediaBookmarks.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(
                    title: "Saved for later",
                    subtitle: "Anime, movies, and matches bookmarked across Asterion."
                )

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.mediaBookmarks.prefix(8).enumerated()), id: \.element.id) { index, bookmark in
                        if index > 0 { Divider() }
                        MediaBookmarkRow(
                            bookmark: bookmark,
                            isUpdating: model.isUpdatingMediaBookmark(bookmark.key),
                            remove: {
                                Task { await model.toggleMediaBookmark(descriptor(for: bookmark)) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 18)
                .stableAccountSurface(cornerRadius: 14)
            }
        }
    }

    private var signedOutProfile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR ASTERION")
                        .font(.asterionMono(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.asterionAccent)
                    Text("Make Asterion yours.")
                        .font(.asterionDisplay(36, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text("A profile keeps saved stories, shows, films, matches, and every reading or watching position together.")
                        .font(.asterionDisplay(17))
                        .foregroundStyle(Color.asterionMuted)
                        .lineSpacing(4)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                VStack(spacing: 0) {
                    ProfileBenefit(icon: "bookmark", title: "Save anything", detail: "Keep novels, anime, movies, and matches together.")
                    Divider()
                    ProfileBenefit(icon: "play.circle", title: "Never lose your place", detail: "Reading and watching progress follows your account.")
                    Divider()
                    ProfileBenefit(icon: "chart.bar", title: "See your story", detail: "Your profile turns activity into useful personal stats.")
                }
                .padding(.horizontal, 22)
                .stableAccountSurface(cornerRadius: 14)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(34)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private func descriptor(for bookmark: MediaBookmark) -> MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: bookmark.mediaType,
            contentID: bookmark.contentId,
            title: bookmark.title,
            subtitle: bookmark.subtitle,
            imageURL: bookmark.imageURL
        )
    }

    private func openPlayback(_ progress: MediaPlaybackProgress) {
        switch progress.mediaType {
        case .anime:
            openWindow(
                value: AnimePlayerRoute(
                    slug: progress.contentId,
                    title: progress.title,
                    initialEpisodeID: progress.unitId
                )
            )
        case .movie:
            openWindow(
                value: MoviePlayerRoute(
                    slug: progress.contentId,
                    title: progress.title,
                    initialEpisodeID: progress.unitId
                )
            )
        case .football:
            break
        }
    }

    private func openPlayback(_ history: MediaHistoryEntry) {
        switch history.mediaType {
        case .anime:
            openWindow(
                value: AnimePlayerRoute(
                    slug: history.contentId,
                    title: history.title,
                    initialEpisodeID: history.unitId
                )
            )
        case .movie:
            openWindow(
                value: MoviePlayerRoute(
                    slug: history.contentId,
                    title: history.title,
                    initialEpisodeID: history.unitId == history.contentId ? nil : history.unitId
                )
            )
        case .football:
            break
        }
    }
}

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var presentsProfileEditor = false
    @State private var clerkTheme = AsterionClerkTheme.make()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let user = model.signedInUser {
                    signedInAccount(user)
                } else {
                    signedOutAccount
                }
            }
            .frame(maxWidth: 540, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.asterionMediaCanvas)
        .sheet(isPresented: $presentsProfileEditor) {
            UserProfileView()
                .environment(Clerk.shared)
                .environment(\.clerkTheme, clerkTheme)
                .hidingScrollIndicators()
        }
    }

    private func signedInAccount(_ user: AppModel.SignedInUser) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 5) {
                Text("Account & sync")
                    .font(.asterionDisplay(26, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text("Manage your identity and Asterion session.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ReaderAvatar(user: user, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name)
                            .font(.asterionDisplay(18, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(Color.asterionMuted)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                }

                Button {
                    presentsProfileEditor = true
                } label: {
                    Label("Manage Profile", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.large)
                .tint(.asterionAccent)
            }
            .accountCard()

            VStack(alignment: .leading, spacing: 16) {
                Label("Automatic saving", systemImage: "externaldrive.badge.checkmark")
                    .font(.asterionDisplay(17, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                AccountStatusRow(label: "Library", value: "\(model.libraryNovelIDs.count) saved")
                AccountStatusRow(label: "Reading progress", value: "\(model.continueReadingEntries.count) active")
                AccountStatusRow(label: "Media bookmarks", value: "\(model.mediaBookmarks.count) saved")
                AccountStatusRow(label: "Watch progress", value: "\(model.continueWatching.count) active")
                AccountStatusRow(label: "Watch history", value: "\(model.mediaStats.historyEntries) entries")
                Text("Asterion saves bookmarks, reading position, watch progress, and history on this Mac first, then sends them to your account when sync is available.")
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accountCard()

            if let error = model.accountError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.asterionAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accountCard()
            }

            Button(role: .destructive) {
                Task { await model.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var signedOutAccount: some View {
        Group {
            VStack(alignment: .leading, spacing: 5) {
                Text("Welcome to Asterion")
                    .font(.asterionDisplay(26, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text("Sign in to begin your personal library.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
            }

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 42, weight: .thin))
                    .foregroundStyle(Color.asterionAccent)
                Text("Keep your place")
                    .font(.asterionDisplay(21, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text("Create an account or sign in to sync bookmarks, reading progress, watch progress, and history.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Sign In or Create Account") {
                    openWindow(id: "authentication")
                }
                .buttonStyle(.borderedProminent)
                .tint(.asterionAccent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .accountCard()

            if let error = model.accountError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.asterionAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accountCard()
            }
        }
    }
}

struct AsterionAuthenticationView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image("AsterionMark", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 27)
                Text("ASTERION")
                    .font(.asterionDisplay(15, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.asterionText)
                Spacer()
                Text("YOUR ASTERION")
                    .font(.asterionMono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.asterionAccent)
            }
            .padding(.horizontal, 2)

            AuthView(isDismissible: false)
                .environment(Clerk.shared)
                .environment(\.clerkTheme, AsterionClerkTheme.make())
                .hidingScrollIndicators()
                .frame(width: 390, height: 430)
                .background(Color.asterionSurface, in: .rect(cornerRadius: 16))
                .clipShape(.rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                }

            Text("Your bookmarks, history, and reading or watching position stay synced across Asterion.")
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 438, height: 548)
        .background(Color.asterionMediaCanvas)
        .onChange(of: clerk.user?.id) {
            if clerk.user != nil {
                dismissWindow(id: "authentication")
            }
        }
    }
}

private struct ReaderAvatar: View {
    let user: AppModel.SignedInUser
    let size: CGFloat

    var body: some View {
        AsyncImage(url: user.imageURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color.asterionSurface, lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        .accessibilityLabel("Profile photo for \(user.name)")
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.asterionDisplay(22, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.asterionMuted)
        }
    }
}

private struct ProfileStatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.asterionAccent)
                .frame(width: 30, height: 30)
                .background(Color.asterionAccentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.asterionDisplay(25, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableAccountSurface(cornerRadius: 12)
    }
}

private struct ReadingActivityRow: View {
    let entry: AppModel.ContinueReadingEntry
    let action: () -> Void

    private var progress: Double {
        min(1, max(0, entry.progress.percentage / 100))
    }

    var body: some View {
        HStack(spacing: 16) {
            CoverView(novel: entry.novel, width: 62, height: 88)

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.novel.title)
                    .font(.asterionDisplay(17, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                Text(entry.novel.authorDisplayName)
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.asterionProgressTrack)
                        Capsule()
                            .fill(Color.asterionAccent)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 5)
                .accessibilityLabel("Chapter progress")
                .accessibilityValue("\(Int(entry.progress.percentage)) percent")
                HStack {
                    Text("Chapter progress")
                    Spacer()
                    Text("\(Int(entry.progress.percentage))%")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(Color.asterionMuted)
            }

            Button(action: action) {
                Text("Continue")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .tint(.asterionAccent)
        }
        .padding(.vertical, 15)
    }
}

private struct MediaProgressRow: View {
    let progress: MediaPlaybackProgress
    let action: () -> Void

    private var fraction: Double {
        min(1, max(0, progress.percentage / 100))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                MediaCoverView(url: progress.imageURL, width: 54, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Label(progress.mediaType.title, systemImage: progress.mediaType.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.asterionAccent)
                    Text(progress.title)
                        .font(.asterionDisplay(16, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    Text(progress.unitTitle ?? progress.mediaType.title)
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                    ProgressView(value: fraction)
                        .tint(.asterionAccent)
                        .accessibilityLabel("Watch progress")
                        .accessibilityValue("\(Int(progress.percentage)) percent")
                }

                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .foregroundStyle(Color.asterionAccent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue \(progress.title), \(progress.unitTitle ?? progress.mediaType.title)")
    }
}

private struct MediaHistoryRow: View {
    let history: MediaHistoryEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                MediaCoverView(url: history.imageURL, width: 46, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(history.title)
                        .font(.asterionDisplay(15, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label(history.unitTitle ?? history.mediaType.title, systemImage: history.mediaType.systemImage)
                        Text("·")
                        Text(history.lastViewedAt.formatted(.relative(presentation: .named)))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                }

                Spacer(minLength: 8)
                if history.completed {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.asterionAccent)
                        .help("Finished")
                } else {
                    Image(systemName: "play.fill")
                        .foregroundStyle(Color.asterionMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch \(history.title), \(history.unitTitle ?? history.mediaType.title) again")
    }
}

private struct MediaBookmarkRow: View {
    let bookmark: MediaBookmark
    let isUpdating: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MediaCoverView(url: bookmark.imageURL, width: 46, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(bookmark.title)
                    .font(.asterionDisplay(15, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                Label(bookmark.subtitle ?? bookmark.mediaType.title, systemImage: bookmark.mediaType.systemImage)
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Button(action: remove) {
                if isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "bookmark.slash")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isUpdating)
            .help("Remove bookmark")
            .accessibilityLabel("Remove \(bookmark.title) from saved items")
        }
        .padding(.vertical, 11)
    }
}

private struct ProfileBenefit: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.asterionAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.asterionDisplay(16, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountStatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.asterionMuted)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(Color.asterionText)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

private extension View {
    func accountCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stableAccountSurface(cornerRadius: 12)
    }

    func stableAccountSurface(cornerRadius: CGFloat) -> some View {
        background(
            Color.asterionSurface,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.asterionBorder, lineWidth: 1)
        }
    }
}
