import AppKit
import ImageIO
import SwiftUI

/// Extracts the light an artwork would cast into a dark room: its most
/// characteristic saturated colour, normalised so it reads as a glow on the
/// canvas rather than as a flat swatch.
actor ArtworkPaletteCache {
    static let shared = ArtworkPaletteCache()

    private var colors: [URL: ArtworkTone] = [:]
    private var inFlight: [URL: Task<ArtworkTone?, Never>] = [:]

    func tone(for url: URL) async -> ArtworkTone? {
        if let cached = colors[url] { return cached }
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
        if let tone {
            colors[url] = tone
        }
        return tone
    }
}

struct ArtworkTone: Equatable, Sendable {
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
              ) else {
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
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
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

        return ArtworkTone(red: red / total, green: green / total, blue: blue / total)
            .normalisedForGlow()
    }

    /// Lifts brightness and saturation into a range that glows on #0E0F13.
    private func normalisedForGlow() -> ArtworkTone {
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let adjusted = NSColor(
            hue: hue,
            saturation: min(0.78, max(0.28, saturation * 1.25)),
            brightness: min(0.88, max(0.62, brightness * 1.2)),
            alpha: 1
        ).usingColorSpace(.sRGB) ?? color
        return ArtworkTone(
            red: Double(adjusted.redComponent),
            green: Double(adjusted.greenComponent),
            blue: Double(adjusted.blueComponent)
        )
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
    var height: CGFloat = 720
    var intensity: Double = 1

    var body: some View {
        ArtworkToneReader(url: url) { tone in
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [tone.opacity(0.42 * intensity), tone.opacity(0.10 * intensity), .clear],
                    center: UnitPoint(x: 0.72, y: 0.0),
                    startRadius: 20,
                    endRadius: height * 1.05
                )
                RadialGradient(
                    colors: [tone.opacity(0.18 * intensity), .clear],
                    center: UnitPoint(x: 0.08, y: 0.1),
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
