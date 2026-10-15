import SwiftUI

struct AsterionDetailStat: Identifiable, Hashable {
    let label: String
    let value: String
    let symbol: String
    var id: String { label }

    init(label: String, value: String, symbol: String? = nil) {
        self.label = label
        self.value = value
        self.symbol = symbol ?? Self.symbol(for: label)
    }

    private static func symbol(for label: String) -> String {
        switch label.lowercased() {
        case "rank": "trophy"
        case "rating", "score", "imdb": "star.fill"
        case "chapters": "book.closed"
        case "episodes": "rectangle.stack"
        case "status": "checkmark.circle"
        case "views": "eye"
        case "type", "kind": "sparkles.tv"
        case "year": "calendar"
        case "runtime": "clock"
        default: "circle"
        }
    }
}

struct AsterionDetailHero<Poster: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var poster: () -> Poster

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            poster()
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.asterionDisplay(28, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.asterionReading(15))
                        .foregroundStyle(Color.asterionSynopsis)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 72)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AsterionCoverBleed: View {
    let url: URL?
    var height: CGFloat = 420

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.2)
                    .blur(radius: 26)
                    .saturation(1.05)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0),
                    .init(color: .black.opacity(0.35), location: 0.42),
                    .init(color: .clear, location: 0.78),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AsterionDetailPoster: View {
    let url: URL?
    var width: CGFloat = 132
    var height: CGFloat = 198

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Color.asterionCard
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(Color.asterionMuted)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AsterionDetailStatsRow: View {
    let items: [AsterionDetailStat]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(visibleItems) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.asterionReading(12))
                        .foregroundStyle(Color.asterionMuted)
                    Text(displayValue(for: item))
                        .font(.asterionDisplay(20, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private var visibleItems: [AsterionDetailStat] {
        Array(items.filter { $0.label != "Views" }.prefix(3))
    }

    private func displayValue(for item: AsterionDetailStat) -> String {
        let value = item.value.replacingOccurrences(of: "★ ", with: "")
        if item.label == "Status" {
            switch value.lowercased() {
            case "finished airing", "completed": return "Finished"
            case "currently airing", "ongoing": return "Ongoing"
            default: return value
            }
        }
        return value
    }
}

struct AsterionChipRow: View {
    let chips: [String]
    var tint: Color = Color.asterionMuted

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.prefix(3)), id: \.self) { chip in
                    Text(chip)
                        .font(.asterionReading(13, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.asterionCard, in: Capsule())
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
    }
}

struct AsterionSynopsisBlock: View {
    let text: String
    var genres: [String] = []
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !genres.isEmpty {
                Text(genres.prefix(3).joined(separator: "  ·  "))
                    .font(.asterionReading(13))
                    .foregroundStyle(Color.asterionMuted)
            }
            Text(cleaned)
                .font(.asterionReading(16))
                .foregroundStyle(Color.asterionSynopsis)
                .lineSpacing(6)
                .lineLimit(expanded ? nil : 5)
            if cleaned.count > 180 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Read more")
                        .font(.asterionReading(15, weight: .medium))
                        .foregroundStyle(Color.asterionInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var cleaned: String {
        text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: #"\.(\S)"#, with: ". $1", options: .regularExpression)
    }
}

struct AsterionPrimaryActionLabel: View {
    let title: String
    var tint: Color = Color.asterionInk

    var body: some View {
        Text(title)
            .font(.asterionReading(16, weight: .semibold))
            .foregroundStyle(Color.asterionOnInk)
            .lineLimit(1)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .fixedSize(horizontal: true, vertical: false)
            .background(tint, in: Capsule())
    }
}

struct AsterionCircleIconButton: View {
    let systemName: String
    var isBusy: Bool = false
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .tint(Color.asterionInk)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.asterionInk)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.asterionCard, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct MediaMassDownloadButton: View {
    let isComplete: Bool
    var isBusy: Bool = false
    var progress: CGFloat = 0
    var accessibilityLabel: String = "Download all"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    Circle()
                        .trim(from: 0, to: max(progress, 0.06))
                        .stroke(
                            Color.asterionInk,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 40, height: 40)
                }

                Image(systemName: isComplete ? "checkmark" : "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isComplete
                            ? Color(red: 0.353, green: 0.608, blue: 0.478)
                            : Color.asterionInk
                    )
            }
            .frame(width: 48, height: 48)
            .background(Color.asterionCard, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || isComplete)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AsterionEpisodeCard: View {
    let number: Int
    let title: String
    let subtitle: String
    let imageURL: URL?
    var isBusy: Bool = false
    var downloadProgress: Double? = nil
    var isDownloaded: Bool = false
    let onPlay: () -> Void
    let onDownload: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.asterionCardHover
                        }
                    }
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.52),
                            .init(color: Color.asterionBackground.opacity(0.88), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .topLeading) {
                    Text("\(number)")
                        .font(.asterionReading(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.asterionReading(17, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(1)
                        Text(isBusy ? "Opening…" : subtitle)
                            .font(.asterionReading(14))
                            .foregroundStyle(Color.asterionMuted)
                            .lineLimit(1)
                    }
                    .padding(12)
                    .padding(.trailing, 52)
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture {
                    guard !isBusy else { return }
                    onPlay()
                }

            downloadControl
                .padding(10)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var downloadControl: some View {
        Button {
            onDownload()
        } label: {
            ZStack {
                if let downloadProgress {
                    ProgressView(value: downloadProgress)
                        .tint(Color.asterionInk)
                } else {
                    Image(systemName: isDownloaded ? "checkmark" : "arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.asterionInk)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.asterionCard, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isDownloaded || downloadProgress != nil)
        .accessibilityLabel(isDownloaded ? "Downloaded" : "Download episode \(number)")
    }
}

struct AsterionFilterPills: View {
    let titles: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    private var fillsRow: Bool { titles.count > 1 && titles.count <= 3 }

    var body: some View {
        Group {
            if fillsRow {
                HStack(spacing: 8) { pills }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { pills }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var pills: some View {
        ForEach(titles.indices, id: \.self) { index in
            Button {
                onSelect(index)
            } label: {
                Text(titles[index])
                    .font(.asterionReading(14, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: fillsRow ? .infinity : nil)
            }
            .buttonStyle(.plain)
            .asterionGlassPill(isSelected: selectedIndex == index)
        }
    }
}

struct AsterionEpisodeShelf<Item: Identifiable, Card: View>: View {
    var title: String? = "Episodes"
    let items: [Item]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder var card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                AsterionSectionLabel(title: title)
                    .padding(.horizontal, 24)
            }

            LazyVGrid(
                columns: AsterionLayout.episodeColumns(horizontalSizeClass),
                spacing: 16
            ) {
                ForEach(items) { item in
                    card(item)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 10)
    }
}

struct AsterionUnitGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionSectionLabel(title: title)
            VStack(spacing: 0) {
                content()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}

struct AsterionUnitRow: View {
    var index: String? = nil
    let title: String
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let index {
                Text(index)
                    .font(.asterionReading(13, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                    .frame(width: 36, alignment: .leading)
            }

            Text(title)
                .font(.asterionReading(16, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)

            Spacer(minLength: 8)

            if isBusy {
                ProgressView().tint(Color.asterionInk).scaleEffect(0.8)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

struct AsterionDetailBar<Trailing: View>: View {
    let onBack: () -> Void
    var topPadding: CGFloat = 44
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .frame(width: 36, height: 36)
                    .background(Color.asterionCard, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
            trailing()
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 20)
    }
}
