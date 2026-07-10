import SwiftUI

struct ReaderChapterPicker: View {
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Spacer()
                    Text(chapters.count.formatted())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.faint)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Close chapters")
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
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.text.opacity(0.055))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.border, lineWidth: 0.75)
                }
            }
            .padding(16)

            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5)

            ScrollViewReader { proxy in
                Group {
                    if filteredChapters.isEmpty {
                        ContentUnavailableView {
                            Label("No chapters found", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try a chapter number or title.")
                        }
                        .foregroundStyle(palette.muted)
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
            HStack(spacing: 12) {
                Text(item.chapter.chapterNumber.formatted())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? palette.text : palette.faint)
                    .frame(width: 42, alignment: .trailing)

                Text(item.chapter.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? palette.text : palette.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "book.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.text.opacity(0.10) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(selectedIndex, anchor: .center)
            }
        }
    }
}

private struct IndexedChapter: Identifiable {
    let index: Int
    let chapter: Chapter

    var id: String { chapter.id }
}
