import XCTest
@testable import NexusCore

final class SnippetTransferTests: XCTestCase {
    var paths: [String] = []

    func makeStore() -> SnippetStore {
        let p = NSTemporaryDirectory() + "nexus-xfer-\(UUID().uuidString).db"
        paths.append(p)
        return SnippetStore(path: p)
    }
    override func tearDown() { paths.forEach { try? FileManager.default.removeItem(atPath: $0) } }

    func testExportExcludesSecretsAndRoundTrips() throws {
        let a = makeStore()
        a.insert(name: "email", content: "me@x.com", tags: ["me", "work"], secret: false, now: Date(timeIntervalSince1970: 100))
        a.insert(name: "db pass", content: "hunter2", tags: [], secret: true)
        let out = try SnippetTransfer.export(a.all())
        XCTAssertEqual(out.exported, 1)
        XCTAssertEqual(out.skippedSecrets, 1)
        XCTAssertFalse(String(decoding: out.data, as: UTF8.self).contains("hunter2"))

        let b = makeStore()
        let s = b.importEntries(try SnippetTransfer.decode(out.data))
        XCTAssertEqual(s, ImportSummary(added: 1, duplicates: 0, renamed: 0, invalid: 0))
        let got = b.all().first!
        XCTAssertEqual(got.name, "email"); XCTAssertEqual(got.content, "me@x.com"); XCTAssertEqual(got.tags, ["me", "work"])
        XCTAssertEqual(got.created, Date(timeIntervalSince1970: 100)) // timestamps preserved
    }

    func testReimportIsIdempotentAndNameClashesAreRenamed() throws {
        let store = makeStore()
        store.insert(name: "greeting", content: "hello", tags: [], secret: false)
        let e = { (n: String, c: String) in SnippetExport.Entry(name: n, content: c, tags: [], created: Date(), modified: Date()) }

        var s = store.importEntries([e("greeting", "hello")])
        XCTAssertEqual(s.duplicates, 1); XCTAssertEqual(s.added, 0)

        s = store.importEntries([e("greeting", "hi there")])
        XCTAssertEqual(s.renamed, 1)
        s = store.importEntries([e("greeting", "yo")])
        XCTAssertEqual(Set(store.all().map(\.name)), ["greeting", "greeting (imported)", "greeting (imported 2)"])
        XCTAssertEqual(store.all().first { $0.name == "greeting" }?.content, "hello") // original untouched
    }

    func testSecretWithSameNameNeverCountsAsDuplicate() {
        let store = makeStore()
        store.insert(name: "pw", content: "x", tags: [], secret: true)
        let s = store.importEntries([.init(name: "pw", content: "", tags: [], created: Date(), modified: Date()),
                                     .init(name: "pw", content: "plain", tags: [], created: Date(), modified: Date())])
        XCTAssertEqual(s.invalid, 1)
        XCTAssertEqual(s.renamed, 1)
        XCTAssertEqual(store.all().filter { $0.isSecret }.count, 1)
    }

    func testKindsAndLanguageSurviveExportImport() throws {
        let a = makeStore()
        a.insert(name: "fmt", content: "func f() {}", tags: [], secret: false, kind: .code, language: "swift")
        a.insert(name: "logs", content: "tail -f /var/log/system.log", tags: [], secret: false, kind: .command, language: "ignored")
        let b = makeStore()
        _ = b.importEntries(try SnippetTransfer.decode(try SnippetTransfer.export(a.all()).data))
        let got = Dictionary(uniqueKeysWithValues: b.all().map { ($0.name, $0) })
        XCTAssertEqual(got["fmt"]?.kind, .code); XCTAssertEqual(got["fmt"]?.language, "swift")
        XCTAssertEqual(got["logs"]?.kind, .command); XCTAssertEqual(got["logs"]?.language, "") // language only applies to code
    }

    func testOldExportWithoutKindImportsAsText() throws {
        let old = #"{"version":1,"exportedAt":"2026-01-01T00:00:00Z","snippets":[{"name":"n","content":"c","tags":[],"created":"2026-01-01T00:00:00Z","modified":"2026-01-01T00:00:00Z"}]}"#
        let store = makeStore()
        XCTAssertEqual(store.importEntries(try SnippetTransfer.decode(Data(old.utf8))).added, 1)
        XCTAssertEqual(store.all().first?.kind, .text)
    }

    func testRejectsBadFiles() {
        XCTAssertThrowsError(try SnippetTransfer.decode(Data("[1,2]".utf8))) { XCTAssertEqual($0 as? TransferError, .notSnippetFile) }
        XCTAssertThrowsError(try SnippetTransfer.decode(Data("not json".utf8))) { XCTAssertEqual($0 as? TransferError, .notSnippetFile) }
        let future = #"{"version":99,"exportedAt":"2026-01-01T00:00:00Z","snippets":[]}"#
        XCTAssertThrowsError(try SnippetTransfer.decode(Data(future.utf8))) { XCTAssertEqual($0 as? TransferError, .unsupportedVersion(99)) }
    }
}
