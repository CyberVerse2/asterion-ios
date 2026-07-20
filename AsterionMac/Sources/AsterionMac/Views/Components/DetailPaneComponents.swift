import SwiftUI

struct AsterionDetailMetadata: Identifiable {
    let icon: String
    let value: String

    var id: String { "\(icon):\(value)" }
}

struct AsterionDetailHero: View {
    let imageURL: URL?
    let badge: String
    let title: String
    let subtitle: String?
    let metadata: [AsterionDetailMetadata]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.asterionCard
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.04), .black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(badge)
                    .font(.asterionMono(9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.12))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
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
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { metadataItems }
                VStack(alignment: .leading, spacing: 8) { metadataItems }
            }
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
