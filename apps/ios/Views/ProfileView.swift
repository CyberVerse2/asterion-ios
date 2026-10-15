import ClerkKit
import ClerkKitUI
import Inject
import SwiftUI

struct ProfileView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var readingActivityService: ReadingActivityService
    @EnvironmentObject private var contentNotifications: ContentNotificationService
    @Environment(\.openURL) private var openURL
    @State private var libraryNovels: [Novel] = []
    @State private var activityNovels: [Novel] = []
    @State private var readingProgress: [ReadingProgress] = []
    @State private var readingHistory: [AsterionReadingHistoryEntry] = []
    @State private var readingGoal: Int = 30
    @State private var notificationsOn = true
    @State private var fontSizePref: FontSizePref = .medium
    @State private var showAuthSheet = false
    @State private var authSheetMode: DesktopAuthMode = .signIn
    @State private var cloudProfile: AsterionUserProfile?
    @State private var cloudBookmarkCount = 0
    @State private var cloudProgressCount = 0
    @State private var cloudChaptersRead = 0
    @State private var cloudSyncError: String?
    @State private var isApplyingServerPreferences = false
    @State private var startedNovelIds: Set<String> = []
    @State private var completedNovelIds: Set<String> = []
    @AppStorage(DownloadAheadCoordinator.enabledKey) private var downloadAheadEnabled = true
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var contentMaxWidth: CGFloat { AsterionLayout.pageMaxWidth(horizontalSizeClass) }
    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    enum FontSizePref: String, CaseIterable { case small, medium, large }

    private var ongoing: Int {
        let libraryIds = Set(libraryNovels.map(\.id))
        return startedNovelIds
            .intersection(libraryIds)
            .subtracting(completedNovelIds)
            .count
    }
    private var completed: Int {
        let libraryIds = Set(libraryNovels.map(\.id))
        return completedNovelIds.intersection(libraryIds).count
    }
    private var unreadInLibrary: Int {
        max(libraryNovels.count - ongoing - completed, 0)
    }
    private var totalChapters: Int {
        libraryNovels.reduce(0) { sum, n in
            sum + (Int(n.totalChapters?.filter(\.isNumber) ?? "") ?? 0)
        }
    }
    private var avgRating: String {
        guard !libraryNovels.isEmpty else { return "—" }
        let avg = libraryNovels.compactMap(\.rating).reduce(0, +) / Double(libraryNovels.count)
        return String(format: "%.1f", avg)
    }
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageTitleSection
                    if authService.isSignedIn {
                        signedInContent
                    } else {
                        signedOutContent
                    }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .asterionStatusBarScrim()
            .background { AsterionBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadCloudProfileData() }
            .task(id: authService.isSignedIn) {
                await loadCloudProfileData()
            }
            .onChange(of: tabBarState.selectedTab) { _, tab in
                guard tab == .account else { return }
                Task { await loadCloudProfileData() }
            }
        }
        .sheet(isPresented: $showAuthSheet, onDismiss: {
            Task {
                await authService.syncClerkSession()
                apiClient.setSessionToken(authService.sessionToken)
                await authService.syncUserProfileToBackend(using: apiClient)
                await loadCloudProfileData()
            }
        }) {
            #if targetEnvironment(macCatalyst)
            DesktopAuthSheet(mode: authSheetMode)
                .environmentObject(authService)
                .environmentObject(apiClient)
            #else
            AuthView()
                .environment(Clerk.shared)
            #endif
        }
        .onChange(of: readingGoal) { _, _ in
            Task { await pushPreferencesToCloud() }
        }
        .onChange(of: notificationsOn) { _, _ in
            Task { await pushPreferencesToCloud() }
        }
        .onChange(of: fontSizePref) { _, _ in
            Task { await pushPreferencesToCloud() }
        }
        .enableInjection()
    }

    private var pageTitleSection: some View {
        AsterionPageHeader(
            title: "Account",
            subtitle: authService.isSignedIn && cloudChaptersRead > 0 ? "\(cloudChaptersRead) chapters read" : nil
        )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 12 : 0)
            .padding(.bottom, isDesktop ? 8 : 0)
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: isDesktop ? 72 : 40)

            Image(systemName: "person.crop.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.asterionMuted)
                .frame(width: 84, height: 84)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.035))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.09)))
                }

            Text("Welcome to Asterion")
                .font(.asterionTitle(isDesktop ? 30 : 26, weight: .heavy))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.top, 20)

            Text("Sign in to keep your library, progress, and downloads in step across devices.")
                .font(.asterionReading(15))
                .foregroundStyle(Color.asterionMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 8)

            VStack(spacing: 12) {
                Button {
                    authSheetMode = .signIn
                    showAuthSheet = true
                } label: {
                    Text("Sign in")
                        .font(.asterionReading(isDesktop ? 17 : 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isDesktop ? 16 : 14)
                }
                .buttonStyle(AsterionFilledButtonStyle())

                Button {
                    authSheetMode = .createAccount
                    showAuthSheet = true
                } label: {
                    Text("Create account")
                        .font(.asterionReading(isDesktop ? 17 : 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isDesktop ? 16 : 14)
                }
                .buttonStyle(AsterionOutlineButtonStyle())
            }
            .frame(maxWidth: isDesktop ? 420 : .infinity)
            .padding(.horizontal, isDesktop ? 0 : 32)
            .padding(.top, 30)

            if !mediaAccountService.snapshot.bookmarks.isEmpty || !mediaAccountService.snapshot.progress.isEmpty {
                Text("Your guest saves and watch progress are ready to merge after sign-in.")
                    .font(.asterionReading(13.5))
                    .foregroundStyle(Color.asterionMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
            }

            if let error = authService.authError {
                statusMessage(error)
                    .padding(.top, 14)
            }

            if let cloudSyncError {
                statusMessage(cloudSyncError)
                    .padding(.top, 10)
            }

            downloadsSection
                .padding(.top, 40)

            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.asterionReading(12.5, weight: .medium))
            .foregroundStyle(Color.asterionWarning)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    // MARK: - Signed In

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
            avatarSection
            statisticsSection
            recentActivitySection
            readingPreferencesSection
            downloadsSection
            notificationsSection
            aboutSection
            footerBrand
        }
        .padding(.top, 18)
        .padding(.bottom, 40)
    }

    // MARK: - Profile header

    private var displayName: String {
        cloudProfile?.username ?? authService.currentUser?.username ?? "Reader"
    }

    private var displayEmail: String? {
        let email = cloudProfile?.email ?? authService.currentUser?.email
        guard let email, !email.isEmpty else { return nil }
        return email
    }

    private var avatarSection: some View {
        HStack(alignment: .center, spacing: 18) {
            avatarImage
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                .padding(5)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.035))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.09)))
                }
                .shadow(color: .white.opacity(0.08), radius: 16)
                .accessibilityLabel("Profile photo for \(displayName)")

            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.asterionTitle(26, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)

                if let displayEmail {
                    Text(displayEmail)
                        .font(.asterionReading(13.5))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                SyncChip(hasIssue: cloudSyncError != nil)
                    .padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pageHorizontalPadding)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let pfp = cloudProfile?.avatarUrl ?? authService.currentUser?.pfpUrl, let url = URL(string: pfp) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallback
                }
            }
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Color.asterionCard
            .overlay {
                Text(initials)
                    .font(.asterionTitle(28, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
            }
    }

    private var initials: String {
        let name = cloudProfile?.username ?? authService.currentUser?.username
        guard let name, !name.isEmpty else { return "A" }
        return String(name.prefix(1)).uppercased()
    }

    private struct RecentActivity: Identifiable {
        let id: String
        let title: String
        let imageURL: URL?
        let caption: String
        let date: Date
        var progress: Double? = nil
    }

    private var recentActivity: [RecentActivity] {
        var novelsByID: [String: Novel] = [:]
        for novel in activityNovels + libraryNovels { novelsByID[novel.id] = novel }
        var activityByID: [String: RecentActivity] = [:]
        for progress in readingProgressService.mergedProgress(with: readingProgress) {
            guard let novel = novelsByID[progress.novelId], let date = progress.lastReadAt else { continue }
            let id = "novel-\(novel.id)"
            activityByID[id] = RecentActivity(
                id: id, title: novel.title, imageURL: novel.imageUrl.flatMap(URL.init(string:)),
                caption: "\(Int(progress.percentage))% read · \(date.formatted(.relative(presentation: .named)))",
                date: date,
                progress: progress.percentage / 100
            )
        }
        // Preserve the latest reading session saved by earlier app versions, too.
        if let snapshot = ContinueReadingStore.loadSnapshot() {
            let id = "novel-\(snapshot.novelId)"
            if snapshot.updatedAt > (activityByID[id]?.date ?? .distantPast) {
                activityByID[id] = RecentActivity(
                    id: id, title: snapshot.novelTitle,
                    imageURL: novelsByID[snapshot.novelId]?.imageUrl.flatMap(URL.init(string:)),
                    caption: "\(snapshot.chapterTitle) · \(snapshot.updatedAt.formatted(.relative(presentation: .named)))",
                    date: snapshot.updatedAt
                )
            }
        }
        let media = MediaHistoryEntry.latestPerTitle(mediaAccountService.snapshot.history).map { entry in
            RecentActivity(id: "media-\(entry.mediaType.rawValue)-\(entry.contentId)", title: entry.title, imageURL: entry.imageURL,
                           caption: activityCaption(for: entry), date: entry.lastViewedAt,
                           progress: entry.completed ? 1 : entry.percentage / 100)
        }
        return Array((Array(activityByID.values) + media).sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date > $1.date
        }.prefix(6))
    }

    @ViewBuilder
    private var recentActivitySection: some View {
        let activity = recentActivity
        if !activity.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                AsterionSectionLabel(title: "Reading and watching", detail: "Most recent first")

                VStack(spacing: 0) {
                    ForEach(Array(activity.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .center, spacing: 14) {
                            MediaArtwork(url: entry.imageURL, width: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.asterionReading(14.5, weight: .semibold))
                                    .foregroundStyle(Color.asterionText)
                                    .lineLimit(1)
                                Text(entry.caption)
                                    .font(.asterionReading(12.5))
                                    .foregroundStyle(Color.asterionMuted)
                                    .lineLimit(1)
                                if let progress = entry.progress, progress > 0 {
                                    AsterionLightLine(fraction: progress, height: 2.5)
                                        .padding(.top, 6)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) {
                            if index > 0 { hairline.padding(.leading, 14 + 44 + 14) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .asterionPanel(cornerRadius: 16)
            }
            .padding(.horizontal, pageHorizontalPadding)
        }
    }

    private func activityCaption(for entry: MediaHistoryEntry) -> String {
        let unit = entry.unitTitle ?? (entry.completed ? "Finished" : "Watched")
        let when = entry.lastViewedAt.formatted(.relative(presentation: .named))
        return "\(unit) · \(when)"
    }

    private func loadCloudProfileData() async {
        guard authService.isSignedIn else {
            cloudProfile = nil
            cloudBookmarkCount = 0
            cloudProgressCount = 0
            cloudChaptersRead = 0
            libraryNovels = []
            activityNovels = []
            readingProgress = []
            readingHistory = []
            startedNovelIds = []
            completedNovelIds = []
            cloudSyncError = nil
            return
        }

        if activityNovels.isEmpty {
            activityNovels = await OfflineChapterStore.shared.loadCatalog()
        }

        do {
            async let profileFetch = apiClient.fetchMyProfile()
            async let statsFetch = apiClient.fetchMyStats()
            async let prefsFetch = apiClient.fetchMyPreferences()
            async let libraryFetch = apiClient.fetchMyLibrary()
            async let allNovelsFetch = apiClient.fetchAllNovels()
            async let progressFetch = apiClient.fetchAllReadingProgress()
            async let historyFetch = fetchAllReadingHistory()

            cloudProfile = try await profileFetch
            let stats = try await statsFetch
            let prefs = try await prefsFetch
            let libraryItems = try await libraryFetch
            let allNovels = try await allNovelsFetch
            let progressList = try await progressFetch
            let history = try await historyFetch
            readingHistory = history
            activityNovels = allNovels
            readingProgress = progressList

            cloudBookmarkCount = stats.bookmarks
            cloudProgressCount = stats.novelsInProgress
            cloudChaptersRead = stats.chaptersRead

            let libraryIds = Set(libraryItems.map(\.novelId))
            libraryNovels = allNovels.filter { libraryIds.contains($0.id) }

            let startedFromProgress = Set(progressList.map(\.novelId))
            let startedFromHistory = Set(history.map(\.novelId))
            startedNovelIds = startedFromProgress.union(startedFromHistory)

            var distinctChapterCountsByNovel: [String: Set<String>] = [:]
            for entry in history {
                distinctChapterCountsByNovel[entry.novelId, default: []].insert(entry.chapterId)
            }

            var completedIds: Set<String> = []
            for novel in allNovels {
                let totalChapters = Int(novel.totalChapters?.filter(\.isNumber) ?? "") ?? 0
                guard totalChapters > 0 else { continue }
                let readCount = distinctChapterCountsByNovel[novel.id]?.count ?? 0
                if readCount >= totalChapters {
                    completedIds.insert(novel.id)
                }
            }
            completedNovelIds = completedIds

            isApplyingServerPreferences = true
            readingGoal = prefs.readingGoal
            notificationsOn = prefs.notificationsOn
            await contentNotifications.setEnabled(prefs.notificationsOn, kind: .novel, askPermission: false)
            fontSizePref = FontSizePref(rawValue: prefs.fontSizePref) ?? .medium
            isApplyingServerPreferences = false
            cloudSyncError = nil
        } catch {
            cloudSyncError = "Cloud sync is temporarily unavailable. Your on-device activity is safe."
        }
    }

    private func fetchAllReadingHistory() async throws -> [AsterionReadingHistoryEntry] {
        var all: [AsterionReadingHistoryEntry] = []
        let pageSize = 50
        var offset = 0
        while true {
            let chunk = try await apiClient.fetchReadingHistory(limit: pageSize, offset: offset)
            if chunk.isEmpty { break }
            all.append(contentsOf: chunk)
            if chunk.count < pageSize { break }
            offset += pageSize
            // Guard against unexpected infinite loops.
            if offset > 50_000 { break }
        }
        return all
    }

    private func pushPreferencesToCloud() async {
        guard authService.isSignedIn, !isApplyingServerPreferences else { return }
        do {
            _ = try await apiClient.updateMyPreferences(
                readingGoal: readingGoal,
                darkMode: nil,
                notificationsOn: notificationsOn,
                fontSizePref: fontSizePref.rawValue
            )
            cloudSyncError = nil
        } catch {
            cloudSyncError = "Couldn't save reading preferences to cloud."
        }
    }

    // MARK: - Statistics

    /// One panel: what is saved, what is underway, and this week's reading.
    private var statisticsSection: some View {
        let activity = readingActivityService.summary(history: readingHistory, goal: readingGoal)
        let saved = libraryNovels.count + mediaAccountService.snapshot.bookmarks.count
        let inProgress = ongoing + mediaAccountService.snapshot.stats.titlesInProgress

        return VStack(alignment: .leading, spacing: 14) {
            AsterionSectionLabel(
                title: "Your Asterion",
                detail: libraryNovels.isEmpty ? nil : "\(unreadInLibrary) unread"
            )

            VStack(spacing: 0) {
                statRow([
                    ("\(saved)", "Saved"),
                    ("\(inProgress)", "In progress"),
                    ("\(completed)", "Finished"),
                ])
                hairline
                statRow([
                    (timeLabel(activity.todaySeconds), "Today"),
                    (timeLabel(activity.weeklySeconds), "This week"),
                    ("\(activity.streak)", "Day streak"),
                ])
                hairline
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Weekly goal")
                            .font(.asterionReading(13.5, weight: .medium))
                            .foregroundStyle(Color.asterionText)
                        Spacer(minLength: 8)
                        Text("\(activity.weeklyChapters) of \(activity.goal) chapters")
                            .font(.asterionMono(12, weight: .medium))
                            .foregroundStyle(Color.asterionMuted)
                    }
                    AsterionLightLine(fraction: activity.goalFraction, height: 3)
                        .accessibilityLabel("Weekly reading goal")
                        .accessibilityValue("\(activity.weeklyChapters) of \(activity.goal) chapters")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .asterionPanel(cornerRadius: 16)
        }
        .padding(.horizontal, pageHorizontalPadding)
    }

    private func statRow(_ items: [(value: String, label: String)]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 5) {
                    Text(item.value)
                        .font(.asterionTitle(22, weight: .heavy))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.label)
                        .font(.asterionReading(12))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .overlay(alignment: .leading) {
                    if index > 0 {
                        Rectangle()
                            .fill(Color.asterionHairline)
                            .frame(width: 1, height: 32)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 18)
    }

    private func timeLabel(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 60 { return "<1 min" }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.asterionHairline)
            .frame(height: 1)
    }

    // MARK: - Reading Preferences

    private var readingPreferencesSection: some View {
        settingsGroup(title: "Reading") {
            settingsRow(label: "Font size", sublabel: fontSizePref.rawValue.capitalized) {
                HStack(spacing: 6) {
                    ForEach(FontSizePref.allCases, id: \.self) { size in
                        let selected = fontSizePref == size
                        Button {
                            if fontSizePref != size { Haptics.selection() }
                            fontSizePref = size
                        } label: {
                            Text("A")
                                .font(.asterionReading(size == .small ? 12 : size == .medium ? 15 : 18, weight: .semibold))
                                .foregroundStyle(selected ? Color.asterionOnInk : Color.asterionText)
                                .frame(width: 34, height: 34)
                                .background(selected ? Color.asterionInk : Color.white.opacity(0.06), in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0 : 0.08)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(size.rawValue.capitalized) font size")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            settingsRow(label: "Weekly goal", sublabel: "Chapters to read each week") {
                HStack(spacing: 10) {
                    stepButton(systemName: "minus", label: "Decrease weekly goal") {
                        readingGoal = max(5, readingGoal - 5)
                    }
                    Text("\(readingGoal)")
                        .font(.asterionMono(15, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .frame(minWidth: 28)
                    stepButton(systemName: "plus", label: "Increase weekly goal") {
                        readingGoal = min(100, readingGoal + 5)
                    }
                }
            }

            settingsRow(label: "Appearance", sublabel: "The reader keeps its own page themes", showBorder: false) {
                Text("Dark")
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        settingsGroup(title: "Downloads") {
            settingsRow(
                label: "Download ahead",
                sublabel: "Keep the next \(DownloadAheadCoordinator.chaptersAhead) chapters and the next \(DownloadAheadCoordinator.episodesAhead) episodes ready offline, on Wi-Fi",
                showBorder: false
            ) {
                Toggle("", isOn: $downloadAheadEnabled)
                    .tint(Color.asterionSuccess)
                    .labelsHidden()
                    .accessibilityLabel("Download ahead")
            }
        }
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.asterionText)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(Color.asterionBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsGroup(title: "Notifications") {
            settingsRow(label: "New chapters", sublabel: "When a saved novel updates") {
                Toggle("", isOn: Binding(get: { notificationsOn }, set: { enabled in
                    notificationsOn = enabled
                    Task { await contentNotifications.setEnabled(enabled, kind: .novel) }
                }))
                    .tint(Color.asterionSuccess)
                    .labelsHidden()
                    .accessibilityLabel("New chapter alerts")
            }

            settingsRow(label: "New episodes", sublabel: "When a saved anime updates") {
                Toggle("", isOn: Binding(get: { contentNotifications.episodeAlerts }, set: { enabled in
                    Task { await contentNotifications.setEnabled(enabled, kind: .anime) }
                }))
                .tint(Color.asterionSuccess)
                .labelsHidden()
                .accessibilityLabel("New anime episode alerts")
            }

            if contentNotifications.permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Notifications are off. Allow them in Settings")
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.asterionReading(13.5, weight: .medium))
                    .foregroundStyle(Color.asterionWarning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) { hairline.padding(.leading, 16) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            settingsRow(label: "Siri Shortcuts", sublabel: "Open the last chapter from Siri", showBorder: false) {
                chevron
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsGroup(title: "About") {
            ForEach(Array(["Widget setup", "Rate Asterion", "Privacy policy", "Terms of service"].enumerated()), id: \.offset) { index, item in
                settingsRow(label: item, showBorder: index < 3) {
                    chevron
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.asterionFaint)
    }

    // MARK: - Footer

    private var footerBrand: some View {
        VStack(spacing: 14) {
            Button(role: .destructive) {
                authService.signOut()
                apiClient.setSessionToken(nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                    Text("Sign out")
                        .font(.asterionReading(15, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .asterionPanel(cornerRadius: 16)

            Text("Asterion · \(appVersion)")
                .font(.asterionMono(11.5))
                .foregroundStyle(Color.asterionFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, pageHorizontalPadding)
    }

    // MARK: - Settings Helpers

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AsterionSectionLabel(title: title)
            VStack(spacing: 0) {
                content()
            }
            .asterionPanel(cornerRadius: 16)
        }
        .padding(.horizontal, pageHorizontalPadding)
    }

    private func settingsRow<Trailing: View>(
        label: String,
        sublabel: String? = nil,
        showBorder: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.asterionReading(15, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                if let sublabel {
                    Text(sublabel)
                        .font(.asterionReading(12.5))
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if showBorder { hairline.padding(.leading, 16) }
        }
    }
}

/// Small smoked chip: a green dot when the account is in sync.
private struct SyncChip: View {
    let hasIssue: Bool

    var body: some View {
        let tint = hasIssue ? Color.asterionWarning : Color.asterionSuccess
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.7), radius: 3)
            Text(hasIssue ? "Needs attention" : "Synced")
                .font(.asterionReading(11.5, weight: .semibold))
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

private enum DesktopAuthMode {
    case signIn
    case createAccount
}

#if targetEnvironment(macCatalyst)
private struct DesktopAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var apiClient: APIClient

    @State private var activeMode: DesktopAuthMode
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var pendingSignUp: SignUp?
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(mode: DesktopAuthMode) {
        _activeMode = State(initialValue: mode)
    }

    private var isCreatingAccount: Bool {
        activeMode == .createAccount
    }

    private var needsVerificationCode: Bool {
        pendingSignUp != nil
    }

    private var canSubmit: Bool {
        if needsVerificationCode {
            !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
        } else {
            !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !isWorking
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(needsVerificationCode ? "Verify email" : (isCreatingAccount ? "Create account" : "Sign in"))
                        .font(.asterionTitle(28, weight: .heavy))
                        .foregroundStyle(Color.asterionText)
                    Text(needsVerificationCode ? "Enter the code Clerk sent to your email." : "Use your Asterion email and password.")
                        .font(.asterionReading(15))
                        .foregroundStyle(Color.asterionMuted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Color.asterionBorder))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 14) {
                if needsVerificationCode {
                    authField(title: "Verification Code", text: $verificationCode)
                } else {
                    authField(title: "Email", text: $email)
                    secureAuthField(title: "Password", text: $password)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.asterionReading(12.5, weight: .medium))
                    .foregroundStyle(Color.asterionWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    if needsVerificationCode {
                        await verifySignUpCode()
                    } else if isCreatingAccount {
                        await createAccount()
                    } else {
                        await signIn()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.asterionOnInk)
                    }
                    Text(buttonTitle)
                        .font(.asterionReading(16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(AsterionFilledButtonStyle())
            .disabled(!canSubmit)

            if !needsVerificationCode {
                Button {
                    toggleAuthMode()
                } label: {
                    Text(isCreatingAccount ? "Already have an account? Sign in" : "New to Asterion? Create an account")
                        .font(.asterionReading(14, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(34)
        .frame(width: 560)
        .background(Color.asterionBackground)
    }

    private var buttonTitle: String {
        if needsVerificationCode { return "Verify and continue" }
        return isCreatingAccount ? "Create account" : "Sign in"
    }

    private func authField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold).width(.expanded))
                .foregroundStyle(Color.asterionMuted)
                .tracking(1.3)
            TextField(title, text: text)
                .textContentType(title == "Email" ? .emailAddress : .oneTimeCode)
                .textFieldStyle(.plain)
                .font(.asterionReading(16))
                .foregroundStyle(Color.asterionText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.asterionSurface)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
        }
    }

    private func secureAuthField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold).width(.expanded))
                .foregroundStyle(Color.asterionMuted)
                .tracking(1.3)
            SecureField(title, text: text)
                .textContentType(.password)
                .textFieldStyle(.plain)
                .font(.asterionReading(16))
                .foregroundStyle(Color.asterionText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.asterionSurface)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
        }
    }

    private func signIn() async {
        await runAuthAction {
            _ = try? await Clerk.shared.refreshClient()
            let signIn = try await Clerk.shared.auth.signInWithPassword(
                identifier: normalizedEmail,
                password: password
            )
            guard signIn.status == .complete, let sessionId = signIn.createdSessionId else {
                throw DesktopAuthError.unsupportedStep("This account needs another sign-in step before desktop can continue.")
            }
            try await activateSession(sessionId)
        }
    }

    private func createAccount() async {
        await runAuthAction {
            _ = try? await Clerk.shared.refreshClient()
            let signUp = try await Clerk.shared.auth.signUp(
                emailAddress: normalizedEmail,
                password: password
            )
            switch signUp.status {
            case .complete:
                guard let sessionId = signUp.createdSessionId else {
                    throw DesktopAuthError.unsupportedStep("Your account was created, but Clerk did not return a session.")
                }
                try await activateSession(sessionId)
            case .missingRequirements:
                pendingSignUp = try await signUp.sendEmailCode()
            default:
                throw DesktopAuthError.unsupportedStep("This account needs another setup step before desktop can continue.")
            }
        }
    }

    private func verifySignUpCode() async {
        await runAuthAction {
            guard let pendingSignUp else { return }
            let verifiedSignUp = try await pendingSignUp.verifyEmailCode(normalizedCode)
            guard verifiedSignUp.status == .complete, let sessionId = verifiedSignUp.createdSessionId else {
                throw DesktopAuthError.unsupportedStep("That code was accepted, but the account is not ready yet.")
            }
            try await activateSession(sessionId)
        }
    }

    private func runAuthAction(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await action()
        } catch let error as DesktopAuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activateSession(_ sessionId: String) async throws {
        try await Clerk.shared.auth.setActive(sessionId: sessionId)
        await authService.syncClerkSession()
        apiClient.setSessionToken(authService.sessionToken)
        await authService.syncUserProfileToBackend(using: apiClient)
        dismiss()
    }

    private func toggleAuthMode() {
        activeMode = isCreatingAccount ? .signIn : .createAccount
        errorMessage = nil
        email = ""
        password = ""
        verificationCode = ""
        pendingSignUp = nil
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedCode: String {
        verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum DesktopAuthError: LocalizedError {
    case unsupportedStep(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedStep(let message):
            message
        }
    }
}
#endif
