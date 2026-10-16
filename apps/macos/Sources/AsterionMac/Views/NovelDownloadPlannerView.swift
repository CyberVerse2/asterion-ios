import SwiftUI

/// The novel page's "Download chapters" sheet: presets from the chapter being
/// read, a typed range, and what is already on this Mac. Shares the episode
/// planner's header, chip group and footer.
struct NovelDownloadPlannerView: View {
    @Environment(\.dismiss) private var dismiss

    let novelTitle: String
    let totalChapters: Int
    let currentChapter: Int?
    let saved: OfflineChapterSet
    /// Downloads a range of chapter numbers, or the whole novel for nil.
    let onDownload: (ClosedRange<Int>?) -> Void
    /// Removes every downloaded chapter; nil when none are downloaded.
    let onRemove: (() -> Void)?

    private enum Choice: Hashable {
        case preset(NovelDownloadRange.Preset)
        case custom
    }

    @State private var choice: Choice
    @State private var fromText: String
    @State private var toText: String

    init(
        novelTitle: String,
        totalChapters: Int,
        currentChapter: Int?,
        saved: OfflineChapterSet,
        onDownload: @escaping (ClosedRange<Int>?) -> Void,
        onRemove: (() -> Void)?
    ) {
        self.novelTitle = novelTitle
        self.totalChapters = totalChapters
        self.currentChapter = currentChapter
        self.saved = saved
        self.onDownload = onDownload
        self.onRemove = onRemove

        let preset: NovelDownloadRange.Preset = currentChapter.map { $0 > 1 } == true ? .next50 : .all
        let range = NovelDownloadRange.range(
            for: preset,
            currentChapter: currentChapter,
            totalChapters: totalChapters
        )
        _choice = State(initialValue: .preset(preset))
        _fromText = State(initialValue: range.map { String($0.lowerBound) } ?? "")
        _toText = State(initialValue: range.map { String($0.upperBound) } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.asterionHairline).frame(height: 1)
            rangeEditor
            Rectangle().fill(Color.asterionHairline).frame(height: 1)
            footer
        }
        .frame(minWidth: 520, idealWidth: 560)
        .background(Color.asterionMediaCanvas)
    }

    // MARK: Range

    private var selectedRange: ClosedRange<Int>? {
        switch choice {
        case .preset(let preset):
            NovelDownloadRange.range(for: preset, currentChapter: currentChapter, totalChapters: totalChapters)
        case .custom:
            Int(fromText).flatMap { from in
                Int(toText).flatMap { to in
                    NovelDownloadRange.custom(from: from, to: to, totalChapters: totalChapters)
                }
            }
        }
    }

    /// The range handed to the download: nil means the whole novel, so
    /// chapters released later count as missing from it.
    private var requestedRange: ClosedRange<Int>? {
        choice == .preset(.all) ? nil : selectedRange
    }

    private var missingCount: Int {
        guard let range = selectedRange else { return 0 }
        return max(0, range.count - saved.count(in: range))
    }

    private func select(_ preset: NovelDownloadRange.Preset) {
        choice = .preset(preset)
        if let range = NovelDownloadRange.range(
            for: preset,
            currentChapter: currentChapter,
            totalChapters: totalChapters
        ) {
            fromText = String(range.lowerBound)
            toText = String(range.upperBound)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Download chapters")
                    .font(.asterionTitle(20, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                Text(novelTitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }

            Spacer()

            if !saved.isEmpty {
                Label {
                    Text(verbatim: saved.summary + " on this Mac")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.asterionSuccess)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var rangeEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 4) {
                ForEach(NovelDownloadRange.Preset.allCases) { preset in
                    RangeChip(title: preset.title, isSelected: choice == .preset(preset)) {
                        select(preset)
                    }
                }
                RangeChip(title: "Custom", isSelected: choice == .custom) {
                    choice = .custom
                }
            }
            .padding(3)
            .background(Color.asterionSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.asterionBorder))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Chapters to download")

            HStack(spacing: 10) {
                Text("From")
                    .foregroundStyle(Color.asterionMuted)
                chapterField("First chapter", text: $fromText)
                Text("to")
                    .foregroundStyle(Color.asterionMuted)
                chapterField("Last chapter", text: $toText)
                Text(verbatim: "of " + String(totalChapters))
                    .font(.asterionMono(12, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
            }
            .font(.system(size: 13))

            Text(rangeSummary)
                .font(.system(size: 12.5))
                .foregroundStyle(selectedRange == nil ? Color.asterionWarning : Color.asterionMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chapterField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: Binding(
            get: { text.wrappedValue },
            set: { newValue in
                text.wrappedValue = newValue.filter(\.isNumber)
                choice = .custom
            }
        ))
        .textFieldStyle(.plain)
        .font(.asterionMono(13, weight: .medium))
        .multilineTextAlignment(.center)
        .frame(width: 72, height: 30)
        .background(Color.asterionSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.asterionBorder))
        .accessibilityLabel(label)
    }

    /// "Chapters 50–99 · 50 chapters · 12 already downloaded".
    private var rangeSummary: String {
        guard let range = selectedRange else {
            return "Enter chapters between 1 and " + String(totalChapters) + "."
        }
        var parts = [
            range.count == 1
                ? "Chapter " + String(range.lowerBound)
                : "Chapters " + String(range.lowerBound) + "–" + String(range.upperBound),
            range.count == 1 ? "1 chapter" : String(range.count) + " chapters",
        ]
        let alreadySaved = range.count - missingCount
        if alreadySaved > 0 {
            parts.append(String(alreadySaved) + " already downloaded")
        }
        if case .preset(let preset) = choice, preset != .all, currentChapter == nil {
            parts.append("from the first chapter")
        }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let onRemove {
                Button(role: .destructive) {
                    onRemove()
                    dismiss()
                } label: {
                    Label("Remove downloads", systemImage: "trash")
                }
                .buttonStyle(.asterionSecondary)
                .help("Remove every downloaded chapter of this novel")
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.asterionSecondary)
                .keyboardShortcut(.cancelAction)

            Button {
                onDownload(requestedRange)
                dismiss()
            } label: {
                Label(downloadButtonTitle, systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.asterionPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedRange == nil || missingCount == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.asterionSurface.opacity(0.5))
    }

    private var downloadButtonTitle: String {
        guard selectedRange != nil else { return "Download" }
        switch missingCount {
        case 0: return "Already downloaded"
        case 1: return "Download 1 chapter"
        default: return "Download " + String(missingCount) + " chapters"
        }
    }
}

private struct RangeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.asterionMediaCanvas : Color.asterionMuted)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(isSelected ? Color.asterionText : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
