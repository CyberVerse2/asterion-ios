import ClerkKitUI
import Inject
import SwiftUI

struct ProfileView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []
    @State private var readingGoal: Int = 30
    @State private var darkMode = true
    @State private var notificationsOn = true
    @State private var fontSizePref: FontSizePref = .medium
    @State private var showAuthSheet = false

    enum FontSizePref: String, CaseIterable { case small, medium, large }

    private var ongoing: Int { novels.filter { $0.status == "Ongoing" }.count }
    private var completed: Int { novels.filter { $0.status == "Completed" }.count }
    private var totalChapters: Int {
        novels.reduce(0) { sum, n in
            sum + (Int(n.totalChapters?.filter(\.isNumber) ?? "") ?? 0)
        }
    }
    private var avgRating: String {
        guard !novels.isEmpty else { return "—" }
        let avg = novels.compactMap(\.rating).reduce(0, +) / Double(novels.count)
        return String(format: "%.1f", avg)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if authService.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }
            }
            .background(Color.asterionBackground.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                do { novels = try await apiClient.fetchNovels(limit: 100) } catch {}
            }
        }
        .sheet(isPresented: $showAuthSheet, onDismiss: {
            Task {
                await authService.syncClerkSession()
                apiClient.setSessionToken(authService.sessionToken)
            }
        }) {
            AuthView()
        }
        .enableInjection()
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

                if let pfp = authService.currentUser?.pfpUrl, let url = URL(string: pfp) {
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

            Text(authService.currentUser?.username ?? "Reader")
                .font(.asterionSerif(22))
                .foregroundStyle(Color.asterionText)

            if let email = authService.currentUser?.email {
                Text(email)
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionDim)
                    .padding(.top, 2)
            }

            Text("Member since 2024")
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionDim)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 36)
    }

    private var initials: String {
        guard let name = authService.currentUser?.username, !name.isEmpty else { return "A" }
        return String(name.prefix(1)).uppercased()
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
        .padding(.bottom, 28)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statCard(value: "\(novels.count)", label: "Novels")
            statCard(value: totalChapters.formatted(), label: "Chapters")
            statCard(value: avgRating, label: "Avg Rating")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
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

                if !novels.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(red: 0.353, green: 0.608, blue: 0.478))
                                .frame(width: geo.size.width * CGFloat(ongoing) / CGFloat(novels.count))
                            Rectangle()
                                .fill(Color.goldAccent)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(novels.count))
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
