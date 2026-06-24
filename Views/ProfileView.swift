import ClerkKit
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
    private var contentMaxWidth: CGFloat { isDesktop ? 1040 : .infinity }
    private var pageHorizontalPadding: CGFloat { isDesktop ? 46 : 24 }

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
            .font(.asterionSerif(isDesktop ? 58 : 42, weight: .semibold))
            .foregroundStyle(Color.asterionText)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 26 : 14)
            .padding(.bottom, isDesktop ? 16 : 8)
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: isDesktop ? 90 : 60)

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
                    .frame(width: isDesktop ? 160 : 120, height: isDesktop ? 160 : 120)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: isDesktop ? 68 : 48, weight: .light))
                    .foregroundStyle(Color.asterionDim)
            }

            Text("Welcome to Asterion")
                .font(.asterionSerif(isDesktop ? 34 : 22, weight: .light))
                .foregroundStyle(Color.asterionText)
                .padding(.top, 16)

            Text("SIGN IN TO TRACK YOUR READING")
                .font(.asterionMono(isDesktop ? 12 : 10))
                .foregroundStyle(Color.asterionDim)
                .tracking(2)
                .padding(.top, 6)

            VStack(spacing: 12) {
                Button {
                    authSheetMode = .signIn
                    showAuthSheet = true
                } label: {
                    Text("Sign In")
                        .font(.asterionSerif(isDesktop ? 21 : 16, weight: .medium))
                        .foregroundStyle(Color.asterionBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isDesktop ? 18 : 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.goldAccent)
                        )
                }

                Button {
                    authSheetMode = .createAccount
                    showAuthSheet = true
                } label: {
                    Text("Create Account")
                        .font(.asterionSerif(isDesktop ? 21 : 16, weight: .medium))
                        .foregroundStyle(Color.goldAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isDesktop ? 18 : 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.clear)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: isDesktop ? 520 : .infinity)
            .padding(.horizontal, isDesktop ? 0 : 32)
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
        .padding(.horizontal, pageHorizontalPadding)
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
                    HStack(spacing: 8) {
                        Circle().fill(Color.asterionBorderHover)
                            .frame(width: 8, height: 8)
                        Text("\(unreadInLibrary) Unread")
                            .font(.asterionSerif(13))
                            .foregroundStyle(Color.asterionSynopsis)
                    }
                }

                if !libraryNovels.isEmpty {
                    let denominator = max(ongoing + completed + unreadInLibrary, 1)
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(red: 0.353, green: 0.608, blue: 0.478))
                                .frame(width: geo.size.width * CGFloat(ongoing) / CGFloat(denominator))
                            Rectangle()
                                .fill(Color.goldAccent)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(denominator))
                            Rectangle()
                                .fill(Color.asterionBorderHover)
                                .frame(width: geo.size.width * CGFloat(unreadInLibrary) / CGFloat(denominator))
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
