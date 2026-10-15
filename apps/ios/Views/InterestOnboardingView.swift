import SwiftUI

struct InterestOnboardingView: View {
    let completion: () -> Void

    @AppStorage("asterion.onboarding.genres") private var savedGenres = ""
    @AppStorage("asterion.onboarding.contentTypes") private var savedContentTypes = ""
    @State private var selectedGenres: Set<String> = []
    @State private var selectedContentTypes: Set<String> = ["Novels"]

    private let contentTypes = [
        InterestOption(title: "Novels", symbol: "book.closed"),
        InterestOption(title: "Anime", symbol: "play.tv"),
        InterestOption(title: "Movies & TV", symbol: "film"),
        InterestOption(title: "Football", symbol: "soccerball"),
    ]

    private let genres = [
        "Fantasy", "Action", "Romance", "Mystery", "Adventure",
        "Drama", "Comedy", "Sci-Fi", "Thriller", "Historical",
    ]

    var body: some View {
        ZStack {
            AsterionBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    introduction
                    contentTypePicker
                    genrePicker
                    continueButton
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: restoreSelections)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AsterionMark(size: 18)
                Text("Asterion")
                    .font(.asterionDisplay(20, weight: .medium))
                    .foregroundStyle(Color.asterionText)
            }

            Text("Make it yours")
                .font(.asterionDisplay(36, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .tracking(-0.5)

            Text("Choose what you enjoy. We’ll use it to shape Home, and you can change this later.")
                .font(.asterionReading(17))
                .foregroundStyle(Color.asterionSynopsis)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contentTypePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("What are you here for?")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 12)], spacing: 12) {
                ForEach(contentTypes) { option in
                    Button {
                        toggle(option.title, in: &selectedContentTypes)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol)
                            Text(option.title)
                                .font(.asterionReading(16, weight: .semibold))
                            Spacer(minLength: 0)
                            if selectedContentTypes.contains(option.title) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.asterionOnInk)
                            }
                        }
                        .foregroundStyle(
                            selectedContentTypes.contains(option.title)
                                ? Color.asterionOnInk
                                : Color.asterionText
                        )
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            selectedContentTypes.contains(option.title)
                                ? Color.asterionInk
                                : Color.asterionCard,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedContentTypes.contains(option.title) ? .isSelected : [])
                }
            }
        }
    }

    private var genrePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Pick a few genres")

            FlowLayout(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Button {
                        toggle(genre, in: &selectedGenres)
                    } label: {
                        Text(genre)
                            .font(.asterionReading(14, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .asterionGlassPill(isSelected: selectedGenres.contains(genre))
                    .accessibilityAddTraits(selectedGenres.contains(genre) ? .isSelected : [])
                }
            }
        }
    }

    private var continueButton: some View {
        Button {
            saveAndContinue()
        } label: {
            HStack {
                Text("Continue")
                    .font(.asterionReading(17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(AsterionFilledButtonStyle())
        .accessibilityHint("Saves your interests and opens Home")
    }

    private func sectionLabel(_ title: String) -> some View {
        AsterionSectionLabel(title: title)
    }

    private func toggle(_ value: String, in selection: inout Set<String>) {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }

    private func restoreSelections() {
        let content = Self.decode(savedContentTypes)
        let genres = Self.decode(savedGenres)
        if !content.isEmpty { selectedContentTypes = content }
        if !genres.isEmpty { selectedGenres = genres }
    }

    private func saveAndContinue() {
        savedContentTypes = selectedContentTypes.sorted().joined(separator: ",")
        savedGenres = selectedGenres.sorted().joined(separator: ",")
        completion()
    }

    private static func decode(_ rawValue: String) -> Set<String> {
        Set(
            rawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

private struct InterestOption: Identifiable {
    let title: String
    let symbol: String
    var id: String { title }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: proposal.width ?? cursor.x, height: cursor.y + rowHeight), points)
    }
}
