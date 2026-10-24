import XCTest
@testable import NexusCore

final class CommandRankerTests: XCTestCase {
    func e(_ id: String, _ title: String, _ kw: [String] = [], _ group: Int = 4) -> CommandRanker.Entry {
        .init(id: id, title: title, keywords: kw, group: group)
    }

    func testTiers() {
        XCTAssertEqual(CommandRanker.tier(query: "gen", title: "Generate UUID", keywords: []), 0)
        XCTAssertEqual(CommandRanker.tier(query: "uuid", title: "Generate UUID", keywords: []), 1)       // a word in the title
        XCTAssertEqual(CommandRanker.tier(query: "guid", title: "Generate UUID", keywords: ["guid"]), 2)  // keyword only
        XCTAssertEqual(CommandRanker.tier(query: "nerate", title: "Generate UUID", keywords: []), 3)     // inside a word
        XCTAssertNil(CommandRanker.tier(query: "zzz", title: "Generate UUID", keywords: ["id"]))
        XCTAssertEqual(CommandRanker.tier(query: "", title: "Anything", keywords: []), 0)
        XCTAssertEqual(CommandRanker.tier(query: "gen pass", title: "Generate Password", keywords: []), 1) // every word prefixes a title word
        XCTAssertEqual(CommandRanker.tier(query: "gen secret", title: "Generate Password", keywords: ["secret"]), 2)
        XCTAssertNil(CommandRanker.tier(query: "gen foo", title: "Generate Password", keywords: []))
    }

    func testBestMatchBeatsGroupOrder() {
        let all = [e("sort", "Sort Lines (A→Z)", ["lines"], 5), e("snip", "Search Snippets", [], 0), e("sleep", "Sleep", [], 2),
                   e("slack", "Convert to lowercase", ["lower"], 5)]
        XCTAssertEqual(CommandRanker.order(all, query: "s"), ["snip", "sleep", "sort", "slack"]) // prefixes first (ties by group), "lowercase" only contains an s
        XCTAssertEqual(CommandRanker.order(all, query: "lines"), ["sort"])
        XCTAssertEqual(CommandRanker.order(all, query: "low"), ["slack"])
    }

    func testPrefixOutranksKeywordEvenInALaterGroup() {
        let all = [e("a", "Open Ports", ["kill", "port"], 0), e("b", "Kill Process", [], 2)]
        XCTAssertEqual(CommandRanker.order(all, query: "kill"), ["b", "a"])
    }

    func testUsageThenGroupThenAlphabetical() {
        let all = [e("z", "Zeta", [], 0), e("m", "Mid", [], 1), e("a", "Alpha", [], 1), e("b", "Beta", [], 1)]
        XCTAssertEqual(CommandRanker.order(all, query: ""), ["z", "a", "b", "m"])                       // group, then A–Z
        XCTAssertEqual(CommandRanker.order(all, query: "", usage: ["b": 5, "m": 2]), ["b", "m", "z", "a"]) // used commands first
        XCTAssertEqual(CommandRanker.order(all, query: "", usage: ["m": 2, "b": 2]), ["b", "m", "z", "a"]) // equal use: alphabetical
    }
}
