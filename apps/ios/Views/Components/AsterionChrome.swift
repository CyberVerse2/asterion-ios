import SwiftUI

struct AsterionMark: View {
    var size: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .strokeBorder(Color.asterionInk, lineWidth: 1.4)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                    .fill(Color.asterionInk)
                    .frame(width: size * 0.34, height: size * 0.34)
            }
            .accessibilityHidden(true)
    }
}

struct AsterionPageHeader: View {
    enum Style {
        case wordmark
        case page
    }

    let title: String
    var subtitle: String? = nil
    var style: Style = .page

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.asterionDisplay(style == .wordmark ? 36 : 32, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .tracking(-0.6)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.asterionReading(16))
                    .foregroundStyle(Color.asterionSynopsis)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

struct AsterionSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.asterionDisplay(22, weight: .medium))
            .foregroundStyle(Color.asterionText)
    }
}

struct AsterionIndexTabs<Item: Hashable>: View {
    enum Rank {
        case header
        case section
        case subheader
    }

    let items: [Item]
    let title: (Item) -> String
    var rank: Rank = .header
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .lastTextBaseline, spacing: itemSpacing) {
                ForEach(items, id: \.self) { item in
                    let selected = selection == item
                    Button {
                        withAnimation(.snappy) { selection = item }
                    } label: {
                        VStack(alignment: .leading, spacing: underlineGap) {
                            Text(title(item))
                                .font(labelFont)
                                .foregroundStyle(selected ? Color.asterionText : Color.asterionMuted)
                                .tracking(rank == .header ? -0.4 : 0)

                            if showsUnderline {
                                Rectangle()
                                    .fill(selected ? Color.asterionInk : Color.clear)
                                    .frame(height: rank == .header ? 1.5 : 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(Color.asterionBackground)
    }

    private var showsUnderline: Bool {
        switch rank {
        case .header, .section: true
        case .subheader: false
        }
    }

    private var itemSpacing: CGFloat {
        switch rank {
        case .header: 20
        case .section: 16
        case .subheader: 18
        }
    }

    private var underlineGap: CGFloat {
        switch rank {
        case .header: 7
        case .section: 5
        case .subheader: 0
        }
    }

    private var topPadding: CGFloat {
        switch rank {
        case .header: 8
        case .section: 4
        case .subheader: 14
        }
    }

    private var bottomPadding: CGFloat {
        switch rank {
        case .header: 2
        case .section: 4
        case .subheader: 12
        }
    }

    private var labelFont: Font {
        switch rank {
        case .header:
            .asterionDisplay(26, weight: .medium)
        case .section:
            .asterionDisplay(18, weight: .medium)
        case .subheader:
            .asterionDisplay(17, weight: .regular)
        }
    }
}

struct AsterionContinueCard<Artwork: View>: View {
    let title: String
    let subtitle: String
    let percentage: Double
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder var artwork: () -> Artwork

    private var cardSize: CGSize {
        AsterionLayout.continueCardSize(horizontalSizeClass)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork()
                .frame(width: cardSize.width, height: cardSize.height)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.28), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.asterionDisplay(22, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.asterionReading(13))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule()
                            .fill(.white)
                            .frame(width: geo.size.width * min(1, max(0, percentage / 100)))
                    }
                }
                .frame(height: 3)
            }
            .padding(14)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct AsterionEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(Color.asterionMuted)

            Text(title)
                .font(.asterionDisplay(24, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.asterionReading(15))
                    .foregroundStyle(Color.asterionMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
    }
}
