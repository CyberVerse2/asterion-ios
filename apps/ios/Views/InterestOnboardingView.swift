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
                VStack(alignment: .leading, spacing: 34) {
                    introduction
                    contentTypePicker
                    genrePicker
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                continueButton
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(
                            colors: [Color.asterionBackground.opacity(0), Color.asterionBackground],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .ignoresSafeArea()
                    }
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: restoreSelections)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionEyebrow(text: "Welcome to Asterion")

            Text("Make it yours")
                .font(.asterionTitle(30, weight: .heavy))
                .foregroundStyle(Color.asterionText)
                .accessibilityAddTraits(.isHeader)

            Text("Choose what you enjoy. We\u{2019}ll use it to shape Home, and you can change this later.")
                .font(.asterionReading(15))
                .foregroundStyle(Color.asterionMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contentTypePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("What are you here for?")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(contentTypes) { option in
                    let selected = selectedContentTypes.contains(option.title)
                    Button {
                        toggle(option.title, in: &selectedContentTypes)
                    } label: {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 20, weight: .medium))
                                Spacer(minLength: 0)
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17, weight: .medium))
                                    .opacity(selected ? 1 : 0.35)
                            }
                            Text(option.title)
                                .font(.asterionReading(15, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(selected ? Color.asterionOnInk : Color.asterionText)
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selected ? Color.asterionInk : Color.white.opacity(0.05))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(selected ? 0 : 0.08))
                        }
                        .shadow(color: .white.opacity(selected ? 0.12 : 0), radius: 14)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .animation(.easeOut(duration: 0.18), value: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var genrePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Pick a few genres")

            FlowLayout(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    let selected = selectedGenres.contains(genre)
                    Button {
                        toggle(genre, in: &selectedGenres)
                    } label: {
                        Text(genre)
                            .font(.asterionReading(14, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .asterionGlassPill(isSelected: selected)
                            .contentShape(Capsule())
                            .animation(.easeOut(duration: 0.18), value: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
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
                    .font(.asterionReading(16, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
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
