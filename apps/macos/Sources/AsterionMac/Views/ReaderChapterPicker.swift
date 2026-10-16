import SwiftUI

struct ReaderChapterPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let chapters: [Chapter]
    let selectedIndex: Int
    let palette: ReaderPalette
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchIsFocused: Bool

    private var filteredChapters: [IndexedChapter] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let indexed = chapters.enumerated().map { IndexedChapter(index: $0.offset, chapter: $0.element) }
        guard !search.isEmpty else { return indexed }
        return indexed.filter {
            String($0.chapter.chapterNumber).localizedCaseInsensitiveContains(search)
                || $0.chapter.displayTitle.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Chapters")
                        .font(.asterionTitle(16, weight: .bold))
                        .foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(chapters.count.formatted())
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(palette.faint)
                        .accessibilityLabel("\(chapters.count) chapters")
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.muted)
                            .frame(width: 24, height: 24)
                            .background(palette.text.opacity(0.06), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close chapters")
                    .accessibilityLabel("Close chapters")
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.muted)
                    TextField("Find a chapter", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.text)
                        .focused($searchIsFocused)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.faint)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    Capsule()
                        .fill(palette.text.opacity(0.05))
                    Capsule()
                        .strokeBorder(palette.border, lineWidth: 1)
                }
            }
            .padding(16)

            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5)

            ScrollViewReader { proxy in
                Group {
                    if filteredChapters.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(palette.faint)
                            Text("No chapters found")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("Try a chapter number or title.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.muted)
                        }
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(filteredChapters) { item in
                                    chapterRow(item)
                                        .id(item.index)
                                }
                            }
                            .padding(8)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .onAppear {
                    scrollToSelection(using: proxy)
                    searchIsFocused = true
                }
                .onChange(of: selectedIndex) {
                    scrollToSelection(using: proxy)
                }
                .onChange(of: query) {
                    guard query.isEmpty else { return }
                    scrollToSelection(using: proxy)
                }
            }
        }
        .background(palette.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.border)
                .frame(width: 0.5)
        }
    }

    private func chapterRow(_ item: IndexedChapter) -> some View {
        let isSelected = item.index == selectedIndex

        return Button {
            onSelect(item.index)
        } label: {
            ReaderChapterRowLabel(
                number: String(item.chapter.chapterNumber),
                title: item.chapter.displayTitle,
                isSelected: isSelected,
                palette: palette
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter \(item.chapter.chapterNumber), \(item.chapter.displayTitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            guard hovering else { return }
            model.prefetchChapter(id: item.chapter.id)
        }
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            if reduceMotion {
                proxy.scrollTo(selectedIndex, anchor: .center)
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
            }
        }
    }
}

private struct IndexedChapter: Identifiable {
    let index: Int
    let chapter: Chapter

    var id: String { chapter.id }
}

private struct ReaderChapterRowLabel: View {
    let number: String
    let title: String
    let isSelected: Bool
    let palette: ReaderPalette

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.asterionMono(11, weight: .medium))
                .foregroundStyle(isSelected ? palette.text : palette.faint)
                .frame(width: 42, alignment: .trailing)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.text : palette.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Circle()
                    .fill(palette.text)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.text.opacity(isSelected ? 0.10 : (isHovering ? 0.05 : 0)))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
