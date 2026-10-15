import SwiftUI

/// Genre-derived styling for cover placeholders. The interface is monochrome,
/// so genres no longer carry colour: every genre resolves to the same faint
/// ink, and the placeholder mark is a quiet SF Symbol rather than an emoji.
enum GenreStyle {
    /// Placeholder ink for covers without artwork. Always neutral.
    static func color(for genres: [String]?) -> Color {
        Color.asterionFaint
    }

    /// A faint SF Symbol that hints at the genre on a placeholder cover.
    static func symbol(for genres: [String]?) -> String {
        guard let genre = genres?.first?.lowercased() else { return "book.closed" }
        if genre.contains("fantasy") || genre.contains("xuanhuan") { return "sparkles" }
        if genre.contains("action") || genre.contains("martial") || genre.contains("wuxia") { return "flame" }
        if genre.contains("romance") { return "heart" }
        if genre.contains("sci") { return "atom" }
        if genre.contains("horror") { return "moon" }
        if genre.contains("adventure") { return "map" }
        if genre.contains("mystery") { return "magnifyingglass" }
        if genre.contains("drama") { return "theatermasks" }
        if genre.contains("comedy") { return "face.smiling" }
        if genre.contains("system") || genre.contains("reincarnation") { return "arrow.triangle.2.circlepath" }
        return "book.closed"
    }
}
