import SwiftUI

struct FootballCatalogView: View {
    @ObservedObject var store: FootballStore
    let section: FootballSection
    let query: String

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groupedMatches: [(date: Date, matches: [FootballMatch])] {
        let groups = Dictionary(grouping: store.matches) {
            Calendar.current.startOfDay(for: $0.kickoff)
        }
        return groups.keys.sorted().map { date in
            (date, groups[date, default: []])
        }
    }

    var body: some View {
        Group {
            if store.isLoading, store.matches.isEmpty {
                ProgressView("Loading fixtures…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.error, store.matches.isEmpty {
                ContentUnavailableView {
                    Label("Football unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.refresh(section: section) } }
                }
            } else if store.matches.isEmpty {
                ContentUnavailableView(
                    normalizedQuery.isEmpty ? emptyTitle : "No matches found",
                    systemImage: section == .live ? "sportscourt" : "calendar.badge.exclamationmark",
                    description: Text(normalizedQuery.isEmpty ? emptyDescription : "Try a team or competition name.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26, pinnedViews: [.sectionHeaders]) {
                        catalogHeader
                        if let error = store.error {
                            refreshError(error)
                        }
                        ForEach(groupedMatches, id: \.date) { group in
                            Section {
                                VStack(spacing: 10) {
                                    ForEach(group.matches) { match in
                                        FootballMatchRow(
                                            match: match,
                                            isSelected: store.selectedMatchID == match.id
                                        ) {
                                            store.select(match)
                                        }
                                    }
                                }
                            } header: {
                                dateHeader(group.date)
                            }
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(.background)
        .navigationTitle(section.title)
        .task(id: section) {
            await store.load(section: section)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                await store.refresh(section: section)
            }
        }
        .onAppear { store.updateSearch(normalizedQuery) }
        .onChange(of: normalizedQuery) { _, value in store.updateSearch(value) }
    }

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.catalogTitle)
                .font(.asterionDisplay(24, weight: .semibold))
            Text(section.catalogDescription)
                .font(.callout)
                .foregroundStyle(Color.asterionMuted)
        }
        .padding(.bottom, 2)
    }

    private func refreshError(_ error: String) -> some View {
        HStack(spacing: 12) {
            Label(error, systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
            Spacer()
            Button("Try Again") { Task { await store.refresh(section: section) } }
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.asterionCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dateHeader(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .font(.asterionMono(11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Color.asterionMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .background(.background)
    }

    private var emptyTitle: String {
        section == .live ? "No live matches" : "No matches available"
    }

    private var emptyDescription: String {
        section == .live
            ? "Live fixtures will appear here as soon as play begins."
            : "The football service has no fixtures for this section right now."
    }
}

private struct FootballMatchRow: View {
    let match: FootballMatch
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(spacing: 5) {
                    Text(match.kickoff.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    if match.isLive {
                        Text("LIVE")
                            .font(.asterionMono(9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.asterionAccent)
                    }
                }
                .foregroundStyle(Color.asterionMuted)
                .frame(width: 58)

                VStack(alignment: .leading, spacing: 10) {
                    teamLine(match.homeTeam, fallback: homeFallback)
                    teamLine(match.awayTeam, fallback: awayFallback)
                }

                Spacer(minLength: 8)

                if match.popular {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.asterionAccent)
                        .help("Popular match")
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.asterionMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                isSelected ? Color.asterionAccent.opacity(0.13) : Color.asterionCard,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.asterionAccent : .white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .accessibilityLabel(match.displayTitle)
    }

    private func teamLine(_ team: FootballTeam?, fallback: String) -> some View {
        HStack(spacing: 10) {
            FootballBadgeView(team: team, size: 26)
            Text(team?.name ?? fallback)
                .font(.asterionDisplay(15, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(1)
        }
    }

    private var homeFallback: String {
        match.title.components(separatedBy: " vs ").first ?? match.title
    }

    private var awayFallback: String {
        let parts = match.title.components(separatedBy: " vs ")
        return parts.count > 1 ? parts[1] : "Opponent"
    }
}

struct FootballBadgeView: View {
    let team: FootballTeam?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: team?.badgeURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "shield")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
