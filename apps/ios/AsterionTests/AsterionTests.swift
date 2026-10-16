//
//  AsterionTests.swift
//  AsterionTests
//
//  Created by Celestine Ejiofor on 02/03/2026.
//
//  App-hosted tests for services that need the app target (UIKit, Network,
//  the app-group snapshot store). Pure logic is tested in AsterionKit with
//  `swift test`.
//

import AsterionKit
import Foundation
import Testing
@testable import Asterion

@MainActor
struct AsterionTests {
    @Test
    func downloadAheadPruningKeepsManualChaptersAndUnreadOnes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineChapterStore(baseDirectory: root.appendingPathComponent("cache"),
                                        documentsDirectory: root.appendingPathComponent("documents"))
        let book = novel(id: "book")
        for (number, automatic) in [(1, false), (2, true), (3, true), (4, true)] {
            let chapter = Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)",
                                  content: "Body \(number)", url: nil)
            _ = try await store.saveDownloadedChapter(
                novelTitle: book.title, chapterNumber: number, chapterTitle: chapter.title,
                content: "\(book.title)\nChapter \(number)\n\nBody \(number)",
                novel: book, chapter: chapter, automatic: automatic
            )
        }

        let removed = await store.pruneDownloadedAheadChapters(novel: book, readingChapterNumber: 3)

        #expect(removed == 1)
        let collection = try #require(await store.downloadedCollections().first)
        #expect(collection.chapters.map(\.id) == ["c1", "c3", "c4"])
        #expect(collection.downloadedAheadCount == 2)
    }

    @Test
    func bulkDownloadKeepsEveryChapterInTheManifestOnceFlushed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let documents = root.appendingPathComponent("documents")
        let store = OfflineChapterStore(baseDirectory: cache, documentsDirectory: documents)
        let book = novel(id: "book")
        for number in 1...300 {
            let chapter = Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)",
                                  content: nil, url: nil)
            _ = try await store.saveDownloadedChapter(
                novelTitle: book.title, chapterNumber: number, chapterTitle: chapter.title,
                content: "\(book.title)\nChapter \(number)\n\nBody \(number)",
                novel: book, chapter: chapter, automatic: true
            )
        }
        // Saving a downloaded-ahead chapter yourself keeps it from being pruned.
        let first = Chapter(id: "c1", chapterNumber: 1, title: "Chapter 1", content: nil, url: nil)
        _ = try await store.saveDownloadedChapter(
            novelTitle: book.title, chapterNumber: 1, chapterTitle: first.title,
            content: "\(book.title)\nChapter 1\n\nBody 1", novel: book, chapter: first
        )
        await store.flushDownloadedManifests()

        // A fresh store reads only what reached disk.
        let reopened = OfflineChapterStore(baseDirectory: cache, documentsDirectory: documents)
        let collection = try #require(await reopened.downloadedCollections().first)
        #expect(collection.novel.id == "book")
        #expect(collection.chapters.map(\.id) == (1...300).map { "c\($0)" })
        #expect(collection.downloadedAheadCount == 299)

        #expect(await reopened.pruneDownloadedAheadChapters(novel: book, readingChapterNumber: 11) == 9)
        let pruned = try #require(await reopened.downloadedCollections().first)
        #expect(pruned.chapterCount == 291)
        #expect(pruned.chapters.first?.id == "c1")
    }

    @Test
    func localReadingCountsBeforeSyncedProgressArrives() throws {
        // Cold launch: the session token has not reached the API, so the
        // remote list is empty. The novel read last on this device must
        // still be offered to Continue.
        let suite = "asterion.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingProgressService(defaults: defaults)
        service.updateProgress(novelId: "novel", chapterId: "c12", currentLine: 5, totalLines: 40, syncToCloud: false)

        let relaunched = ReadingProgressService(defaults: defaults)
        let merged = relaunched.mergedProgress(with: [])
        #expect(merged.map(\.novelId) == ["novel"])
        #expect(merged.first?.chapterId == "c12")
    }

    @Test
    func removingDownloadsDeletesTheChapterFilesAndThenTheNovelsFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let documents = root.appendingPathComponent("documents")
        let store = OfflineChapterStore(baseDirectory: cache, documentsDirectory: documents)
        let book = novel(id: "book")
        for number in 1...3 {
            let chapter = Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)",
                                  content: nil, url: nil)
            _ = try await store.saveDownloadedChapter(
                novelTitle: book.title, chapterNumber: number, chapterTitle: chapter.title,
                content: "\(book.title)\nChapter \(number)\n\nBody \(number)", novel: book, chapter: chapter
            )
        }
        let collection = try #require(await store.downloadedCollections().first)

        // Swiping one chapter away leaves the others, and the manifest agrees after a relaunch.
        let swiped = try #require(collection.chapters.first { $0.id == "c2" })
        let remaining = try #require(await store.removeDownloadedChapters([swiped], from: collection))
        #expect(remaining.chapters.map(\.id) == ["c1", "c3"])
        await store.flushDownloadedManifests()
        let reopened = OfflineChapterStore(baseDirectory: cache, documentsDirectory: documents)
        let afterSwipe = try #require(await reopened.downloadedCollections().first)
        #expect(afterSwipe.chapters.map(\.id) == ["c1", "c3"])
        #expect(await reopened.downloadedChapterCount(novelTitle: book.title) == 2)

        // Removing the novel takes its folder, manifest included.
        await reopened.removeDownloadedNovel(afterSwipe)
        #expect(await reopened.downloadedCollections().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: afterSwipe.folderURL.path))
    }

    @Test
    func aGuestsSavedNovelsMoveIntoTheAccountAtSignIn() async throws {
        let suite = "asterion.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = NovelLibraryService(defaults: defaults)
        #expect(library.toggle(novel(id: "saved-as-guest")))

        await library.handleAuthenticationChange(userID: "user-1")
        #expect(library.contains("saved-as-guest"))
        #expect(library.ledger.pending.contains { $0.novelId == "saved-as-guest" && $0.kind == .add })

        // Signed out, the guest shelf starts empty again; the account keeps its copy.
        await library.handleAuthenticationChange(userID: nil)
        #expect(!library.contains("saved-as-guest"))
        let relaunched = NovelLibraryService(defaults: defaults)
        await relaunched.handleAuthenticationChange(userID: "user-1")
        #expect(relaunched.contains("saved-as-guest"))
    }

    private func novel(id: String) -> Novel {
        Novel(id: id, title: id, author: nil, rank: nil, totalChapters: nil, views: nil, bookmarks: nil,
              status: nil, genres: [], summary: nil, imageUrl: nil, rating: 4)
    }
}
