import SwiftUI

struct FootballCatalogView: View {
    @Environment(\.asterionTopInset) private var topInset
    @ObservedObject var store: FootballStore
    let section: FootballSection
    let query: String
    let selectMatch: (FootballMatch) -> Void

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        AsterionSkeleton(cornerRadius: 4).frame(width: 220, height: 18)
                        Color.clear
                            .frame(height: AsterionCardMetrics.matchHeight)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .topLeading) {
                                HStack(spacing: 16) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        AsterionSkeleton(cornerRadius: 14)
                                            .frame(width: AsterionCardMetrics.matchWidth, height: AsterionCardMetrics.matchHeight)
                                    }
                                }
                                .fixedSize()
                            }
                            .clipped()
                    }
                    .padding(.horizontal, AsterionLayout.pageInset)
                    .padding(.top, AsterionLayout.catalogContentTop(topInset))
                }
                .scrollDisabled(true)
            } else if let error = store.error, store.matches.isEmpty {
                AsterionEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Fixtures didn’t load",
                    message: error
                ) {
                    Button("Try again") { Task { await store.refresh(section: section) } }
                        .buttonStyle(.asterionSecondary)
                }
            } else if store.matches.isEmpty {
                AsterionEmptyState(
                    systemImage: section == .live ? "sportscourt" : "calendar",
                    title: normalizedQuery.isEmpty ? emptyTitle : "No matches for “\(normalizedQuery)”",
                    message: normalizedQuery.isEmpty ? emptyDescription : "Try a team or a competition name."
                ) {
                    if section == .live, normalizedQuery.isEmpty {
                        Button {
                            Task { await store.refresh(section: section) }
                        } label: {
                            Label("Check again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.asterionSecondary)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 36) {
                        catalogHeader
                        if let error = store.error {
                            refreshError(error)
                        }
                        ForEach(groupedMatches, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                dateHeader(group.date, count: group.matches.count)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.matchWidth, maximum: AsterionCardMetrics.matchWidth), spacing: 16)],
                                    alignment: .leading,
                                    spacing: 16
                                ) {
                                    ForEach(group.matches) { match in
                                        HomeMatchCard(
                                            match: match,
                                            isSelected: store.selectedMatchID == match.id
                                        ) {
                                            selectMatch(match)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AsterionLayout.pageInset)
                    .padding(.top, AsterionLayout.catalogContentTop(topInset))
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
        .task(id: section) {
            await store.refresh(section: section)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    return
                }
                await store.refresh(section: section)
            }
        }
        .onAppear { store.updateSearch(normalizedQuery) }
        .onChange(of: normalizedQuery) { _, value in store.updateSearch(value) }
    }

    private var refreshInterval: Duration {
        switch section {
        case .live: .seconds(15)
        case .popular: .seconds(30)
        case .schedule: .seconds(60)
        }
    }

    private var catalogHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(section.catalogTitle)
                .font(.asterionTitle(18, weight: .bold))
                .foregroundStyle(Color.asterionText)
            Text(section.catalogDescription)
                .font(.system(size: 13))
                .foregroundStyle(Color.asterionMuted)
            Spacer()
            Text("Updates every \(Int(refreshInterval.components.seconds))s")
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionFaint)
        }
    }

    private func refreshError(_ error: String) -> some View {
        HStack(spacing: 12) {
            Label(error, systemImage: "wifi.exclamationmark")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.asterionWarning)
            Spacer()
            Button("Try again") { Task { await store.refresh(section: section) } }
                .buttonStyle(.asterionSecondary)
                .controlSize(.small)
        }
        .padding(14)
        .asterionPanel(cornerRadius: 12)
    }

    private func dateHeader(_ date: Date, count: Int) -> some View {
        HStack(spacing: 10) {
            AsterionEyebrow(text: dayLabel(for: date), color: Color.asterionText.opacity(0.8))
            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)
            Text("\(count)")
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionFaint)
        }
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var emptyTitle: String {
        section == .live ? "No live matches" : "No matches available"
    }

    private var emptyDescription: String {
        switch section {
        case .live: "Matches appear here the moment they kick off. Schedule shows what’s coming up."
        case .schedule: "No upcoming fixtures are listed yet. Live shows matches already in play."
        case .popular: "No featured matches right now. Schedule lists every upcoming fixture."
        }
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
                Text(initials)
                    .font(.system(size: size * 0.3, weight: .bold).width(.expanded))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: size * 0.82, height: size * 0.82)
                    .background(Circle().fill(.white.opacity(0.1)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.18)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = (team?.name ?? "").split(separator: " ").filter { !$0.isEmpty }
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array((words.first ?? "").prefix(3))
        return String(letters).uppercased()
    }
}
