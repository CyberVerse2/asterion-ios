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

/// Title block that opens a page without a hero.
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
                .font(.asterionTitle(style == .wordmark ? 32 : 30, weight: .heavy))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Shelf and section heading in the title-card face.
struct AsterionSectionLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.asterionTitle(17, weight: .bold))
                .foregroundStyle(Color.asterionText)
                .accessibilityAddTraits(.isHeader)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.asterionReading(13))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Navigation between sibling sections.
///
/// `.header` switches between whole catalogs (Novels, Anime, …) and is set
/// as large title-card words: the selected one lit, the rest faint.
/// `.section` and `.subheader` are a smoked pill bar with a lit selection,
/// matching the desktop section bar.
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

    @Namespace private var selectionNamespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if rank == .header {
                        headerTabs
                    } else {
                        pillTabs
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selection) { _, item in
                withAnimation(.snappy) { proxy.scrollTo(item, anchor: .center) }
            }
        }
        .padding(.top, rank == .header ? 6 : 4)
        .padding(.bottom, rank == .header ? 10 : 8)
    }

    private var headerTabs: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item
                Button {
                    if selection != item { Haptics.selection() }
                    withAnimation(.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.asterionTitle(22, weight: .heavy))
                        .foregroundStyle(selected ? Color.asterionText : Color.asterionFaint)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .id(item)
                .accessibilityAddTraits(selected ? [.isSelected, .isHeader] : [])
            }
        }
    }

    private var pillTabs: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item
                Button {
                    if selection != item { Haptics.selection() }
                    withAnimation(.spring(duration: 0.32, bounce: 0.12)) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.asterionReading(13, weight: .semibold))
                        .foregroundStyle(selected ? Color.asterionOnInk : Color.asterionText.opacity(0.78))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.asterionInk)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .id(item)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }
}

/// Resume card: 16:9 artwork with title, detail, and a light-line progress.
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
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.55), location: 0.6),
                    .init(color: .black.opacity(0.92), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.asterionReading(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int(percentage.rounded()))%")
                        .font(.asterionMono(11, weight: .medium))
                }
                .font(.asterionReading(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

                AsterionLightLine(fraction: percentage / 100, height: 3)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
    }
}

/// Centered empty or error state: what happened and what to do next.
struct AsterionEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.asterionMuted)
                .frame(width: 72, height: 72)
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.09), .white.opacity(0)],
                                center: .center,
                                startRadius: 2,
                                endRadius: 44
                            )
                        )
                }

            Text(title)
                .font(.asterionTitle(19, weight: .bold))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
    }
}

// MARK: - Status bar scrim

/// Pages hide the navigation bar, so scrolling content passes under the
/// clock. The canvas fades in behind the status bar to keep it legible.
struct AsterionStatusBarScrim: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color.asterionBackground.opacity(0.94), location: 0),
                    .init(color: Color.asterionBackground.opacity(0.94), location: 0.7),
                    .init(color: Color.asterionBackground.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func asterionStatusBarScrim() -> some View {
        modifier(AsterionStatusBarScrim())
    }
}
