import SwiftUI

struct ContinueWatchingShelf: View {
    let entries: [MediaPlaybackProgress]
    let resume: (MediaPlaybackProgress) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue Watching")
                    .font(.asterionDisplay(22, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text("Pick up where you left off.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 22) {
                    ForEach(entries) { entry in
                        ContinueWatchingTile(progress: entry) {
                            resume(entry)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ContinueWatchingTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: MediaPlaybackProgress
    let action: () -> Void

    private var fraction: Double {
        min(1, max(0, progress.percentage / 100))
    }

    private var percentage: Int {
        Int(progress.percentage.rounded())
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                MediaCoverView(url: progress.imageURL, width: 112, height: 160)
                    .padding(4)

                Text(progress.title)
                    .font(.asterionDisplay(14, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .frame(maxWidth: 120, alignment: .leading)

                Text(progress.unitTitle ?? progress.mediaType.title)
                    .font(.caption2)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                HStack(spacing: 6) {
                    ProgressView(value: fraction)
                        .tint(Color.asterionAccent)
                    Text("\(percentage)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.asterionMuted)
                }
                .frame(maxWidth: 120)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: percentage)
        .help("Continue \(progress.title) from \(percentage)%")
        .accessibilityLabel("Continue \(progress.title), \(progress.unitTitle ?? progress.mediaType.title)")
        .accessibilityValue("\(percentage) percent watched")
    }
}
