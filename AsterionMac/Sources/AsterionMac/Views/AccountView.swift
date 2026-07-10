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
        .background(Color.asterionBackground)
        .navigationTitle("Profile")
    }

    private func signedInProfile(_ user: AppModel.SignedInUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                profileHeader(user)
                readingStats
                currentlyReading
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
                Text("READER PROFILE")
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

            Label("Synced", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.asterionAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.asterionAccentSoft, in: Capsule())
        }
        .padding(24)
        .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.asterionBorder)
        }
    }

    private var readingStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Your reading life", subtitle: "A quiet snapshot of your Asterion library.")

            HStack(spacing: 12) {
                ProfileStatCard(
                    value: String(model.libraryNovelIDs.count),
                    label: model.libraryNovelIDs.count == 1 ? "Saved story" : "Saved stories",
                    icon: "bookmark.fill"
                )
                ProfileStatCard(
                    value: String(model.continueReadingEntries.count),
                    label: "In progress",
                    icon: "book.pages.fill"
                )
                ProfileStatCard(
                    value: averageProgressLabel,
                    label: "Average progress",
                    icon: "chart.line.uptrend.xyaxis"
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
                .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.asterionBorder)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.continueReadingEntries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(Color.asterionBorder)
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
                .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.asterionBorder)
                }
            }
        }
    }

    private var signedOutProfile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR READING LIFE")
                        .font(.asterionMono(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.asterionAccent)
                    Text("Make Asterion yours.")
                        .font(.asterionDisplay(36, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text("A profile keeps every saved story and reading position together, wherever you return to the library.")
                        .font(.asterionDisplay(17))
                        .foregroundStyle(Color.asterionMuted)
                        .lineSpacing(4)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                VStack(spacing: 0) {
                    ProfileBenefit(icon: "bookmark", title: "Keep a personal library", detail: "Save the stories you want to return to.")
                    Divider().overlay(Color.asterionBorder)
                    ProfileBenefit(icon: "book.pages", title: "Never lose your place", detail: "Reading progress follows your account.")
                    Divider().overlay(Color.asterionBorder)
                    ProfileBenefit(icon: "macbook.and.iphone", title: "Read across devices", detail: "Your library stays in sync automatically.")
                }
                .padding(.horizontal, 22)
                .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.asterionBorder)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(34)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private var averageProgressLabel: String {
        let values = model.continueReadingEntries.map(\.progress.percentage)
        guard !values.isEmpty else { return "—" }
        return "\(Int(values.reduce(0, +) / Double(values.count)))%"
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
        .background(.background)
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
                Label("Sync is on", systemImage: "checkmark.icloud.fill")
                    .font(.asterionDisplay(17, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                AccountStatusRow(label: "Library", value: "\(model.libraryNovelIDs.count) saved")
                AccountStatusRow(label: "Reading progress", value: "\(model.continueReadingEntries.count) active")
                Text("Changes to your library and chapter position are saved automatically.")
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
                Text("Create an account or sign in to sync your library and reading progress.")
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
                Text("YOUR READING LIFE")
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
                .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.asterionBorder)
                }
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

            Text("Your saved stories and reading position stay synced across Asterion.")
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 438, height: 548)
        .background(Color.asterionBackground)
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
        .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.asterionBorder)
        }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.asterionAccent)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Color.asterionAccentSoft, in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.asterionAccent.opacity(0.35))
                    }
            }
            .buttonStyle(AsterionPressButtonStyle())
        }
        .padding(.vertical, 15)
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
            .background(Color.asterionBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.asterionBorder)
            }
    }
}
