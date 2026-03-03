import SwiftUI

enum GenreStyle {

    private static let genreColors: [(keyword: String, color: Color)] = [
        ("fantasy",        Color(red: 0.545, green: 0.412, blue: 0.078)),  // #8B6914
        ("action",         Color(red: 0.627, green: 0.322, blue: 0.176)),  // #A0522D
        ("romance",        Color(red: 0.545, green: 0.227, blue: 0.384)),  // #8B3A62
        ("sci-fi",         Color(red: 0.29,  green: 0.42,  blue: 0.541)),  // #4A6B8A
        ("horror",         Color(red: 0.42,  green: 0.227, blue: 0.227)),  // #6B3A3A
        ("adventure",      Color(red: 0.227, green: 0.42,  blue: 0.353)),  // #3A6B5A
        ("mystery",        Color(red: 0.353, green: 0.29,  blue: 0.42)),   // #5A4A6B
        ("drama",          Color(red: 0.42,  green: 0.357, blue: 0.294)),  // #6B5B4B
        ("comedy",         Color(red: 0.545, green: 0.545, blue: 0.227)),  // #8B8B3A
        ("martial",        Color(red: 0.478, green: 0.29,  blue: 0.227)),  // #7A4A3A
        ("xuanhuan",       Color(red: 0.42,  green: 0.353, blue: 0.541)),  // #6B5A8A
        ("wuxia",          Color(red: 0.353, green: 0.42,  blue: 0.29)),   // #5A6B4A
        ("reincarnation",  Color(red: 0.29,  green: 0.42,  blue: 0.42)),   // #4A6B6B
        ("system",         Color(red: 0.42,  green: 0.42,  blue: 0.29)),   // #6B6B4A
    ]

    private static let fallbackHues: [Color] = [
        Color(red: 0.545, green: 0.412, blue: 0.078),
        Color(red: 0.29,  green: 0.42,  blue: 0.541),
        Color(red: 0.42,  green: 0.357, blue: 0.294),
        Color(red: 0.353, green: 0.29,  blue: 0.42),
        Color(red: 0.227, green: 0.42,  blue: 0.353),
        Color(red: 0.545, green: 0.227, blue: 0.384),
        Color(red: 0.478, green: 0.29,  blue: 0.227),
    ]

    private static let defaultColor = Color(red: 0.42, green: 0.392, blue: 0.349) // #6B6459

    static func color(for genres: [String]?) -> Color {
        guard let genres, !genres.isEmpty else { return defaultColor }
        for genre in genres {
            let low = genre.lowercased()
            for entry in genreColors {
                if low.contains(entry.keyword) { return entry.color }
            }
        }
        let hash = genres[0].unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return fallbackHues[hash % fallbackHues.count]
    }

    static func emoji(for genres: [String]?) -> String {
        guard let genres, !genres.isEmpty else { return "📖" }
        let g = genres[0].lowercased()
        if g.contains("fantasy") || g.contains("xuanhuan") { return "⚔️" }
        if g.contains("action") || g.contains("martial") { return "🔥" }
        if g.contains("romance") { return "💜" }
        if g.contains("sci") { return "🚀" }
        if g.contains("horror") { return "🌑" }
        if g.contains("adventure") { return "🗺️" }
        if g.contains("mystery") { return "🔮" }
        if g.contains("drama") { return "🎭" }
        if g.contains("comedy") { return "😄" }
        if g.contains("system") || g.contains("reincarnation") { return "⟳" }
        return "📖"
    }
}
