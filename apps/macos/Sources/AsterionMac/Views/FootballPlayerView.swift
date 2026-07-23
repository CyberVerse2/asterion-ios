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
                Divider().overlay(.white.opacity(0.08))
                sourceSidebar
                    .frame(width: 260)
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
            Divider().overlay(.white.opacity(0.08))
            playerStage

            Label(
                "The live player is supplied by a third party and may include external content.",
                systemImage: "globe"
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.42))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.black)
        }
    }

    private var playerToolbar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.asterionAccent)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.system(size: 11, weight: .bold).monospaced())
                .tracking(1)
                .foregroundStyle(Color.asterionAccent)

            Text(route.match.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 24)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .accessibilityHidden(true)

            MediaWindowPinButton(isPinned: $keepsWindowOnTop)

            if let selected = store.selectedStream {
                Text(selected.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Button {
                showsSources.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .disabled(store.streams.count < 2)
            .help(showsSources ? "Hide Sources" : "Show Sources")
            .accessibilityLabel(showsSources ? "Hide Sources" : "Show Sources")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.black.opacity(0.96))
    }

    @ViewBuilder
    private var playerStage: some View {
        Group {
            if store.isLoading {
                ProgressView("Preparing live video…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let error = store.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.title)
                    Text(error).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await store.retry() } }
                }
                .foregroundStyle(.white)
                .padding()
            } else if let stream = store.selectedStream {
                MediaWebPlayer(url: stream.embedURL)
                    .id(stream.optionID)
            } else {
                ContentUnavailableView(
                    "No live source",
                    systemImage: "play.slash",
                    description: Text("This match has no playable source right now.")
                )
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STREAMS")
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.42))
                Text("Choose another live source")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.46))
            }
            .padding(15)

            Divider().overlay(.white.opacity(0.08))

            List(store.streams, id: \.optionID) { stream in
                Button {
                    store.choose(stream)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stream.source.capitalized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))
                            Text(sourceMetadata(stream))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        if store.selectedStreamID == stream.optionID {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(Color.asterionAccent)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    store.selectedStreamID == stream.optionID
                        ? Color.asterionAccent.opacity(0.16)
                        : Color.clear
                )
                .accessibilityLabel("Play \(stream.displayName)")
                .accessibilityValue(sourceMetadata(stream))
                .accessibilityAddTraits(store.selectedStreamID == stream.optionID ? .isSelected : [])
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Color.black.opacity(0.94))
    }

    private func sourceMetadata(_ stream: FootballStream) -> String {
        var parts: [String] = []
        if !stream.language.isEmpty { parts.append(stream.language.uppercased()) }
        if stream.hd { parts.append("HD") }
        if let viewers = stream.viewers { parts.append("\(viewers.formatted()) watching") }
        return parts.joined(separator: " · ")
    }
}
