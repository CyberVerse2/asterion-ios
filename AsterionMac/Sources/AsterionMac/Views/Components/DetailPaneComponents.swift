import SwiftUI

private struct AsterionDetailPageFrame: ViewModifier {
    let maxContentWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(.horizontal, 46)
            .padding(.top, 30)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension View {
    func asterionDetailPageFrame(maxContentWidth: CGFloat = 1_180) -> some View {
        modifier(AsterionDetailPageFrame(maxContentWidth: maxContentWidth))
    }
}

struct AsterionDetailMetadata: Identifiable {
    let icon: String
    let value: String

    var id: String { "\(icon):\(value)" }
}

struct AsterionDetailHero: View {
    let imageURL: URL?
    let title: String
    let subtitle: String?
    let metadata: [AsterionDetailMetadata]
    let summary: String?
    @Binding var showsFullSummary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.asterionCard
                }
            }
            .frame(width: 180, height: 260)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.10))
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .textSelection(.enabled)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(2)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { metadataItems }
                    VStack(alignment: .leading, spacing: 7) { metadataItems }
                }

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.asterionText.opacity(0.82))
                        .lineSpacing(3)
                        .lineLimit(showsFullSummary ? nil : 4)
                        .textSelection(.enabled)

                    if summary.count > 240 {
                        Button(showsFullSummary ? "Show less" : "More") {
                            showsFullSummary.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                        .tint(.asterionAccent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        ForEach(metadata) { item in
            Label(item.value, systemImage: item.icon)
                .font(.callout)
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)
        }
    }
}
