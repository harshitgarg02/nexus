import XCTest
@testable import NexusCore

final class SnippetStoreTests: XCTestCase {
    var store: SnippetStore!
    var path: String!

    override func setUp() {
        path = NSTemporaryDirectory() + "nexus-snip-\(UUID().uuidString).db"
        store = SnippetStore(path: path)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: path) }

    func testSecretContentNeverStoredInDatabase() {
        let id = store.insert(name: "db pass", content: "hunter2", tags: ["work"], secret: true)
        let s = store.all().first { $0.id == id }!
        XCTAssertTrue(s.isSecret)
        XCTAssertEqual(s.content, "")
        XCTAssertTrue(store.all(query: "hunter2").isEmpty)
        // converting a plain snippet to secret scrubs the stored text
        let p = store.insert(name: "plain", content: "visible", tags: [], secret: false)
        store.update(p, name: "plain", content: "visible", tags: [], secret: true)
        XCTAssertEqual(store.all().first { $0.id == p }?.content, "")
    }

    func testUsageOrderingTagsAndSearch() {
        let t = Date(timeIntervalSince1970: 1_000)
        let a = store.insert(name: "email", content: "a@b.c", tags: ["me", "work"], secret: false, now: t)
        let b = store.insert(name: "mongo", content: "brew services start mongodb", tags: ["dev"], secret: false, now: t + 10)
        XCTAssertEqual(store.all().map(\.id), [b, a])
        store.markUsed(a, now: t + 100)
        XCTAssertEqual(store.all().map(\.id), [a, b])
        XCTAssertEqual(store.all().first?.timesUsed, 1)
        XCTAssertEqual(store.all(tag: "dev").map(\.id), [b])
        XCTAssertEqual(store.all(query: "mongodb").map(\.id), [b])
        XCTAssertEqual(store.allTags(), ["dev", "me", "work"])
    }

    func testExpander() {
        let now = Date(timeIntervalSince1970: 1_792_767_344) // 2026-10-23 14:55:44 UTC
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(SnippetExpander.expand("on {date} at {time}: {clipboard}", clipboard: "hi", now: now, timeZone: utc),
                       "on 2026-10-23 at 14:55: hi")
        XCTAssertEqual(SnippetExpander.expand("{datetime} {nope}", clipboard: nil, now: now, timeZone: utc), "2026-10-23 14:55 {nope}")
    }
}
