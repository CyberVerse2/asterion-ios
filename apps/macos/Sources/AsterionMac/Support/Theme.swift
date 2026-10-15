import AppKit
import SwiftUI

// Asterion is a dark room and the content is the light. The interface stays
// monochrome; colour enters only through artwork, and the glow it casts onto
// the canvas (see `ArtworkGlow`). Media windows always render dark.
extension Color {
    // Surfaces, from the room itself to the most raised panel.
    static let asterionMediaCanvas = Color(hex: 0x0E0F13)
    static let asterionSurface = Color(hex: 0x16171C)
    static let asterionCard = Color(hex: 0x1E1F25)
    static let asterionRaised = Color(hex: 0x272830)
    static let asterionBackground = asterionMediaCanvas
    static let asterionSidebar = asterionMediaCanvas

    // Ink.
    static let asterionText = Color(hex: 0xF2F3F5)
    static let asterionMuted = Color(hex: 0x9A9DA8)
    static let asterionFaint = Color(hex: 0x5E616C)
    static let asterionReaderText = Color.primary
    static let asterionBorder = Color.white.opacity(0.08)
    static let asterionHairline = Color.white.opacity(0.06)
    static let asterionProgressTrack = Color.white.opacity(0.14)

    // Light. The "accent" is projector white: primary actions, progress,
    // and selection are lit, not coloured.
    static let asterionAccent = Color(hex: 0xF2F3F5)
    static let asterionAccentSoft = Color.white.opacity(0.10)

    // Signal colours carry state only.
    static let asterionLive = Color(hex: 0xFF4F5A)
    static let asterionSuccess = Color(hex: 0x52C98F)
    static let asterionWarning = Color(hex: 0xE9A945)

    static let asterionSidebarText = asterionText
    static let asterionSidebarMuted = asterionMuted
    static let asterionSidebarSelection = Color.white.opacity(0.08)
    static let asterionSidebarAccent = asterionAccent

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Native UI headline face for card titles and controls.
    static func asterionDisplay(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Title-card face: SF Pro Expanded. Used for page, hero, and shelf
    /// titles only, so it stays a signature rather than a texture.
    static func asterionTitle(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    static func asterionReading(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Utility face for eyebrows, counts, and timecodes.
    static func asterionMono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum AsterionLayout {
    /// Leading and trailing inset shared by headers, shelves, and grids.
    static let pageInset: CGFloat = 40
    /// Fallback height of the transparent toolbar band that content scrolls
    /// beneath. The live value is measured and published as
    /// `EnvironmentValues.asterionTopInset`, which also covers full screen.
    static let toolbarClearance: CGFloat = 52
    static let sectionSpacing: CGFloat = 44
    /// Height of the floating section bar on catalog pages.
    static let sectionBarHeight: CGFloat = 42
    /// Where catalog content without a hero begins, below the section bar.
    static func catalogContentTop(_ topInset: CGFloat) -> CGFloat {
        topInset + sectionBarHeight + 22
    }
}

extension EnvironmentValues {
    /// Measured height of the window chrome above the main content.
    @Entry var asterionTopInset: CGFloat = AsterionLayout.toolbarClearance
}

private struct AsterionDetailTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.asterionTitle(26))
            .foregroundStyle(Color.asterionText)
            .lineLimit(3)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .layoutPriority(1)
    }
}

/// Small tracked uppercase label above a title.
struct AsterionEyebrow: View {
    let text: String
    var color: Color = .asterionMuted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold).width(.expanded))
            .tracking(1.4)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Title block that opens every page without a hero.
struct AsterionPageHeader<Accessory: View>: View {
    @Environment(\.asterionTopInset) private var topInset
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.asterionTitle(34, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
        .padding(.horizontal, AsterionLayout.pageInset)
        .padding(.top, topInset + 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Centered empty or error state.
struct AsterionEmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.asterionMuted)
                .frame(width: 76, height: 76)
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.09), .white.opacity(0.0)],
                                center: .center,
                                startRadius: 2,
                                endRadius: 46
                            )
                        )
                }
                .padding(.bottom, 2)

            Text(title)
                .font(.asterionTitle(20))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.asterionMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)

            actions()
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Primary action: a lit, white capsule. One per screen.
struct AsterionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .labelStyle(AsterionButtonLabelStyle())
            .foregroundStyle(Color.asterionMediaCanvas)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(
                Color.asterionText.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.35),
                in: Capsule()
            )
            .shadow(color: .white.opacity(isEnabled ? 0.16 : 0), radius: 14)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary action: a smoked capsule that sits beside the primary without
/// competing with it, legible over bright artwork.
struct AsterionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AsterionSecondaryButtonBody(configuration: configuration)
    }
}

private struct AsterionSecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .labelStyle(AsterionButtonLabelStyle())
            .foregroundStyle(Color.asterionText.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 16)
            .frame(minWidth: 38, minHeight: 38)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.28)))
                    .overlay(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.08 : 0))))
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
            .environment(\.colorScheme, .dark)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
    }
}

private struct AsterionButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .font(.system(size: 12, weight: .bold))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == AsterionPrimaryButtonStyle {
    static var asterionPrimary: AsterionPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == AsterionSecondaryButtonStyle {
    static var asterionSecondary: AsterionSecondaryButtonStyle { .init() }
}

/// Progress as a line of light on a dark track.
struct AsterionLightLine: View {
    let fraction: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.asterionProgressTrack)
                Capsule()
                    .fill(Color.asterionText)
                    .frame(width: width)
                    .shadow(color: .white.opacity(0.55), radius: 4)
                    .opacity(width > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// Placeholder that breathes while artwork and shelves load.
struct AsterionSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cornerRadius: CGFloat = 10
    @State private var isDim = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.asterionSurface)
            .opacity(isDim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func asterionDetailTitleStyle() -> some View {
        modifier(AsterionDetailTitleStyle())
    }

    /// Rounded surface used for rows, panels, and grouped content.
    func asterionPanel(cornerRadius: CGFloat = 16, fill: Color = .asterionSurface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.asterionBorder)
            }
    }
}

enum GenreStyle {
    static func color(for genres: [String]?) -> Color {
        guard let genre = genres?.first?.lowercased() else { return .asterionMuted }
        if genre.contains("fantasy") || genre.contains("xianxia") { return Color(hex: 0xC2A05A) }
        if genre.contains("action") || genre.contains("martial") { return Color(hex: 0xC97A55) }
        if genre.contains("romance") { return Color(hex: 0xC46A8C) }
        if genre.contains("sci") { return Color(hex: 0x6A93BD) }
        if genre.contains("horror") { return Color(hex: 0x8C5A5A) }
        return Color(hex: 0x5E9C82)
    }
}
