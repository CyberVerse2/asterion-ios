import Inject
import SwiftUI

struct ReaderView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss

    let initialChapter: Chapter
    let novel: Novel
    let allChapters: [Chapter]

    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var fontSize: CGFloat = 19
    @State private var controlTimer: Task<Void, Never>?
    @State private var loadingChapter = false
    @State private var scrollProxy: ScrollViewProxy?

    private var genreColor: Color { GenreStyle.color(for: novel.genres) }

    private var currentIndex: Int {
        allChapters.firstIndex(where: { $0.id == currentChapter.id }) ?? -1
    }
    private var hasPrev: Bool { currentIndex > 0 }
    private var hasNext: Bool { currentIndex >= 0 && currentIndex < allChapters.count - 1 }

    private var paragraphs: [String] {
        currentChapter.plainContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    init(initialChapter: Chapter, novel: Novel, allChapters: [Chapter]) {
        self.initialChapter = initialChapter
        self.novel = novel
        self.allChapters = allChapters
        self._currentChapter = State(initialValue: initialChapter)
    }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        chapterHeading
                            .id("top")
                        chapterContent
                        endOfChapterNav
                    }
                }
                .onAppear { scrollProxy = proxy }
                .simultaneousGesture(
                    TapGesture().onEnded { toggleControls() }
                )
                .overlay(alignment: .top) {
                    topControlBar
                }
                .overlay(alignment: .bottom) {
                    bottomControlBar
                }
            }

            if loadingChapter {
                Color.asterionBackground.opacity(0.85).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().tint(Color.goldAccent)
                    Text("Loading chapter...")
                        .font(.asterionMono(12))
                        .foregroundStyle(Color.asterionDim)
                }
            }
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .statusBarHidden(!showControls)
        .onAppear {
            tabBarState.isVisible = false
            scheduleHideControls()
        }
        .onChange(of: currentChapter.id) { _, _ in
            withAnimation {
                scrollProxy?.scrollTo("top", anchor: .top)
            }
        }
        .enableInjection()
    }

    // MARK: - Chapter Heading

    private var chapterHeading: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 80)

            if currentChapter.chapterNumber > 0 {
                Text("CHAPTER \(currentChapter.chapterNumber)")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionBorderHover)
                    .tracking(4)
            }

            Text(currentChapter.title)
                .font(.asterionSerif(22, weight: .light))
                .foregroundStyle(Color.asterionMuted)
                .italic()
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Rectangle()
                .fill(Color.asterionBorder)
                .frame(width: 40, height: 1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 10)
    }

    // MARK: - Chapter Content

    private var chapterContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, para in
                Text(para)
                    .font(.asterionSerif(fontSize))
                    .lineSpacing(fontSize * 0.85)
                    .foregroundStyle(Color.asterionReaderText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, index > 0 ? 32 : 0)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 140)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    // MARK: - End of Chapter Nav

    private var endOfChapterNav: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.asterionCard).frame(height: 1)
                .padding(.horizontal, 32)

            HStack(spacing: 16) {
                if hasPrev {
                    Button {
                        navigateChapter(direction: -1)
                    } label: {
                        Text("← Previous")
                            .font(.asterionSerif(14))
                            .foregroundStyle(Color.asterionMuted)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.asterionBorder, lineWidth: 1)
                            )
                    }
                }

                if hasNext {
                    Button {
                        navigateChapter(direction: 1)
                    } label: {
                        Text("Next Chapter →")
                            .font(.asterionSerif(14))
                            .foregroundStyle(Color.goldAccent)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(genreColor.opacity(0.1))
                                    .stroke(genreColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("← Back")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }

            Spacer()

            Text(novel.title)
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionDim)
                .lineLimit(1)
                .frame(maxWidth: 160)

            Spacer()

            HStack(spacing: 8) {
                Button { fontSize = max(14, fontSize - 1) } label: {
                    Text("A-")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
                Button { fontSize = min(28, fontSize + 1) } label: {
                    Text("A+")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.asterionBackground, Color.asterionBackground, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Bottom Control Bar

    private var bottomControlBar: some View {
        HStack(spacing: 24) {
            if hasPrev {
                Button { navigateChapter(direction: -1) } label: {
                    Text("◂ Prev")
                        .font(.asterionMono(12))
                        .foregroundStyle(Color.asterionMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule().stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
            if hasNext {
                Button { navigateChapter(direction: 1) } label: {
                    Text("Next ▸")
                        .font(.asterionMono(12))
                        .foregroundStyle(Color.goldAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule().stroke(genreColor.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.bottom, 34)
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, Color.asterionBackground, Color.asterionBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Actions

    private func toggleControls() {
        showControls.toggle()
        if showControls { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        controlTimer?.cancel()
        controlTimer = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    private func navigateChapter(direction: Int) {
        let nextIdx = currentIndex + direction
        guard nextIdx >= 0 && nextIdx < allChapters.count else { return }
        let target = allChapters[nextIdx]

        loadingChapter = true
        Task {
            defer { loadingChapter = false }
            do {
                let full = try await apiClient.fetchChapter(id: target.id)
                currentChapter = full
            } catch {
                currentChapter = target
            }
            scheduleHideControls()
        }
    }
}
