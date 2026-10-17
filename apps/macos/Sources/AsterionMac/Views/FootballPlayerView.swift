import SwiftUI

struct FootballPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let route: FootballPlayerRoute

    @StateObject private var store = FootballPlayerStore()
    @State private var showsSources = false
    @State private var keepsWindowOnTop = false

    var body: some View {
        HStack(spacing: 0) {
            playerPane
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

            if showsSources {
                Rectangle()
                    .fill(Color.asterionHairline)
                    .frame(width: 1)
                sourceSidebar
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .background(.black)
        .navigationTitle(route.match.displayTitle)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .mediaWindowPinning(isPinned: keepsWindowOnTop)
        .animation(reduceMotion ? nil : AsterionMotion.sidebar, value: showsSources)
        .task(id: route) {
            showsSources = false
            await store.load(route: route)
        }
    }

    private var playerPane: some View {
        VStack(spacing: 0) {
            playerToolbar
            playerStage
        }
    }

    private var playerToolbar: some View {
        HStack(spacing: 8) {
            Group {
                if route.match.isLive {
                    AsterionLiveBadge()
                } else {
                    Text(route.match.kickoff.formatted(date: .omitted, time: .shortened))
                        .font(.asterionMono(11, weight: .semibold))
                        .foregroundStyle(Color.asterionMuted)
                        .accessibilityLabel(
                            "Kickoff \(route.match.kickoff.formatted(date: .omitted, time: .shortened))"
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))

            PlayerTitleLabel(title: route.match.displayTitle)
                .padding(.leading, 4)

            Spacer(minLength: 24)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .accessibilityHidden(true)

            if let selected = store.selectedStream {
                Text(streamSummary(selected))
                    .font(.asterionMono(11, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .accessibilityLabel("Playing \(selected.displayName)")
            }

            PlayerPinButton(isPinned: $keepsWindowOnTop)

            Button {
                showsSources.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(PlayerChromeButtonStyle(isLit: showsSources))
            .disabled(store.streams.count < 2)
            .help(showsSources ? "Hide sources" : "Show sources")
            .accessibilityLabel(showsSources ? "Hide sources" : "Show sources")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var playerStage: some View {
        Group {
            if store.isLoading {
                PlayerLoadingState(
                    message: "Preparing live video…",
                    artworkURL: route.match.posterURL
                )
            } else if let error = store.error {
                PlayerErrorState(
                    title: "The live video didn’t load",
                    message: error,
                    retry: { Task { await store.retry() } }
                )
            } else if let stream = store.selectedStream {
                MediaWebPlayer(url: stream.embedURL)
                    .id(stream.optionID)
            } else {
                AsterionEmptyState(
                    systemImage: "play.slash",
                    title: "No live source",
                    message: "This match has no playable source right now. Check back closer to kickoff."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Streams")
                        .font(.asterionTitle(16, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text(verbatim: String(store.streams.count))
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                        .accessibilityLabel("\(store.streams.count) streams")
                }
                Text("Choose another live source")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.asterionMuted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.streams, id: \.optionID) { stream in
                        let isSelected = store.selectedStreamID == stream.optionID
                        Button {
                            store.choose(stream)
                        } label: {
                            FootballStreamRow(stream: stream, isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(stream.displayName)")
                        .accessibilityValue(sourceMetadata(stream))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.asterionSurface)
    }

    private func streamSummary(_ stream: FootballStream) -> String {
        var parts = [stream.source.capitalized]
        if stream.hd { parts.append("HD") }
        if !stream.language.isEmpty { parts.append(stream.language.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func sourceMetadata(_ stream: FootballStream) -> String {
        var parts: [String] = []
        if !stream.language.isEmpty { parts.append(stream.language.uppercased()) }
        if stream.hd { parts.append("HD") }
        if let viewers = stream.viewers { parts.append("\(viewers.formatted()) watching") }
        return parts.joined(separator: " · ")
    }
}

/// A stream in the live source panel: source name over mono HD, language,
/// and viewer metadata. The playing stream is lit white.
private struct FootballStreamRow: View {
    let stream: FootballStream
    let isSelected: Bool

    @State private var isHovering = false

    private var ink: Color { isSelected ? .asterionMediaCanvas : .asterionText }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(stream.source.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    if stream.hd {
                        Text("HD")
                            .font(.asterionMono(9.5, weight: .bold))
                            .foregroundStyle(ink.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(ink.opacity(0.35))
                            }
                    }
                    if !stream.language.isEmpty {
                        Text(stream.language.uppercased())
                            .font(.asterionMono(10.5, weight: .medium))
                            .foregroundStyle(ink.opacity(0.6))
                    }
                    if let viewers = stream.viewers {
                        Text("\(viewers.formatted()) watching")
                            .font(.asterionMono(10.5, weight: .medium))
                            .foregroundStyle(ink.opacity(0.6))
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if isSelected {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.asterionMediaCanvas)
                    .accessibilityHidden(true)
            } else {
                Text("#\(stream.streamNumber)")
                    .font(.asterionMono(10.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.asterionText : Color.white.opacity(isHovering ? 0.05 : 0))
        }
        .shadow(color: .white.opacity(isSelected ? 0.12 : 0), radius: 10)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
