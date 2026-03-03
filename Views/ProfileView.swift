import ClerkKitUI
import Inject
import SwiftUI

struct ProfileView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var apiClient: APIClient
    @State private var libraryNovels: [Novel] = []
    @State private var readingGoal: Int = 30
    @State private var darkMode = true
    @State private var notificationsOn = true
    @State private var fontSizePref: FontSizePref = .medium
    @State private var showAuthSheet = false
    @State private var cloudProfile: AsterionUserProfile?
    @State private var cloudBookmarkCount = 0
    @State private var cloudProgressCount = 0
    @State private var cloudChaptersRead = 0
    @State private var cloudSyncError: String?
    @State private var isApplyingServerPreferences = false
    @State private var startedNovelIds: Set<String> = []
    @State private var completedNovelIds: Set<String> = []

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
            }
            .background(Color.asterionBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadCloudProfileData()
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
            AuthView()
        }
        .onChange(of: readingGoal) { _, _ in
            Task { await pushPreferencesToCloud() }
        }
        .onChange(of: darkMode) { _, _ in
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
        Text("Profile")
            .font(.asterionSerif(42, weight: .semibold))
            .foregroundStyle(Color.asterionText)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.goldAccent.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.asterionDim)
            }

            Text("Welcome to Asterion")
                .font(.asterionSerif(22, weight: .light))
                .foregroundStyle(Color.asterionText)
                .padding(.top, 16)

            Text("SIGN IN TO TRACK YOUR READING")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
                .padding(.top, 6)

            VStack(spacing: 12) {
                Button {
                    showAuthSheet = true
                } label: {
                    Text("Sign In")
                        .font(.asterionSerif(16, weight: .medium))
                        .foregroundStyle(Color.asterionBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.goldAccent)
                        )
                }

                Button {
                    showAuthSheet = true
                } label: {
                    Text("Create Account")
                        .font(.asterionSerif(16, weight: .medium))
                        .foregroundStyle(Color.goldAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.clear)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)

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
            accountSection
            statsGrid
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
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.goldAccent.opacity(0.14), Color.goldAccent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .stroke(Color.asterionBorder, lineWidth: 1)
                    .frame(width: 80, height: 80)

                if let pfp = cloudProfile?.avatarUrl ?? authService.currentUser?.pfpUrl, let url = URL(string: pfp) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(initials)
                            .font(.asterionSerif(32, weight: .light))
                            .foregroundStyle(Color.goldAccent)
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                } else {
                    Text(initials)
                        .font(.asterionSerif(32, weight: .light))
                        .foregroundStyle(Color.goldAccent)
                }

                Circle()
                    .fill(Color.asterionBackground)
                    .stroke(Color.asterionBorder, lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Text("📖").font(.system(size: 11))
                    }
                    .offset(x: 28, y: 28)
            }
            .padding(.bottom, 16)

            Text(cloudProfile?.username ?? authService.currentUser?.username ?? "Reader")
                .font(.asterionSerif(22))
                .foregroundStyle(Color.asterionText)

            if let email = cloudProfile?.email ?? authService.currentUser?.email {
                Text(email)
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionDim)
                    .padding(.top, 2)
            }

            Text(memberSinceLabel)
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionDim)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    private var initials: String {
        let name = cloudProfile?.username ?? authService.currentUser?.username
        guard let name, !name.isEmpty else { return "A" }
        return String(name.prefix(1)).uppercased()
    }

    private var memberSinceLabel: String {
        guard let createdAt = cloudProfile?.createdAt else { return "Member since —" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return "Member since \(formatter.string(from: createdAt))"
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(spacing: 10) {
            Button {
                authService.signOut()
                apiClient.setSessionToken(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12))
                    Text("Sign Out")
                        .font(.asterionMono(12))
                }
                .foregroundStyle(Color.goldAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .overlay(
                    Capsule()
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statCard(
                value: authService.isSignedIn ? "\(cloudProgressCount)" : "\(libraryNovels.count)",
                label: authService.isSignedIn ? "In Progress" : "Novels"
            )
            statCard(value: authService.isSignedIn ? "\(cloudChaptersRead)" : totalChapters.formatted(), label: authService.isSignedIn ? "Chapters Read" : "Chapters")
            statCard(value: authService.isSignedIn ? "\(libraryNovels.count)" : avgRating, label: authService.isSignedIn ? "In Library" : "Avg Rating")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    private func loadCloudProfileData() async {
        guard authService.isSignedIn else {
            cloudProfile = nil
            cloudBookmarkCount = 0
            cloudProgressCount = 0
            cloudChaptersRead = 0
            libraryNovels = []
            startedNovelIds = []
            completedNovelIds = []
            cloudSyncError = nil
            return
        }

        do {
            async let profileFetch = apiClient.fetchMyProfile()
            async let statsFetch = apiClient.fetchMyStats()
            async let prefsFetch = apiClient.fetchMyPreferences()
            async let libraryFetch = apiClient.fetchMyLibrary()
            async let allNovelsFetch = apiClient.fetchNovels(limit: 500, search: "")
            async let progressFetch = apiClient.fetchAllReadingProgress()
            async let historyFetch = fetchAllReadingHistory()

            cloudProfile = try await profileFetch
            let stats = try await statsFetch
            let prefs = try await prefsFetch
            let libraryItems = try await libraryFetch
            let allNovels = try await allNovelsFetch
            let progressList = try await progressFetch
            let history = try await historyFetch

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
            darkMode = prefs.darkMode
            notificationsOn = prefs.notificationsOn
            fontSizePref = FontSizePref(rawValue: prefs.fontSizePref) ?? .medium
            isApplyingServerPreferences = false
            cloudSyncError = nil
        } catch {
            cloudSyncError = "Signed in, but cloud sync failed. Check USER_API_BASE_URL / backend server."
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
                darkMode: darkMode,
                notificationsOn: notificationsOn,
                fontSizePref: fontSizePref.rawValue
            )
            cloudSyncError = nil
        } catch {
            cloudSyncError = "Couldn't save reading preferences to cloud."
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.asterionSerif(22, weight: .medium))
                .foregroundStyle(Color.asterionText)
            Text(label.uppercased())
                .font(.asterionMono(9))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.asterionCard)
                .stroke(Color.asterionBorder, lineWidth: 1)
        )
    }

    // MARK: - Reading Status

    private var readingStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("READING STATUS")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 0.353, green: 0.608, blue: 0.478))
                            .frame(width: 8, height: 8)
                        Text("\(ongoing) Ongoing")
                            .font(.asterionSerif(13))
                            .foregroundStyle(Color.asterionSynopsis)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(Color.goldAccent)
                            .frame(width: 8, height: 8)
                        Text("\(completed) Completed")
                            .font(.asterionSerif(13))
                            .foregroundStyle(Color.asterionSynopsis)
                    }
                }

                if !libraryNovels.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(red: 0.353, green: 0.608, blue: 0.478))
                                .frame(width: geo.size.width * CGFloat(ongoing) / CGFloat(libraryNovels.count))
                            Rectangle()
                                .fill(Color.goldAccent)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(libraryNovels.count))
                        }
                    }
                    .frame(height: 4)
                    .background(Color.asterionBorder)
                    .clipShape(Capsule())
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.asterionCard)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 32)
    }

    // MARK: - Reading Preferences

    private var readingPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("READING PREFERENCES")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                settingsRow(label: "Font Size", sublabel: fontSizePref.rawValue.capitalized) {
                    HStack(spacing: 6) {
                        ForEach(FontSizePref.allCases, id: \.self) { sz in
                            Button { fontSizePref = sz } label: {
                                Text("A")
                                    .font(.asterionSerif(sz == .small ? 12 : sz == .medium ? 15 : 18))
                                    .foregroundStyle(fontSizePref == sz ? Color.goldAccent : Color.asterionDim)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(fontSizePref == sz ? Color.goldAccent : Color.asterionBorder, lineWidth: 1)
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(fontSizePref == sz ? Color.goldAccent.opacity(0.09) : .clear)
                                    )
                            }
                        }
                    }
                }

                settingsRow(label: "Reading Goal", sublabel: "\(readingGoal) chapters / week") {
                    HStack(spacing: 8) {
                        Button { readingGoal = max(5, readingGoal - 5) } label: {
                            Text("−")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.asterionMuted)
                                .frame(width: 28, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.asterionBorder, lineWidth: 1))
                        }
                        Text("\(readingGoal)")
                            .font(.asterionMono(14))
                            .foregroundStyle(Color.asterionText)
                            .frame(minWidth: 24)
                        Button { readingGoal = min(100, readingGoal + 5) } label: {
                            Text("+")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.asterionMuted)
                                .frame(width: 28, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.asterionBorder, lineWidth: 1))
                        }
                    }
                }

                settingsRow(label: "Dark Mode", sublabel: "Optimized for night reading", showBorder: false) {
                    Toggle("", isOn: $darkMode)
                        .tint(Color.goldAccent)
                        .labelsHidden()
                }
            }
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.asterionCard)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATIONS")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                settingsRow(label: "New Chapters", sublabel: "Get notified when novels update") {
                    Toggle("", isOn: $notificationsOn)
                        .tint(Color.goldAccent)
                        .labelsHidden()
                }
                settingsRow(label: "Siri Shortcuts", sublabel: "Quick access to reading", showBorder: false) {
                    Text("›")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.asterionBorder)
                }
            }
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.asterionCard)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ABOUT")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                ForEach(Array(["Widget Setup", "Rate Asterion", "Privacy Policy", "Terms of Service"].enumerated()), id: \.offset) { index, item in
                    settingsRow(label: item, showBorder: index < 3) {
                        Text("›")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.asterionBorder)
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.asterionCard)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Footer

    private var footerBrand: some View {
        VStack(spacing: 4) {
            Text("Asterion")
                .font(.asterionSerif(16, weight: .light))
                .foregroundStyle(Color.asterionBorderHover)
                .tracking(2)
            Text("v1.0.0")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionBorder)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Settings Row Helper

    private func settingsRow<Trailing: View>(
        label: String,
        sublabel: String? = nil,
        showBorder: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.asterionSerif(15))
                    .foregroundStyle(Color.asterionReaderText)
                if let sublabel {
                    Text(sublabel)
                        .font(.asterionMono(11))
                        .foregroundStyle(Color.asterionDim)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            if showBorder {
                Rectangle().fill(Color.asterionCard).frame(height: 1)
            }
        }
    }
}
