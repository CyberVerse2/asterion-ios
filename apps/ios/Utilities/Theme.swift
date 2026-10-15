import ImageIO
import SwiftUI
import UIKit

// Asterion is a dark room and the content is the light. The interface stays
// monochrome; colour enters only through artwork and the glow it casts onto
// the canvas (see `ArtworkGlow`). The app renders dark; only the reader's
// System theme follows the device appearance.
extension Color {
    // Surfaces, from the room itself to the most raised panel.
    static let asterionBackground = Color(hex: 0x0E0F13)
    static let asterionSurface = Color(hex: 0x16171C)
    static let asterionCard = Color(hex: 0x1E1F25)
    static let asterionCardHover = Color(hex: 0x272830)
    static let asterionRaised = Color(hex: 0x272830)

    // Ink.
    static let asterionText = Color(hex: 0xF2F3F5)
    static let asterionMuted = Color(hex: 0x9A9DA8)
    static let asterionDim = Color(hex: 0x7C7F8A)
    static let asterionFaint = Color(hex: 0x5E616C)
    static let asterionSynopsis = Color(hex: 0xC4C6CE)
    static let asterionBorder = Color.white.opacity(0.08)
    static let asterionBorderHover = Color.white.opacity(0.18)
    static let asterionHairline = Color.white.opacity(0.06)
    static let asterionProgressTrack = Color.white.opacity(0.14)

    // Light. "Ink" is projector white: primary actions, progress, and
    // selection are lit, not coloured.
    static let asterionInk = Color(hex: 0xF2F3F5)
    static let asterionOnInk = Color(hex: 0x0E0F13)
    static let goldAccent = asterionInk
    static let asterionHighlight = asterionInk

    // Signal colours carry state only.
    static let asterionLive = Color(hex: 0xFF4F5A)
    static let asterionSuccess = Color(hex: 0x52C98F)
    static let asterionWarning = Color(hex: 0xE9A945)

    /// Reader text for the System theme, which follows the device appearance.
    static let asterionReaderText = Color.family(light: 0x2B2C31, dark: 0xE6E6E9)
    static let asterionReaderPaper = Color.family(light: 0xFAF9F7, dark: 0x0E0F13)

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Resolves against the current traits. The reader lifts the app's dark
    /// override while its System theme is showing, so these follow the device.
    fileprivate static func family(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .light ? light : dark)
            }
        )
    }
}

/// The app renders dark through a window-level override (rather than a
/// SwiftUI colour-scheme preference) so the reader can switch the status bar
/// to dark text while a light page is showing.
enum WindowAppearance {
    @MainActor static func apply(_ style: UIUserInterfaceStyle) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    /// Title face. At 20pt and above it is SF Pro Expanded — the title-card
    /// signature shared with the desktop app. Smaller sizes use the regular
    /// width so card titles stay compact.
    static func asterionDisplay(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        guard size >= 20 else {
            return .system(size: dynamicSize(size, maxScale: 1.3), weight: weight == .regular ? .medium : .semibold)
        }
        let titleWeight: Font.Weight = switch weight {
        case .light, .regular: .semibold
        case .medium: size >= 26 ? .heavy : .bold
        default: .heavy
        }
        return .system(size: dynamicSize(size, maxScale: 1.15), weight: titleWeight).width(.expanded)
    }

    /// Explicit title-card face for headers that must be expanded.
    static func asterionTitle(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: dynamicSize(size, maxScale: 1.15), weight: weight).width(.expanded)
    }

    static func asterionReading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: dynamicSize(size, maxScale: 1.3), weight: weight, design: .default)
    }

    /// Supporting face for secondary headings and numbers.
    static func asterionSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if size >= 26 {
            return .system(size: dynamicSize(size, maxScale: 1.15), weight: .heavy).width(.expanded)
        }
        return .system(size: dynamicSize(size, maxScale: 1.3), weight: weight == .regular ? .medium : weight)
    }

    /// The reader's Literary typeface option.
    static func asterionLiterary(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-Regular", size: size)
    }

    /// Utility face for counts, timecodes, and episode numbers.
    static func asterionMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: dynamicSize(size, maxScale: 1.3), weight: weight, design: .monospaced)
    }

    /// Follows the Dynamic Type setting within what the layout can hold:
    /// titles grow a little, body text and numbers a bit more. The reader's
    /// page text has its own size control and doesn't go through here.
    private static func dynamicSize(_ size: CGFloat, maxScale: CGFloat) -> CGFloat {
        let scaled = UIFontMetrics.default.scaledValue(for: size)
        return min(max(scaled, size * 0.85), size * maxScale)
    }
}

enum AsterionLayout {
    static func isWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
        #endif
    }

    static func pageMaxWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        1460
        #else
        isWide(sizeClass) ? 1180 : .infinity
        #endif
    }

    static func pagePadding(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        40
        #else
        isWide(sizeClass) ? 32 : 20
        #endif
    }

    static func posterColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        if isWide(sizeClass) {
            return [GridItem(.adaptive(minimum: 156, maximum: 200), spacing: 18, alignment: .top)]
        }
        return [
            GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top),
            GridItem(.flexible(minimum: 0), alignment: .top),
        ]
    }

    static func episodeColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        if isWide(sizeClass) {
            return [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 16, alignment: .top)]
        }
        return [GridItem(.flexible(minimum: 0))]
    }

    static func continueCardSize(_ sizeClass: UserInterfaceSizeClass?) -> CGSize {
        isWide(sizeClass) ? CGSize(width: 340, height: 191) : CGSize(width: 290, height: 163)
    }

    static func shelfPosterSize(_ sizeClass: UserInterfaceSizeClass?) -> CGSize {
        isWide(sizeClass) ? CGSize(width: 164, height: 246) : CGSize(width: 132, height: 198)
    }

    static let sectionSpacing: CGFloat = 36
}

struct AsterionBackdrop: View {
    var body: some View {
        Color.asterionBackground.ignoresSafeArea()
    }
}

extension View {
    func asterionGlassSurface(
        cornerRadius: CGFloat = 20,
        interactive: Bool = false
    ) -> some View {
        self.asterionPanel(cornerRadius: cornerRadius)
    }

    /// Selection pill: lit white when selected, smoked otherwise.
    func asterionGlassPill(isSelected: Bool, interactive: Bool = true) -> some View {
        self
            .background(
                isSelected ? Color.asterionInk : Color.white.opacity(0.07),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0 : 0.08)))
            .foregroundStyle(isSelected ? Color.asterionOnInk : Color.asterionText)
    }

    func asterionInsetSurface(cornerRadius: CGFloat = 20) -> some View {
        self.asterionPanel(cornerRadius: cornerRadius)
    }

    /// Rounded surface plus hairline border for rows and grouped content.
    func asterionPanel(cornerRadius: CGFloat = 16, fill: Color = .asterionSurface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.asterionBorder)
            }
    }
}

/// Primary action: a lit, white capsule. One per screen.
struct AsterionFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.asterionOnInk)
            .background(
                Color.asterionInk.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.35),
                in: Capsule()
            )
            .shadow(color: .white.opacity(isEnabled ? 0.14 : 0), radius: 14)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: a smoked capsule beside the primary.
struct AsterionOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.asterionText)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.25)))
                    .overlay(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0)))
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small tracked uppercase label above a title.
struct AsterionEyebrow: View {
    let text: String
    var color: Color = .asterionMuted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold).width(.expanded))
            .tracking(1.3)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Progress as a line of light on a dark track.
struct AsterionLightLine: View {
    let fraction: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.asterionProgressTrack)
                Capsule()
                    .fill(Color.asterionInk)
                    .frame(width: geometry.size.width * clamped)
                    .shadow(color: .white.opacity(0.55), radius: 4)
                    .opacity(clamped > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// Pulsing live indicator: the only place the signal red appears.
struct AsterionLiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.asterionLive)
                .frame(width: 6, height: 6)
                .shadow(color: Color.asterionLive.opacity(0.9), radius: isPulsing ? 5 : 1)
                .opacity(isPulsing ? 1 : 0.6)
            Text("LIVE")
                .font(.system(size: 9.5, weight: .heavy).width(.expanded))
                .tracking(1)
                .foregroundStyle(Color.asterionLive)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
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

// MARK: - Artwork glow

/// Extracts the light an artwork would cast into a dark room: its most
/// characteristic saturated colour, normalised to read as a glow.
actor ArtworkPaletteCache {
    static let shared = ArtworkPaletteCache()

    private var tones: [URL: ArtworkTone] = [:]
    private var inFlight: [URL: Task<ArtworkTone?, Never>] = [:]

    func tone(for url: URL) async -> ArtworkTone? {
        if let cached = tones[url] { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task.detached(priority: .utility) { () -> ArtworkTone? in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
            return ArtworkTone.extract(from: data)
        }
        inFlight[url] = task
        let tone = await task.value
        inFlight[url] = nil
        if let tone { tones[url] = tone }
        return tone
    }
}

nonisolated struct ArtworkTone: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    static let neutral = ArtworkTone(red: 0.42, green: 0.45, blue: 0.56)

    static func extract(from data: Data) -> ArtworkTone? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 32,
                  ] as CFDictionary
              ),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let width = thumbnail.width
        let height = thumbnail.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Weight each pixel by saturation and mid-range brightness so the
        // dominant hue wins over black letterboxing and white title text.
        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let maximum = max(r, g, b)
            let minimum = min(r, g, b)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let brightnessWeight = 1 - abs(maximum - 0.6) * 1.4
            let weight = max(0.02, saturation * saturation) * max(0.05, brightnessWeight)
            red += r * weight
            green += g * weight
            blue += b * weight
            total += weight
        }
        guard total > 0 else { return nil }

        let color = UIColor(red: red / total, green: green / total, blue: blue / total, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let adjusted = UIColor(
            hue: hue,
            saturation: min(0.78, max(0.28, saturation * 1.25)),
            brightness: min(0.88, max(0.62, brightness * 1.2)),
            alpha: 1
        )
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        adjusted.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return ArtworkTone(red: Double(r), green: Double(g), blue: Double(b))
    }
}

/// Resolves the tone for an artwork URL and animates between tones.
struct ArtworkToneReader<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (Color) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tone: ArtworkTone = .neutral

    var body: some View {
        content(tone.color)
            .task(id: url) {
                guard let url, let resolved = await ArtworkPaletteCache.shared.tone(for: url) else { return }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                    tone = resolved
                }
            }
    }
}

/// The light an artwork casts onto the top of a page. Place it behind
/// scrolling content; it fades into the canvas over `height` points.
struct ArtworkGlow: View {
    let url: URL?
    var height: CGFloat = 620
    var intensity: Double = 1

    var body: some View {
        ArtworkToneReader(url: url) { tone in
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [tone.opacity(0.46 * intensity), tone.opacity(0.12 * intensity), .clear],
                    center: UnitPoint(x: 0.7, y: 0.0),
                    startRadius: 10,
                    endRadius: height
                )
                RadialGradient(
                    colors: [tone.opacity(0.2 * intensity), .clear],
                    center: UnitPoint(x: 0.05, y: 0.12),
                    startRadius: 10,
                    endRadius: height * 0.7
                )
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Haptics

/// A few quiet taps for the moments that matter: saving, finishing a
/// download, changing a setting. Nothing buzzes for ordinary navigation.
enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
