import SwiftUI

struct FootballDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: FootballStore

    var body: some View {
        Group {
            if let match = store.selectedMatch {
                detail(match)
            } else {
                ContentUnavailableView(
                    "Choose a match",
                    systemImage: "sportscourt",
                    description: Text("Select a fixture to see its teams and live status.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func detail(_ match: FootballMatch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                status(match)
                matchup(match)
                watchAction(match)

                Divider()

                VStack(alignment: .leading, spacing: 13) {
                    Text("Match details")
                        .font(.asterionDisplay(20, weight: .semibold))
                    metadataLine(icon: "calendar", value: match.kickoff.formatted(date: .complete, time: .shortened))
                    metadataLine(icon: "sportscourt", value: match.category.capitalized)
                    metadataLine(icon: "antenna.radiowaves.left.and.right", value: sourceDescription(match))
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 46)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .navigationTitle(match.displayTitle)
    }

    private func status(_ match: FootballMatch) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(match.isLive ? Color.asterionAccent : Color.asterionMuted)
                .frame(width: 7, height: 7)
            Text(match.isLive ? "LIVE NOW" : match.kickoff.formatted(.relative(presentation: .named)))
                .font(.asterionMono(10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(match.isLive ? Color.asterionAccent : Color.asterionMuted)
        }
    }

    private func matchup(_ match: FootballMatch) -> some View {
        HStack(alignment: .top, spacing: 18) {
            team(match.homeTeam, fallback: fallbackTeams(match).home)
            Text("VS")
                .font(.asterionMono(12, weight: .semibold))
                .foregroundStyle(Color.asterionMuted)
                .padding(.top, 29)
            team(match.awayTeam, fallback: fallbackTeams(match).away)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func team(_ team: FootballTeam?, fallback: String) -> some View {
        VStack(spacing: 12) {
            FootballBadgeView(team: team, size: 78)
            Text(team?.name ?? fallback)
                .font(.asterionDisplay(18, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func watchAction(_ match: FootballMatch) -> some View {
        Button {
            openWindow(value: FootballPlayerRoute(match: match))
        } label: {
            Label(match.isLive ? "Watch live" : "Match not live", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(.asterionAccent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!match.isLive || match.sources.isEmpty)
        .help(match.isLive ? "Open in Asterion Live" : "This match is not live yet")
    }

    private func metadataLine(icon: String, value: String) -> some View {
        Label {
            Text(value).lineLimit(2)
        } icon: {
            Image(systemName: icon).frame(width: 17)
        }
        .font(.callout)
        .foregroundStyle(Color.asterionMuted)
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
