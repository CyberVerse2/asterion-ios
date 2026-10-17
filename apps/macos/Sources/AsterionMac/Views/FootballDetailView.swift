import SwiftUI

struct FootballDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: FootballStore

    @State private var streams: [FootballStream] = []
    @State private var streamsMatchID: FootballMatch.ID?
    @State private var isLoadingStreams = false
    @State private var reminderMatchID: FootballMatch.ID?
    @State private var reminderMessage: String?
    @State private var reminderIsError = false

    private let stageWidth: CGFloat = 860

    /// The feed often labels fixtures only with the sport itself.
    private var isGenericCategory: Bool {
        guard let match = store.selectedMatch else { return true }
        return ["football", "soccer", ""].contains(
            match.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    var body: some View {
        Group {
            if let match = store.selectedMatch {
                detail(match)
            } else {
                AsterionEmptyState(
                    systemImage: "sportscourt",
                    title: "Choose a match",
                    message: "Select a fixture to see its teams and live status."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionMediaCanvas)
    }

    private func detail(_ match: FootballMatch) -> some View {
        ScrollView {
            VStack(spacing: AsterionLayout.sectionSpacing) {
                faceOff(match)

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Streams", count: sourceDescription(match))
                    streamList(match)
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Match details", count: nil)
                    VStack(spacing: 0) {
                        AsterionDetailFactRow(
                            label: "Kickoff",
                            value: match.kickoff.formatted(date: .complete, time: .shortened)
                        )
                        AsterionDetailRowDivider()
                        if !isGenericCategory {
                            AsterionDetailFactRow(label: "Competition", value: match.category.capitalized)
                            AsterionDetailRowDivider()
                        }
                        AsterionDetailFactRow(label: "Status", value: statusDescription(match))
                    }
                    .asterionPanel(cornerRadius: 14)
                }
            }
            .frame(maxWidth: stageWidth)
            .padding(.horizontal, AsterionLayout.pageInset)
            .frame(maxWidth: .infinity)
            .asterionDetailPageFrame()
            .background(alignment: .top) {
                AsterionDetailBackdrop(url: match.posterURL)
            }
        }
        .hidingScrollIndicators()
        .task(id: "\(match.id)#\(match.isLive)") {
            await loadStreams(for: match)
        }
        .task(id: "\(match.id)#\(match.kickoff.timeIntervalSince1970)") {
            reminderMessage = nil
            await KickoffReminderService.refresh(matchID: match.id, title: match.displayTitle, kickoff: match.kickoff)
            reminderMatchID = await KickoffReminderService.isScheduled(matchID: match.id) ? match.id : nil
        }
    }

    // MARK: Face-off

    private func faceOff(_ match: FootballMatch) -> some View {
        VStack(spacing: 26) {
            AsterionEyebrow(
                text: isGenericCategory ? (match.isLive ? "In play" : "Upcoming match") : match.category,
                color: .white.opacity(0.7)
            )

            HStack(alignment: .top, spacing: 20) {
                team(match.homeTeam, fallback: fallbackTeams(match).home)
                centerStatus(match)
                    .padding(.top, 22)
                team(match.awayTeam, fallback: fallbackTeams(match).away)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(match.displayTitle)
            .accessibilityAddTraits(.isHeader)

            watchAction(match)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private func team(_ team: FootballTeam?, fallback: String) -> some View {
        VStack(spacing: 16) {
            FootballBadgeView(team: team, size: 84)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.10), .white.opacity(0)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)
                }
            Text(team?.name ?? fallback)
                .font(.asterionTitle(22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func centerStatus(_ match: FootballMatch) -> some View {
        VStack(spacing: 8) {
            if match.isLive {
                AsterionLiveBadge()
                    .scaleEffect(1.25)
                    .padding(.bottom, 4)
                Text("vs")
                    .font(.asterionMono(14, weight: .semibold))
                    .foregroundStyle(Color.asterionMuted)
            } else {
                Text(match.kickoff.formatted(date: .omitted, time: .shortened))
                    .font(.asterionMono(28, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(match.kickoff.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                Text(match.kickoff.formatted(.relative(presentation: .named)))
                    .font(.asterionMono(11, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
            }
        }
        .frame(width: 150)
    }

    private func watchAction(_ match: FootballMatch) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if !match.isLive, KickoffReminder.fireDate(kickoff: match.kickoff) != nil {
                    reminderButton(match)
                } else {
                    Button {
                        openWindow(value: FootballPlayerRoute(match: match))
                    } label: {
                        Label(match.isLive ? "Watch live" : "Match not live", systemImage: "play.fill")
                    }
                    .buttonStyle(.asterionPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!match.isLive || match.sources.isEmpty)
                    .help(match.isLive ? "Open in Asterion Live" : "This match is not live yet")
                }

                mediaBookmarkButton(match)
            }

            if let error = model.mediaBookmarkError {
                AsterionDetailNotice(message: error)
                    .multilineTextAlignment(.center)
            } else if let reminderMessage {
                AsterionDetailNotice(
                    message: reminderMessage,
                    systemImage: reminderIsError ? "exclamationmark.triangle.fill" : "bell",
                    color: reminderIsError ? .asterionWarning : .asterionFaint
                )
                .multilineTextAlignment(.center)
            }
        }
    }

    private func reminderButton(_ match: FootballMatch) -> some View {
        let isSet = reminderMatchID == match.id
        return Button {
            Task { await toggleReminder(match) }
        } label: {
            Label(isSet ? "Reminder on" : "Remind me", systemImage: isSet ? "bell.badge.fill" : "bell.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.asterionPrimary)
        .keyboardShortcut(.return, modifiers: .command)
        .help(isSet ? "Cancel the kickoff reminder" : "Get a notification 15 minutes before kickoff")
    }

    private func toggleReminder(_ match: FootballMatch) async {
        reminderIsError = false
        if reminderMatchID == match.id {
            KickoffReminderService.cancel(matchID: match.id)
            reminderMatchID = nil
            reminderMessage = "Reminder cancelled."
            return
        }
        do {
            switch try await KickoffReminderService.schedule(
                matchID: match.id, title: match.displayTitle, kickoff: match.kickoff) {
            case .scheduled:
                reminderMatchID = match.id
                reminderMessage = "You’ll get a notification 15 minutes before kickoff."
            case .denied:
                reminderIsError = true
                reminderMessage = "Notifications are off for Asterion. Turn them on in System Settings › Notifications."
            case .tooLate:
                reminderMessage = "This match is about to start."
            case .unavailable:
                reminderIsError = true
                reminderMessage = "Reminders need the installed Asterion app."
            }
        } catch {
            reminderIsError = true
            reminderMessage = "Couldn’t set the reminder. Try again in a moment."
        }
    }

    private func mediaBookmarkButton(_ match: FootballMatch) -> some View {
        let item = MediaItemDescriptor(
            mediaType: .football,
            contentID: match.id,
            title: match.displayTitle,
            subtitle: "\(match.category.capitalized) · \(match.kickoff.formatted(date: .abbreviated, time: .shortened))",
            imageURL: match.posterURL
        )
        let isSaved = model.isMediaBookmarked(item.key)
        let isUpdating = model.isUpdatingMediaBookmark(item.key)

        return Button {
            guard model.isSignedIn else {
                openWindow(id: "authentication")
                return
            }
            Task { await model.toggleMediaBookmark(item) }
        } label: {
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 58)
            } else {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(minWidth: 58)
            }
        }
        .buttonStyle(.asterionSecondary)
        .disabled(isUpdating)
        .help(isSaved ? "Remove saved match" : "Save this match to your account")
    }

    // MARK: Streams

    private func sectionHeader(_ title: String, count: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.asterionTitle(18, weight: .bold))
                .foregroundStyle(Color.asterionText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
            }
        }
    }

    @ViewBuilder
    private func streamList(_ match: FootballMatch) -> some View {
        let loadedStreams = streamsMatchID == match.id ? streams : []

        if match.sources.isEmpty {
            AsterionEmptyState(
                systemImage: "antenna.radiowaves.left.and.right",
                title: "No streams listed",
                message: "Providers usually appear shortly before kickoff. Check back closer to the match."
            )
            .frame(minHeight: 200)
            .asterionPanel(cornerRadius: 14)
        } else if !loadedStreams.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(loadedStreams.enumerated()), id: \.element.optionID) { index, stream in
                    if index > 0 {
                        AsterionDetailRowDivider()
                    }
                    streamRow(stream)
                }
            }
            .asterionPanel(cornerRadius: 14)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(match.sources.enumerated()), id: \.offset) { index, source in
                    if index > 0 {
                        AsterionDetailRowDivider()
                    }
                    sourceRow(source, index: index, match: match)
                }
            }
            .asterionPanel(cornerRadius: 14)
        }
    }

    private func streamRow(_ stream: FootballStream) -> some View {
        HStack(spacing: 16) {
            Text(String(format: "%02d", stream.streamNumber))
                .font(.asterionMono(12, weight: .medium))
                .foregroundStyle(Color.asterionFaint)
                .frame(minWidth: 24, alignment: .leading)

            Text(stream.source.capitalized)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                if stream.hd {
                    Text("HD")
                        .foregroundStyle(Color.asterionText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28))
                        }
                }
                if !stream.language.isEmpty {
                    Text(stream.language.uppercased())
                }
                if let viewers = stream.viewers {
                    Text("\(viewers.formatted(.number.notation(.compactName))) watching")
                }
            }
            .font(.asterionMono(11, weight: .medium))
            .foregroundStyle(Color.asterionMuted)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .accessibilityElement(children: .combine)
    }

    private func sourceRow(_ source: FootballStreamSource, index: Int, match: FootballMatch) -> some View {
        HStack(spacing: 16) {
            Text(String(format: "%02d", index + 1))
                .font(.asterionMono(12, weight: .medium))
                .foregroundStyle(Color.asterionFaint)
                .frame(minWidth: 24, alignment: .leading)

            Text(source.source.capitalized)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .lineLimit(1)

            Spacer(minLength: 12)

            if match.isLive && isLoadingStreams {
                AsterionSkeleton(cornerRadius: 3)
                    .frame(width: 96, height: 9)
            } else {
                Text(match.isLive ? "Ready" : "At kickoff")
                    .font(.asterionMono(11, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .accessibilityElement(children: .combine)
    }

    /// Reads stream quality, language, and audience for a live match so the
    /// list can describe each source. Failures fall back to the provider list.
    private func loadStreams(for match: FootballMatch) async {
        guard match.isLive, !match.sources.isEmpty else {
            streams = []
            streamsMatchID = nil
            return
        }
        guard streamsMatchID != match.id else { return }
        isLoadingStreams = true
        defer { isLoadingStreams = false }
        do {
            let fetched = try await FootballAPI.shared.fetchStreams(for: match)
            guard !Task.isCancelled else { return }
            streams = fetched.sorted { lhs, rhs in
                if lhs.hd != rhs.hd { return lhs.hd }
                return (lhs.viewers ?? 0) > (rhs.viewers ?? 0)
            }
            streamsMatchID = match.id
        } catch {
            guard !Task.isCancelled else { return }
            streams = []
            streamsMatchID = nil
        }
    }

    // MARK: Text

    private func statusDescription(_ match: FootballMatch) -> String {
        if match.isLive { return "Live now" }
        return "Kicks off \(match.kickoff.formatted(.relative(presentation: .named)))"
    }

    private func sourceDescription(_ match: FootballMatch) -> String {
        let count = match.sources.count
        return count == 1 ? "1 stream provider" : "\(count) stream providers"
    }

    private func fallbackTeams(_ match: FootballMatch) -> (home: String, away: String) {
        let parts = match.title.components(separatedBy: " vs ")
        guard parts.count > 1 else { return (match.title, "Opponent") }
        return (parts[0], parts[1])
    }
}
