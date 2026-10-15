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
                input: .asterionMediaCanvas,
                danger: Color(hex: 0xF0645C),
                success: .asterionSuccess,
                warning: .asterionWarning,
                foreground: .asterionText,
                mutedForeground: .asterionMuted,
                primaryForeground: .asterionMediaCanvas,
                inputForeground: .asterionText,
                neutral: .asterionMuted,
                ring: Color.white.opacity(0.42),
                muted: .asterionCard,
                secondaryButtonBackground: .asterionCard,
                secondaryButtonForeground: .asterionText,
                shadow: .black,
                border: .asterionBorder
            ),
            fonts: .init(
                largeTitle: .asterionTitle(26, weight: .heavy),
                title: .asterionTitle(22, weight: .bold),
                title2: .asterionTitle(19, weight: .bold),
                title3: .asterionTitle(16, weight: .bold),
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
    @Environment(\.asterionTopInset) private var topInset
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var presentsProfileEditor = false
    @State private var clerkTheme = AsterionClerkTheme.make()

    var body: some View {
        Group {
            switch model.accountSessionPresentation {
            case .signedIn:
                if let user = model.signedInUser {
                    signedInProfile(user)
                } else {
                    restoringProfile
                }
            case .restoring:
                restoringProfile
            case .restoreFailed:
                restoreFailedProfile
            case .signedOut:
                signedOutProfile
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionMediaCanvas)
        .sheet(isPresented: $presentsProfileEditor) {
            UserProfileView()
                .environment(Clerk.shared)
                .environment(\.clerkTheme, clerkTheme)
                .hidingScrollIndicators()
        }
    }

    // MARK: Signed in

    private func signedInProfile(_ user: AppModel.SignedInUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                profileHeader(user)
                profileStats
                currentlyReading
                continueWatching
                recentViewing
                savedMedia
                accountActions
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, AsterionLayout.pageInset)
            .padding(.top, topInset + 22)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(alignment: .top) {
                if user.imageURL != nil {
                    ArtworkGlow(url: user.imageURL, height: 460, intensity: 0.45)
                }
            }
        }
        .hidingScrollIndicators()
    }

    private func profileHeader(_ user: AppModel.SignedInUser) -> some View {
        HStack(alignment: .center, spacing: 24) {
            ReaderAvatar(user: user, size: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text(user.name)
                    .font(.asterionTitle(30, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)

                if let email = user.email {
                    Text(email)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.asterionMuted)
                        .textSelection(.enabled)
                }

                SyncStatusChip(hasIssue: model.accountError != nil)
                    .padding(.top, 6)
            }

            Spacer(minLength: 12)
        }
    }

    private var profileStats: some View {
        let stats: [ProfileStat] = [
            ProfileStat(
                value: model.libraryNovelIDs.count,
                label: model.libraryNovelIDs.count == 1 ? "Novel saved" : "Novels saved"
            ),
            ProfileStat(value: model.mediaStats.savedAnime, label: "Anime saved"),
            ProfileStat(value: model.mediaStats.savedMovies, label: "Films saved"),
            ProfileStat(value: model.mediaStats.savedMatches, label: "Matches saved"),
            ProfileStat(
                value: model.mediaStats.animeEpisodesCompleted + model.mediaStats.movieUnitsCompleted,
                label: "Finished"
            ),
            ProfileStat(value: model.mediaStats.activityLast30Days, label: "Last 30 days"),
        ]

        return AccountSection(title: "Your Asterion", subtitle: "Everything you have saved, read, and watched.") {
            ViewThatFits(in: .horizontal) {
                ProfileStatRow(stats: stats)
                VStack(spacing: 0) {
                    ProfileStatRow(stats: Array(stats.prefix(3)))
                    Rectangle().fill(Color.asterionHairline).frame(height: 1)
                    ProfileStatRow(stats: Array(stats.suffix(3)))
                }
            }
            .asterionPanel(cornerRadius: 16)
        }
    }

    private var currentlyReading: some View {
        AccountSection(title: "Currently reading", subtitle: "Continue from your latest synced chapter.") {
            if model.continueReadingEntries.isEmpty {
                HStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(width: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your next story is waiting")
                            .font(.asterionDisplay(14.5, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                        Text("Open a novel and start reading to see it here.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.asterionMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .asterionPanel(cornerRadius: 14)
            } else {
                AccountRowPanel {
                    ForEach(Array(model.continueReadingEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { ActivityRowSeparator() }
                        ActivityTimelineRow(
                            imageURL: entry.novel.imageURL.flatMap(URL.init(string:)),
                            fallbackSystemImage: "book.closed",
                            title: entry.novel.title,
                            detail: readingDetail(entry),
                            fraction: min(1, max(0, entry.progress.percentage / 100)),
                            actionTitle: "Continue",
                            actionSystemImage: "book.fill",
                            actionAccessibilityLabel: "Continue reading \(entry.novel.title)"
                        ) {
                            openWindow(
                                value: ReaderRoute(
                                    novelID: entry.novel.id,
                                    chapterID: entry.progress.chapterId
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var continueWatching: some View {
        if !model.continueWatching.isEmpty {
            AccountSection(
                title: "Continue watching",
                subtitle: "Resume the latest episode or movie saved to your account."
            ) {
                AccountRowPanel {
                    ForEach(Array(model.continueWatching.prefix(4).enumerated()), id: \.element.id) { index, progress in
                        if index > 0 { ActivityRowSeparator() }
                        ActivityTimelineRow(
                            imageURL: progress.imageURL,
                            fallbackSystemImage: progress.mediaType.systemImage,
                            title: progress.title,
                            detail: ActivityDetail.playback(
                                title: progress.title,
                                unitTitle: progress.unitTitle,
                                seasonNumber: progress.seasonNumber,
                                episodeNumber: progress.episodeNumber,
                                mediaType: progress.mediaType,
                                positionSeconds: progress.positionSeconds,
                                durationSeconds: progress.durationSeconds,
                                completed: progress.completed
                            ),
                            fraction: min(1, max(0, progress.percentage / 100)),
                            canAct: progress.mediaType != .football,
                            select: { openPlayback(progress) },
                            selectHelp: "Continue \(progress.title)",
                            actionAccessibilityLabel: "Continue \(progress.title), \(progress.unitTitle ?? progress.mediaType.title)"
                        ) {
                            openPlayback(progress)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentViewing: some View {
        if !model.mediaHistory.isEmpty {
            AccountSection(
                title: "Watch history",
                subtitle: "Your latest anime episodes, series, and movies."
            ) {
                AccountRowPanel {
                    ForEach(Array(model.mediaHistory.prefix(6).enumerated()), id: \.element.id) { index, history in
                        if index > 0 { ActivityRowSeparator() }
                        ActivityTimelineRow(
                            imageURL: history.imageURL,
                            fallbackSystemImage: history.mediaType.systemImage,
                            title: history.title,
                            detail: historyDetail(history),
                            timestamp: history.lastViewedAt.formatted(.relative(presentation: .named)),
                            fraction: history.completed ? nil : min(1, max(0, history.percentage / 100)),
                            actionTitle: history.completed ? "Watch again" : "Resume",
                            actionSystemImage: history.completed ? "arrow.counterclockwise" : "play.fill",
                            canAct: history.mediaType != .football,
                            select: { openPlayback(history) },
                            selectHelp: "Watch \(history.title) again",
                            actionAccessibilityLabel: "Watch \(history.title), \(history.unitTitle ?? history.mediaType.title) again"
                        ) {
                            openPlayback(history)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var savedMedia: some View {
        if !model.mediaBookmarks.isEmpty {
            AccountSection(
                title: "Saved for later",
                subtitle: "Anime, movies, and matches bookmarked across Asterion."
            ) {
                AccountRowPanel {
                    ForEach(Array(model.mediaBookmarks.prefix(8).enumerated()), id: \.element.id) { index, bookmark in
                        if index > 0 { ActivityRowSeparator() }
                        MediaBookmarkRow(
                            bookmark: bookmark,
                            isUpdating: model.isUpdatingMediaBookmark(bookmark.key),
                            remove: {
                                Task { await model.toggleMediaBookmark(descriptor(for: bookmark)) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var accountActions: some View {
        AccountSection(title: "Account", subtitle: "Your identity, sync, and session on this Mac.") {
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.accountError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.asterionWarning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ActivityRowSeparator(leadingInset: 0)
                }

                AccountActionRow(
                    title: "Profile",
                    detail: "Name, photo, email, and security."
                ) {
                    Button {
                        presentsProfileEditor = true
                    } label: {
                        Label("Manage profile", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.asterionSecondary)
                }

                ActivityRowSeparator(leadingInset: 0)

                AccountActionRow(
                    title: "Automatic saving",
                    detail: "Bookmarks, reading position, watch progress, and history save on this Mac first, then sync to your account when available."
                ) {
                    EmptyView()
                }

                ActivityRowSeparator(leadingInset: 0)

                AccountActionRow(
                    title: "Sign out",
                    detail: "End the session on this Mac. Everything stays saved to your account."
                ) {
                    Button(role: .destructive) {
                        Task { await model.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.asterionSecondary)
                }
            }
            .asterionPanel(cornerRadius: 14)
        }
    }

    // MARK: Signed out and restoring

    private var restoringProfile: some View {
        AsterionEmptyState(
            systemImage: "person.crop.circle",
            title: "Restoring your profile",
            message: "Checking the saved account on this Mac."
        ) {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var restoreFailedProfile: some View {
        AsterionEmptyState(
            systemImage: "person.crop.circle.badge.exclamationmark",
            title: "Your profile could not be restored",
            message: "Asterion still has a saved account on this Mac, but the session did not come back. Try again, or sign in once more."
        ) {
            VStack(spacing: 16) {
                if let error = model.accountError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.asterionWarning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await model.retryAccountSessionRestore() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.asterionSecondary)

                    Button {
                        openWindow(id: "authentication")
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.asterionPrimary)
                }
            }
        }
    }

    private var signedOutProfile: some View {
        AsterionEmptyState(
            systemImage: "person.crop.circle",
            title: "Make Asterion yours",
            message: "A profile keeps saved stories, shows, films, matches, and every reading or watching position together."
        ) {
            VStack(spacing: 32) {
                VStack(spacing: 14) {
                    Button {
                        openWindow(id: "authentication")
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.asterionPrimary)
                    .help("Sign in or create an account")

                    if let error = model.accountError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.asterionWarning)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 420)
                    }
                }

                HStack(alignment: .top, spacing: 28) {
                    ProfileBenefit(icon: "bookmark", title: "Save anything", detail: "Keep novels, anime, movies, and matches together.")
                    ProfileBenefit(icon: "play.circle", title: "Never lose your place", detail: "Reading and watching progress follows your account.")
                    ProfileBenefit(icon: "chart.bar", title: "See your story", detail: "Your profile turns activity into useful personal stats.")
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: Helpers

    private func readingDetail(_ entry: AppModel.ContinueReadingEntry) -> String {
        let percent = "\(Int(min(100, max(0, entry.progress.percentage)).rounded()))%"
        let author = entry.novel.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? "Current chapter · \(percent)" : "\(author) · \(percent)"
    }

    private func historyDetail(_ history: MediaHistoryEntry) -> String {
        ActivityDetail.playback(
            title: history.title,
            unitTitle: history.unitTitle,
            seasonNumber: history.seasonNumber,
            episodeNumber: history.episodeNumber,
            mediaType: history.mediaType,
            positionSeconds: history.positionSeconds,
            durationSeconds: history.durationSeconds,
            completed: history.completed
        )
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
                switch model.accountSessionPresentation {
                case .signedIn:
                    if let user = model.signedInUser {
                        signedInAccount(user)
                    } else {
                        restoringAccount
                    }
                case .restoring:
                    restoringAccount
                case .restoreFailed:
                    restoreFailedAccount
                case .signedOut:
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

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.asterionTitle(24, weight: .heavy))
                .foregroundStyle(Color.asterionText)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.asterionMuted)
        }
    }

    private func errorLabel(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.asterionWarning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func signedInAccount(_ user: AppModel.SignedInUser) -> some View {
        Group {
            pageTitle("Account & sync", subtitle: "Manage your identity and Asterion session.")

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ReaderAvatar(user: user, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name)
                            .font(.asterionDisplay(17, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                        if let email = user.email {
                            Text(email)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.asterionMuted)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        SyncStatusChip(hasIssue: model.accountError != nil)
                            .padding(.top, 4)
                    }
                }

                Button {
                    presentsProfileEditor = true
                } label: {
                    Label("Manage profile", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.asterionPrimary)
            }
            .accountCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("Automatic saving")
                    .font(.asterionDisplay(15, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                AccountStatusRow(label: "Library", value: "\(model.libraryNovelIDs.count) saved")
                AccountStatusRow(label: "Reading progress", value: "\(model.continueReadingEntries.count) active")
                AccountStatusRow(label: "Media bookmarks", value: "\(model.mediaBookmarks.count) saved")
                AccountStatusRow(label: "Watch progress", value: "\(model.continueWatching.count) active")
                AccountStatusRow(label: "Watch history", value: "\(model.mediaStats.historyEntries) entries")
                Text("Asterion saves bookmarks, reading position, watch progress, and history on this Mac first, then sends them to your account when sync is available.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.asterionMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accountCard()

            if let error = model.accountError {
                errorLabel(error)
                    .accountCard()
            }

            Button(role: .destructive) {
                Task { await model.signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.asterionSecondary)
        }
    }

    private var signedOutAccount: some View {
        VStack(spacing: 0) {
            AsterionEmptyState(
                systemImage: "person.crop.circle",
                title: "Keep your place",
                message: "Create an account or sign in to sync bookmarks, reading progress, watch progress, and history."
            ) {
                VStack(spacing: 14) {
                    Button {
                        openWindow(id: "authentication")
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.asterionPrimary)
                    .help("Sign in or create an account")

                    if let error = model.accountError {
                        errorLabel(error)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    private var restoringAccount: some View {
        AsterionEmptyState(
            systemImage: "person.crop.circle",
            title: "Restoring your profile",
            message: "Checking the saved account on this Mac. This usually takes a moment after opening Asterion."
        ) {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var restoreFailedAccount: some View {
        AsterionEmptyState(
            systemImage: "person.crop.circle.badge.exclamationmark",
            title: "Profile could not be restored",
            message: "Your saved account is still on this Mac, but the session did not come back. Try again, or sign in once more to reconnect."
        ) {
            VStack(spacing: 14) {
                if let error = model.accountError {
                    errorLabel(error)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button("Try again") {
                        Task { await model.retryAccountSessionRestore() }
                    }
                    .buttonStyle(.asterionSecondary)

                    Button("Sign in") {
                        openWindow(id: "authentication")
                    }
                    .buttonStyle(.asterionPrimary)
                }
            }
        }
    }
}

struct AsterionAuthenticationView: View {
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in")
                    .font(.asterionTitle(24, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                Text("Sync bookmarks, history, and your place in every story.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
                        .strokeBorder(Color.asterionBorder, lineWidth: 1)
                }
        }
        .padding(24)
        .frame(width: 438, height: 548, alignment: .top)
        .background(Color.asterionMediaCanvas)
        .onChange(of: clerk.user?.id) {
            guard clerk.user != nil else { return }
            Task {
                await model.reconcileAuthenticationState()
                dismissWindow(id: "authentication")
            }
        }
    }
}

// MARK: - Components

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
                    .foregroundStyle(Color.asterionFaint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .padding(size * 0.06)
        .background {
            Circle()
                .fill(Color.white.opacity(0.035))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }
        .shadow(color: .white.opacity(0.08), radius: size * 0.2)
        .accessibilityLabel("Profile photo for \(user.name)")
    }
}

private struct SyncStatusChip: View {
    let hasIssue: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(hasIssue ? Color.asterionWarning : Color.asterionSuccess)
                .frame(width: 6, height: 6)
                .shadow(color: (hasIssue ? Color.asterionWarning : Color.asterionSuccess).opacity(0.7), radius: 3)
            Text(hasIssue ? "Needs attention" : "Synced")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.asterionText.opacity(0.88))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.asterionBorder))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasIssue ? "Signed in, sync needs attention" : "Signed in, synced")
    }
}

private struct AccountSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.asterionTitle(18, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            content()
        }
    }
}

private struct AccountRowPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .asterionPanel(cornerRadius: 14)
    }
}

private struct ProfileStat: Identifiable {
    let value: Int
    let label: String

    var id: String { label }
}

private struct ProfileStatRow: View {
    let stats: [ProfileStat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Color.asterionHairline)
                        .frame(width: 1)
                        .padding(.vertical, 16)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(stat.value, format: .number)
                        .font(.asterionTitle(30, weight: .heavy))
                        .foregroundStyle(Color.asterionText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .frame(minWidth: 112, idealWidth: 112, maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccountActionRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.asterionDisplay(14, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.asterionMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct MediaBookmarkRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let bookmark: MediaBookmark
    let isUpdating: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ActivityThumbnail(url: bookmark.imageURL, fallbackSystemImage: bookmark.mediaType.systemImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title)
                    .font(.asterionDisplay(14.5, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                Text(bookmark.subtitle ?? bookmark.mediaType.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button(action: remove) {
                if isUpdating {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(.asterionSecondary)
            .disabled(isUpdating)
            .help("Remove bookmark")
            .accessibilityLabel("Remove \(bookmark.title) from saved items")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(isHovering ? 0.04 : 0))
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
    }
}

private struct ProfileBenefit: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.asterionMuted)
                .frame(height: 22)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Color.asterionMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 160)
        .accessibilityElement(children: .combine)
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
                .font(.asterionMono(12.5, weight: .medium))
                .foregroundStyle(Color.asterionText)
        }
        .font(.system(size: 13))
    }
}

private extension View {
    func accountCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .asterionPanel(cornerRadius: 14)
    }
}
