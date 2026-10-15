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
        AsterionPageHeader(title: "Account")
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 12 : 0)
            .padding(.bottom, isDesktop ? 8 : 0)
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: isDesktop ? 90 : 60)

            Image(systemName: "person.crop.circle")
                .font(.system(size: isDesktop ? 68 : 48, weight: .light))
                .foregroundStyle(Color.asterionMuted)
                .padding(.top, 8)

            Text("Welcome to Asterion")
                .font(.asterionDisplay(isDesktop ? 34 : 28, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .padding(.top, 16)

            Text("Sign in to sync your library")
                .font(.asterionReading(16))
                .foregroundStyle(Color.asterionSynopsis)
                .padding(.top, 6)

            VStack(spacing: 12) {
                Button {
                    authSheetMode = .signIn
                    showAuthSheet = true
                } label: {
                    Text("Sign in")
                        .font(.asterionReading(isDesktop ? 18 : 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isDesktop ? 18 : 14)
                }
                .buttonStyle(AsterionFilledButtonStyle())

                Button {
                    authSheetMode = .createAccount
                    showAuthSheet = true
                } label: {
                    Text("Create account")
                        .font(.asterionReading(isDesktop ? 18 : 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isDesktop ? 18 : 14)
                }
                .buttonStyle(AsterionOutlineButtonStyle())
            }
            .frame(maxWidth: isDesktop ? 520 : .infinity)
            .padding(.horizontal, isDesktop ? 0 : 32)
            .padding(.top, 32)

            if !mediaAccountService.snapshot.bookmarks.isEmpty || !mediaAccountService.snapshot.progress.isEmpty {
                Text("Your guest saves and watch progress are ready to merge after sign-in.")
                    .font(.asterionSerif(14))
                    .foregroundStyle(Color.asterionMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
            }

            if let error = authService.authError {
                Text(error)
                    .font(.asterionMono(10))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.top, 12)
            }

            if let cloudSyncError {
                Text(cloudSyncError)
                    .font(.asterionMono(10))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
            }

            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signed In

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            avatarSection
            recentActivitySection
            readingStatisticsSection
            readingStatusSection
            readingPreferencesSection
            notificationsSection
            aboutSection
            footerBrand
        }
        .padding(.bottom, 24)
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        HStack(alignment: .center, spacing: 14) {
            avatarImage
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(cloudProfile?.username ?? authService.currentUser?.username ?? "Reader")
                    .font(.asterionReading(18, weight: .medium))
                    .foregroundStyle(Color.asterionText)

                Text(statsSentence)
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 20)
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
                    .font(.asterionDisplay(28, weight: .medium))
                    .foregroundStyle(Color.asterionText)
            }
    }

    private var statsSentence: String {
        let saved = libraryNovels.count + mediaAccountService.snapshot.bookmarks.count
        let inProgress = cloudProgressCount + mediaAccountService.snapshot.stats.titlesInProgress
        var parts = ["\(saved) saved", "\(inProgress) in progress"]
        if cloudChaptersRead > 0 {
            parts.append("\(cloudChaptersRead) chapters")
        }
        return parts.joined(separator: "  ·  ")
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
                caption: "\(Int(progress.percentage))% read  ·  \(date.formatted(.relative(presentation: .named)))",
                date: date
            )
        }
        // Preserve the latest reading session saved by earlier app versions, too.
        if let snapshot = ContinueReadingStore.loadSnapshot() {
            let id = "novel-\(snapshot.novelId)"
            if snapshot.updatedAt > (activityByID[id]?.date ?? .distantPast) {
                activityByID[id] = RecentActivity(
                    id: id, title: snapshot.novelTitle,
                    imageURL: novelsByID[snapshot.novelId]?.imageUrl.flatMap(URL.init(string:)),
                    caption: "\(snapshot.chapterTitle)  ·  \(snapshot.updatedAt.formatted(.relative(presentation: .named)))",
                    date: snapshot.updatedAt
                )
            }
        }
        let media = MediaHistoryEntry.latestPerTitle(mediaAccountService.snapshot.history).map { entry in
            RecentActivity(id: "media-\(entry.mediaType.rawValue)-\(entry.contentId)", title: entry.title, imageURL: entry.imageURL,
                           caption: activityCaption(for: entry), date: entry.lastViewedAt)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.asterionReading(15, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.bottom, 4)

                ForEach(activity) { entry in
                    HStack(alignment: .center, spacing: 14) {
                        MediaArtwork(url: entry.imageURL, width: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.asterionReading(16))
                                .foregroundStyle(Color.asterionText)
                                .lineLimit(2)
                            Text(entry.caption)
                                .font(.asterionReading(13))
                                .foregroundStyle(Color.asterionMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func activityCaption(for entry: MediaHistoryEntry) -> String {
        let unit = entry.unitTitle ?? (entry.completed ? "Finished" : "Watched")
        let when = entry.lastViewedAt.formatted(.relative(presentation: .named))
        return "\(unit)  ·  \(when)"
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

    // MARK: - Reading Status

    @ViewBuilder
    private var readingStatusSection: some View {
        if !libraryNovels.isEmpty {
            Text("\(ongoing) ongoing  ·  \(completed) finished  ·  \(unreadInLibrary) unread")
                .font(.asterionReading(14))
                .foregroundStyle(Color.asterionMuted)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Reading Preferences

    private var readingStatisticsSection: some View {
        let stats = readingActivityService.summary(history: readingHistory, goal: readingGoal)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Reading activity")
                .font(.asterionDisplay(24, weight: .medium))
                .foregroundStyle(Color.asterionText)
            Text("\(stats.weeklyChapters) of \(stats.goal) chapters this week")
                .font(.asterionReading(16))
                .foregroundStyle(Color.asterionText)
            ProgressView(value: stats.goalFraction)
                .tint(Color.asterionInk)
                .accessibilityLabel("Weekly reading goal")
                .accessibilityValue("\(stats.weeklyChapters) of \(stats.goal) chapters")
            HStack(alignment: .top, spacing: 20) {
                readingMetric(timeLabel(stats.todaySeconds), label: "Reading today")
                readingMetric(timeLabel(stats.weeklySeconds), label: "This week")
                readingMetric("\(stats.streak)", label: "Day streak")
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.bottom, 28)
    }

    private func timeLabel(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 60 { return "<1 min" }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }

    private func readingMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.asterionDisplay(26, weight: .medium)).foregroundStyle(Color.asterionText)
            Text(label).font(.asterionReading(13)).foregroundStyle(Color.asterionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readingPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsterionSectionLabel(title: "Reading")
                .padding(.horizontal, pageHorizontalPadding)

            settingsRow(label: "Font size", sublabel: fontSizePref.rawValue.capitalized) {
                HStack(spacing: 8) {
                    ForEach(FontSizePref.allCases, id: \.self) { size in
                        Button { fontSizePref = size } label: {
                            Text("A")
                                .font(.asterionReading(size == .small ? 13 : size == .medium ? 16 : 19, weight: .medium))
                                .foregroundStyle(fontSizePref == size ? Color.asterionOnInk : Color.asterionText)
                                .frame(width: 36, height: 36)
                                .background(
                                    fontSizePref == size ? Color.asterionInk : Color.asterionCard,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            settingsRow(label: "Weekly goal", sublabel: "\(readingGoal) chapters") {
                HStack(spacing: 16) {
                    Button("–") { readingGoal = max(5, readingGoal - 5) }
                    Text("\(readingGoal)")
                        .font(.asterionReading(16, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .monospacedDigit()
                        .frame(minWidth: 24)
                    Button("+") { readingGoal = min(100, readingGoal + 5) }
                }
                .font(.asterionReading(20, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .buttonStyle(.plain)
            }

            settingsRow(label: "Appearance", sublabel: "Follows the device", showBorder: false) {
                Text("System")
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsterionSectionLabel(title: "Notifications")
                .padding(.horizontal, pageHorizontalPadding)

            settingsRow(label: "New chapters", sublabel: "When a saved novel updates") {
                Toggle("", isOn: Binding(get: { notificationsOn }, set: { enabled in
                    notificationsOn = enabled
                    Task { await contentNotifications.setEnabled(enabled, kind: .novel) }
                }))
                    .tint(Color.asterionInk)
                    .labelsHidden()
                    .accessibilityLabel("New chapter alerts")
            }

            settingsRow(label: "New episodes", sublabel: "When a saved anime updates") {
                Toggle("", isOn: Binding(get: { contentNotifications.episodeAlerts }, set: { enabled in
                    Task { await contentNotifications.setEnabled(enabled, kind: .anime) }
                }))
                .tint(Color.asterionInk)
                .labelsHidden()
                .accessibilityLabel("New anime episode alerts")
            }
            if contentNotifications.permissionDenied {
                Button("Allow notifications in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.asterionReading(14))
                .foregroundStyle(Color.asterionInk)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.vertical, 12)
            }

            settingsRow(label: "Siri Shortcuts", sublabel: "Open the last chapter from Siri", showBorder: false) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsterionSectionLabel(title: "About")
                .padding(.horizontal, pageHorizontalPadding)

            ForEach(Array(["Widget setup", "Rate Asterion", "Privacy policy", "Terms of service"].enumerated()), id: \.offset) { index, item in
                settingsRow(label: item, showBorder: index < 3) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.asterionMuted)
                }
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: - Footer

    private var footerBrand: some View {
        VStack(spacing: 16) {
            Button("Sign out") {
                authService.signOut()
                apiClient.setSessionToken(nil)
            }
            .font(.asterionReading(15, weight: .medium))
            .foregroundStyle(Color.asterionText)
            .buttonStyle(.plain)

            Text("Asterion  ·  \(appVersion)")
                .font(.asterionReading(13))
                .foregroundStyle(Color.asterionMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Settings Row Helper

    private func settingsRow<Trailing: View>(
        label: String,
        sublabel: String? = nil,
        showBorder: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.asterionReading(16))
                    .foregroundStyle(Color.asterionText)
                if let sublabel {
                    Text(sublabel)
                        .font(.asterionReading(13))
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.vertical, 14)
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
                    Text(needsVerificationCode ? "Verify Email" : (isCreatingAccount ? "Create Account" : "Sign In"))
                        .font(.asterionSerif(34, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(needsVerificationCode ? "Enter the code Clerk sent to your email." : "Use your Asterion email and password.")
                        .font(.asterionSerif(17))
                        .foregroundStyle(Color.asterionDim)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.asterionDim)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.asterionCard))
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
                    .font(.asterionMono(12))
                    .foregroundStyle(Color.red.opacity(0.9))
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
                            .tint(Color.asterionBackground)
                    }
                    Text(buttonTitle)
                        .font(.asterionSerif(20, weight: .medium))
                }
                .foregroundStyle(Color.asterionBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSubmit ? Color.goldAccent : Color.goldAccent.opacity(0.45))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            if !needsVerificationCode {
                Button {
                    toggleAuthMode()
                } label: {
                    Text(isCreatingAccount ? "Already have an account? Sign in" : "New to Asterion? Create an account")
                        .font(.asterionSerif(16))
                        .foregroundStyle(Color.goldAccent)
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
        if needsVerificationCode { return "Verify and Continue" }
        return isCreatingAccount ? "Create Account" : "Sign In"
    }

    private func authField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionDim)
                .tracking(1.5)
            TextField(title, text: text)
                .textContentType(title == "Email" ? .emailAddress : .oneTimeCode)
                .textFieldStyle(.plain)
                .font(.asterionSerif(19))
                .foregroundStyle(Color.asterionText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.asterionCard)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
        }
    }

    private func secureAuthField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionDim)
                .tracking(1.5)
            SecureField(title, text: text)
                .textContentType(.password)
                .textFieldStyle(.plain)
                .font(.asterionSerif(19))
                .foregroundStyle(Color.asterionText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.asterionCard)
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
