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
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.asterionCard
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 218)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.04), .black.opacity(0.18), .black.opacity(0.94)],
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.asterionDisplay(25, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .textSelection(.enabled)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.12))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(metadata) { item in
                    Label {
                        Text(item.value).lineLimit(2)
                    } icon: {
                        Image(systemName: item.icon).frame(width: 18)
                    }
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
