import SwiftUI

// MARK: - Page frame

private struct AsterionDetailPageFrame: ViewModifier {
    @Environment(\.asterionTopInset) private var topInset

    func body(content: Content) -> some View {
        content
            // The detail page sits beneath the transparent toolbar band.
            .padding(.top, topInset + 26)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AsterionDetailInset: ViewModifier {
    let maxContentWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(.horizontal, AsterionLayout.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Vertical rhythm of a detail page: clears the toolbar band at the top
    /// and leaves breathing room at the end. Sections inset themselves so
    /// shelves can bleed to the window edge.
    func asterionDetailPageFrame() -> some View {
        modifier(AsterionDetailPageFrame())
    }

    /// Leading and trailing page inset with a readable maximum width.
    func asterionDetailInset(maxContentWidth: CGFloat = 1_180) -> some View {
        modifier(AsterionDetailInset(maxContentWidth: maxContentWidth))
    }

    /// Smoked capsule used for menus and fields that sit beside
    /// `.asterionSecondary` buttons.
    func asterionSmokedCapsule(height: CGFloat = 38) -> some View {
        frame(height: height)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.28)))
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Backdrop

/// The light a title's artwork casts onto the top of its page: the tone glow,
/// textured by a faint, heavily blurred copy of the art.
struct AsterionDetailBackdrop: View {
    let url: URL?
    var height: CGFloat = 820

    var body: some View {
        ZStack(alignment: .top) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.4))) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(height: height * 0.72)
            .frame(maxWidth: .infinity)
            .clipped()
            .blur(radius: 80, opaque: false)
            .saturation(1.15)
            .opacity(0.16)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.7), location: 0.45),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            ArtworkGlow(url: url, height: height)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Hero

/// Key art for a title page: a poster with a hairline edge and a deep,
/// soft shadow so it floats above its own glow.
struct AsterionDetailPoster: View {
    let url: URL?
    var fallbackSystemImage = "photo"
    var width: CGFloat = 240
    var height: CGFloat = 360

    var body: some View {
        ArtworkImage(url: url, fallbackSystemImage: fallbackSystemImage)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.45), radius: 34, y: 22)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// Title page hero: poster beside eyebrow, title, byline, one plain
/// metadata line, synopsis, actions, and a footer for progress and errors.
struct AsterionDetailHero<Actions: View, Footer: View>: View {
    let imageURL: URL?
    var fallbackSystemImage = "photo"
    let eyebrow: String
    let title: String
    var byline: String?
    var metadata: [String] = []
    var secondaryMetadata: [String] = []
    var summary: String?
    @Binding var showsFullSummary: Bool
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let footer: () -> Footer

    init(
        imageURL: URL?,
        fallbackSystemImage: String = "photo",
        eyebrow: String,
        title: String,
        byline: String? = nil,
        metadata: [String] = [],
        secondaryMetadata: [String] = [],
        summary: String? = nil,
        showsFullSummary: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.imageURL = imageURL
        self.fallbackSystemImage = fallbackSystemImage
        self.eyebrow = eyebrow
        self.title = title
        self.byline = byline
        self.metadata = metadata
        self.secondaryMetadata = secondaryMetadata
        self.summary = summary
        self._showsFullSummary = showsFullSummary
        self.actions = actions
        self.footer = footer
    }

    var body: some View {
        HStack(alignment: .top, spacing: 44) {
            AsterionDetailPoster(url: imageURL, fallbackSystemImage: fallbackSystemImage)

            VStack(alignment: .leading, spacing: 0) {
                AsterionEyebrow(text: eyebrow, color: .white.opacity(0.7))

                Text(title)
                    .font(.asterionTitle(40, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 12)

                if let byline, !byline.isEmpty {
                    Text(byline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(2)
                        .padding(.top, 8)
                }

                if !metadata.isEmpty {
                    Text(metadata.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .padding(.top, 16)
                }

                if !secondaryMetadata.isEmpty {
                    Text(secondaryMetadata.joined(separator: "  ·  "))
                        .font(.asterionMono(11.5, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(2)
                        .padding(.top, 6)
                }

                if let summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary)
                            .font(.system(size: 14.5))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineSpacing(4)
                            .lineLimit(showsFullSummary ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if summary.count > 240 {
                            Button(showsFullSummary ? "Show less" : "More") {
                                showsFullSummary.toggle()
                            }
                            .buttonStyle(AsterionDetailTextButtonStyle())
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.top, 20)
                }

                HStack(spacing: 10) {
                    actions()
                }
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 10) {
                    footer()
                }
                .padding(.top, 14)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Quiet inline text action ("More", "Show all cast").
struct AsterionDetailTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AsterionDetailTextButtonBody(configuration: configuration)
    }
}

private struct AsterionDetailTextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color.asterionText.opacity(configuration.isPressed ? 0.6 : (isHovering ? 1 : 0.82)))
            .underline(isHovering)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}

/// Reading or watching progress beneath the hero actions.
struct AsterionDetailProgress: View {
    let fraction: Double
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                AsterionLightLine(fraction: fraction, height: 3)
                    .frame(maxWidth: 320)
                Text("\(Int((min(1, max(0, fraction)) * 100).rounded()))%")
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                    .accessibilityHidden(true)
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}

/// Inline error or warning text: amber, never accent.
struct AsterionDetailNotice: View {
    let message: String
    var systemImage = "exclamationmark.triangle.fill"
    var color: Color = .asterionWarning

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(color)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

// MARK: - Sections

/// Section on a title page: an expanded-face header with a mono count, then
/// content. Bleeding sections let horizontal shelves run to the window edge.
struct AsterionDetailSection<Content: View, Accessory: View>: View {
    let title: String
    var count: String?
    var bleedsContent = false
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        count: String? = nil,
        bleedsContent: Bool = false,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.bleedsContent = bleedsContent
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title)
                    .font(.asterionTitle(18, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                accessory()
                Spacer(minLength: 8)
                if let count, !count.isEmpty {
                    Text(count)
                        .font(.asterionMono(11.5, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                }
            }
            .asterionDetailInset()

            if bleedsContent {
                content()
            } else {
                content()
                    .asterionDetailInset()
            }
        }
    }
}

/// Hairline between rows inside an `.asterionPanel`.
struct AsterionDetailRowDivider: View {
    var leadingInset: CGFloat = 18

    var body: some View {
        Rectangle()
            .fill(Color.asterionHairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// A label/value row for fact panels.
struct AsterionDetailFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.asterionMuted)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.asterionText.opacity(0.92))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

/// Smoked search field that matches the secondary buttons beside it.
struct AsterionDetailSearchField: View {
    let prompt: String
    @Binding var text: String
    var monospacedDigits = false
    var accessibilityLabel: String?
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.asterionMuted)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(monospacedDigits ? .system(size: 13).monospacedDigit() : .system(size: 13))
                .foregroundStyle(Color.asterionText)
                .onSubmit(onSubmit)
                .accessibilityLabel(accessibilityLabel ?? prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asterionMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .asterionSmokedCapsule()
    }
}

/// Small circular control used for per-episode downloads.
struct AsterionDetailCircleIcon: View {
    let systemImage: String
    var tint: Color = .asterionText

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white.opacity(0.06)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
            .contentShape(Circle())
    }
}

// MARK: - Episodes

/// 16:9 episode card: artwork with the episode number in mono, a light line
/// for partial progress, and an unmistakable current/watched state.
struct AsterionEpisodeCard<Accessory: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let imageURL: URL?
    let numberLabel: String
    let artworkVariant: Int
    let title: String
    let status: String
    var progress: Double?
    var isCurrent = false
    var isWatched = false
    let help: String
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                artwork
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(help)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(status)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isWatched && !isCurrent ? Color.asterionText.opacity(0.7) : Color.asterionText)
                        .lineLimit(1)
                    Text(status)
                        .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                accessory()
            }
            .padding(.horizontal, 2)
        }
        .frame(width: AsterionCardMetrics.episodeWidth, alignment: .leading)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.08 + CGFloat(artworkVariant % 3) * 0.05)
                        .offset(x: CGFloat((artworkVariant % 3) - 1) * 10)
                } else {
                    Color.asterionSurface
                }
            }
            .frame(width: AsterionCardMetrics.episodeWidth, height: AsterionCardMetrics.episodeHeight)
            .clipped()
            .saturation(isWatched && !isCurrent ? 0.35 : 1)
            .opacity(isWatched && !isCurrent && !isHovering ? 0.55 : 1)
            .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(numberLabel)
                        .font(.asterionMono(11.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    if isWatched {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.asterionMediaCanvas)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.asterionSuccess))
                            .accessibilityHidden(true)
                    }
                }
                if let progress, progress > 0, progress < 1 {
                    AsterionLightLine(fraction: progress, height: 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 9)

            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.asterionMediaCanvas)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.asterionText))
                .shadow(color: .white.opacity(0.25), radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isHovering || isCurrent ? 1 : 0)
                .scaleEffect(isHovering || reduceMotion ? 1 : 0.9)
                .accessibilityHidden(true)
        }
        .frame(width: AsterionCardMetrics.episodeWidth, height: AsterionCardMetrics.episodeHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isCurrent ? Color.asterionText : Color.white.opacity(isHovering ? 0.24 : 0.08),
                    lineWidth: isCurrent ? 2 : 1
                )
        }
        .shadow(color: isCurrent ? .white.opacity(0.12) : .clear, radius: 14)
        .offset(y: isHovering && !reduceMotion ? -2 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
    }
}

/// Compact tile for long episode lists; the current episode is lit white.
struct AsterionEpisodeTile<Accessory: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let number: Int
    let status: String
    var progress: Double?
    var isCurrent = false
    var isWatched = false
    let help: String
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Text(String(format: "%03d", number))
                        .font(.asterionMono(15, weight: .semibold))
                        .foregroundStyle(numberColor)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            if isCurrent {
                                Circle()
                                    .fill(Color.asterionText)
                                    .frame(width: 5, height: 5)
                                    .shadow(color: .white.opacity(0.7), radius: 3)
                            } else if isWatched {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .foregroundStyle(Color.asterionSuccess)
                            }
                            Text(status)
                                .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionMuted)
                                .lineLimit(1)
                        }
                        if let progress, progress > 0, progress < 1 {
                            AsterionLightLine(fraction: progress, height: 2)
                                .frame(maxWidth: 64)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(status)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])

            accessory()
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isCurrent ? Color.asterionText : Color.white.opacity(isHovering ? 0.16 : 0.08),
                    lineWidth: isCurrent ? 1.5 : 1
                )
        }
        .shadow(color: isCurrent ? .white.opacity(0.10) : .clear, radius: 10)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
        .accessibilityElement(children: .contain)
    }

    private var numberColor: Color {
        if isCurrent { return .asterionText }
        if isWatched { return .asterionFaint }
        return Color.asterionText.opacity(0.88)
    }

    private var fill: Color {
        if isCurrent { return Color.white.opacity(0.10) }
        return isHovering ? .asterionCard : .asterionSurface
    }
}

// MARK: - Loading

/// Opening skeleton for a title page, shaped like the hero and first section.
struct AsterionDetailSkeleton: View {
    var accessibilityLabel = "Loading"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                HStack(alignment: .top, spacing: 44) {
                    AsterionSkeleton(cornerRadius: 12)
                        .frame(width: 240, height: 360)

                    VStack(alignment: .leading, spacing: 0) {
                        AsterionSkeleton(cornerRadius: 3).frame(width: 110, height: 10)
                        AsterionSkeleton(cornerRadius: 6).frame(maxWidth: 440).frame(height: 38)
                            .padding(.top, 16)
                        AsterionSkeleton(cornerRadius: 6).frame(width: 260, height: 38)
                            .padding(.top, 8)
                        AsterionSkeleton(cornerRadius: 4).frame(width: 180, height: 13)
                            .padding(.top, 14)
                        AsterionSkeleton(cornerRadius: 4).frame(width: 300, height: 11)
                            .padding(.top, 18)
                        VStack(alignment: .leading, spacing: 9) {
                            AsterionSkeleton(cornerRadius: 3).frame(maxWidth: 600).frame(height: 10)
                            AsterionSkeleton(cornerRadius: 3).frame(maxWidth: 570).frame(height: 10)
                            AsterionSkeleton(cornerRadius: 3).frame(maxWidth: 380).frame(height: 10)
                        }
                        .padding(.top, 22)
                        HStack(spacing: 10) {
                            AsterionSkeleton(cornerRadius: 19).frame(width: 168, height: 38)
                            AsterionSkeleton(cornerRadius: 19).frame(width: 46, height: 38)
                            AsterionSkeleton(cornerRadius: 19).frame(width: 46, height: 38)
                        }
                        .padding(.top, 26)
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .asterionDetailInset()

                VStack(alignment: .leading, spacing: 16) {
                    AsterionSkeleton(cornerRadius: 4)
                        .frame(width: 150, height: 16)
                    // Drawn in an overlay so the row never widens the window.
                    Color.clear
                        .frame(height: AsterionCardMetrics.episodeHeight)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 16) {
                                ForEach(0..<5, id: \.self) { _ in
                                    AsterionSkeleton(cornerRadius: 10)
                                        .frame(width: AsterionCardMetrics.episodeWidth, height: AsterionCardMetrics.episodeHeight)
                                }
                            }
                            .fixedSize()
                        }
                        .clipped()
                }
                .asterionDetailInset()
            }
            .asterionDetailPageFrame()
        }
        .scrollDisabled(true)
        .hidingScrollIndicators()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Skeleton rows inside a panel while a list page loads.
struct AsterionDetailRowsSkeleton: View {
    var rows = 8

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                if index > 0 {
                    AsterionDetailRowDivider()
                }
                HStack(spacing: 16) {
                    AsterionSkeleton(cornerRadius: 3).frame(width: 36, height: 10)
                    AsterionSkeleton(cornerRadius: 3)
                        .frame(width: CGFloat(180 + (index * 53) % 160), height: 10)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(height: 46)
            }
        }
        .asterionPanel(cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
