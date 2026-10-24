import XCTest
@testable import NexusCore

final class ClipboardStoreTests: XCTestCase {
    var store: ClipboardStore!
    var path: String!

    override func setUp() {
        path = NSTemporaryDirectory() + "nexus-test-\(UUID().uuidString).db"
        store = ClipboardStore(path: path)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: path) }

    func text(_ s: String) -> ClipDraft { ClipDraft(kind: .text, text: s, hash: ClipDraft.hash(Data(s.utf8))) }
    func image(_ n: String) -> ClipDraft { ClipDraft(kind: .image, text: "", hash: "img-\(n)", imagePath: "/tmp/\(n).png") }
    let day: TimeInterval = 86_400

    func testDedupeBumpsToTop() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        store.insert(text("a"), now: t0)
        store.insert(text("b"), now: t0 + 10)
        store.insert(text("a"), now: t0 + 20)
        XCTAssertEqual(store.fetch().map(\.text), ["a", "b"])
    }

    func testFilterAndSearch() {
        store.insert(text("hello world"))
        store.insert(image("x"))
        store.insert(text("100% sure"))
        XCTAssertEqual(store.fetch(query: "hello").count, 1)
        XCTAssertEqual(store.fetch(query: "%").map(\.text), ["100% sure"]) // wildcard is escaped
        XCTAssertEqual(store.fetch(kind: .image).count, 1)
    }

    func testLongTextIsTruncatedInListButPasteableInFull() {
        let big = String(repeating: "x", count: 50_000)
        var d = text(big); d.chars = big.count; d.words = 1
        let id = store.insert(d)
        let c = store.fetch().first!
        XCTAssertEqual(c.text.count, ClipboardStore.previewLimit)
        XCTAssertEqual(c.chars, 50_000)
        XCTAssertTrue(c.isTruncated)
        XCTAssertEqual(store.fullText(id)?.count, 50_000)
        XCTAssertEqual(store.fetch(query: "xxx").count, 1) // search still covers the full text
    }

    func testDeleteByHash() {
        store.insert(text("secret-pw"))
        store.insert(text("keep"))
        store.delete(hash: ClipDraft.hash(Data("secret-pw".utf8)))
        XCTAssertEqual(store.fetch().map(\.text), ["keep"])
    }

    func testRichRoundTrip() {
        var d = text("rich"); d.rtf = Data([1, 2, 3]); d.html = Data("<b>x</b>".utf8)
        let id = store.insert(d)
        XCTAssertEqual(store.rich(id).rtf, Data([1, 2, 3]))
        XCTAssertEqual(store.rich(id).html, Data("<b>x</b>".utf8))
    }

    func testRetentionSplitsTextAndImages() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        store.insert(text("old text"), now: now - 200 * day)
        store.insert(text("year-old text"), now: now - 400 * day)
        store.insert(image("old"), now: now - 40 * day)
        store.insert(image("new"), now: now - 5 * day)
        let pinnedID = store.insert(text("pinned old"), now: now - 900 * day)
        store.setPinned(pinnedID, true)

        let paths = store.purge(textBefore: now - 365 * day, imagesBefore: now - 30 * day)
        XCTAssertEqual(paths, ["/tmp/old.png"])
        let left = store.fetch().map { $0.text.isEmpty ? $0.imagePath! : $0.text }
        XCTAssertEqual(Set(left), ["pinned old", "old text", "/tmp/new.png"])
    }

    func testNilCutoffKeepsForever() {
        let now = Date()
        store.insert(text("ancient"), now: now - 5000 * day)
        XCTAssertTrue(store.purge(textBefore: nil, imagesBefore: nil).isEmpty)
        XCTAssertEqual(store.fetch().count, 1)
    }

    func testPinnedSortsFirstAndClearKeepsPinned() {
        let a = store.insert(text("a"), now: Date(timeIntervalSince1970: 1))
        store.insert(text("b"), now: Date(timeIntervalSince1970: 2))
        store.setPinned(a, true)
        XCTAssertEqual(store.fetch().first?.text, "a")
        _ = store.clear()
        XCTAssertEqual(store.fetch().map(\.text), ["a"])
    }
}

final class RecentTextsTests: XCTestCase {
    func testNewestFirstIgnoresPinningAndImages() {
        let path = NSTemporaryDirectory() + "nexus-recent-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let s = ClipboardStore(path: path)
        func draft(_ t: String, kind: ClipKind = .text) -> ClipDraft { ClipDraft(kind: kind, text: t, hash: ClipDraft.hash(Data(t.utf8))) }
        let old = s.insert(draft("old"), now: Date(timeIntervalSince1970: 1))
        s.insert(draft("img", kind: .image), now: Date(timeIntervalSince1970: 2))
        s.insert(draft("https://x.dev", kind: .url), now: Date(timeIntervalSince1970: 3))
        s.insert(draft("new"), now: Date(timeIntervalSince1970: 4))
        s.setPinned(old, true) // pinned items sort first in `fetch`, but not here
        XCTAssertEqual(s.recentTexts(limit: 2), ["new", "https://x.dev"])
        XCTAssertEqual(s.recentTexts(limit: 10), ["new", "https://x.dev", "old"])
    }
}
