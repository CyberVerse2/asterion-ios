import SwiftUI

// MARK: - Color Palette

extension Color {
    // #0D0C0B
    static let asterionBackground = Color(red: 0.051, green: 0.047, blue: 0.043)
    // #1A1816
    static let asterionCard = Color(red: 0.102, green: 0.094, blue: 0.086)
    // #E8DCC8
    static let asterionText = Color(red: 0.91, green: 0.863, blue: 0.784)
    // #C4A44A
    static let goldAccent = Color(red: 0.769, green: 0.643, blue: 0.29)
    // #6B6459
    static let asterionMuted = Color(red: 0.42, green: 0.392, blue: 0.349)
    // #4A4640
    static let asterionDim = Color(red: 0.29, green: 0.275, blue: 0.251)
    // #2A2722
    static let asterionBorder = Color(red: 0.165, green: 0.153, blue: 0.133)
    // #1E1C19
    static let asterionCardHover = Color(red: 0.118, green: 0.11, blue: 0.098)
    // #3A3530
    static let asterionBorderHover = Color(red: 0.227, green: 0.208, blue: 0.188)
    // #C8B8A0
    static let asterionReaderText = Color(red: 0.784, green: 0.722, blue: 0.627)
    // #A09888
    static let asterionSynopsis = Color(red: 0.627, green: 0.596, blue: 0.533)
}

// MARK: - Font Helpers

extension Font {
    static func asterionSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func asterionMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
