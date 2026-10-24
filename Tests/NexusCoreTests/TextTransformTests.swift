import XCTest
@testable import NexusCore

final class TextTransformTests: XCTestCase {
    func run(_ t: TextTransform, _ s: String) -> String? { try? t.apply(s).get() }

    func testFormatJSONKeepsKeyOrderNumbersAndEscapes() {
        let src = #"{"b":1.50,"a":[1,2,{"x":"q\"uote, {not} [structure]"}],"empty":{},"list":[],"n":null}"#
        XCTAssertEqual(run(.formatJSON, src), """
        {
          "b": 1.50,
          "a": [
            1,
            2,
            {
              "x": "q\\"uote, {not} [structure]"
            }
          ],
          "empty": {},
          "list": [],
          "n": null
        }
        """)
        XCTAssertEqual(run(.formatJSON, #"  "just a string"  "#), #""just a string""#) // fragments are fine
        XCTAssertEqual(run(.formatJSON, "[1,2]"), "[\n  1,\n  2\n]")
    }

    func testMinifyJSONRoundTrips() {
        let pretty = run(.formatJSON, #"{"a":[1,2],"s":"x y"}"#)!
        XCTAssertEqual(run(.minifyJSON, pretty), #"{"a":[1,2],"s":"x y"}"#)
        XCTAssertEqual(run(.minifyJSON, #"{ "a" : { } , "b" : [ ] }"#), #"{"a":{},"b":[]}"#)
    }

    func testInvalidJSONReportsAnError() {
        guard case .failure(.invalid(let m)) = TextTransform.formatJSON.apply(#"{"a":1,}"#) else { return XCTFail("expected failure") }
        XCTAssertTrue(m.hasPrefix("Not valid JSON"))
        XCTAssertEqual(TextTransform.formatJSON.apply("").mapError { $0 }, .failure(.empty))
    }

    func testLineOperations() {
        XCTAssertEqual(run(.sortLines, "b\na\nc10\nc2\n"), "a\nb\nc2\nc10\n") // natural order, trailing newline kept
        XCTAssertEqual(run(.sortLinesDescending, "a\nc\nb"), "c\nb\na")
        XCTAssertEqual(run(.reverseLines, "1\n2\n3"), "3\n2\n1")
        XCTAssertEqual(run(.dedupeLines, "a\nb\na\nc\nb\n"), "a\nb\nc\n")           // first occurrence wins, order kept
        XCTAssertEqual(run(.removeEmptyLines, "a\n\n  \nb\n"), "a\nb\n")
        XCTAssertEqual(run(.trimWhitespace, "  a  \n\tb\t\n"), "a\nb\n")
    }

    func testCaseJoinSplitAndStats() {
        XCTAssertEqual(run(.upper, "Hello, wörld"), "HELLO, WÖRLD")
        XCTAssertEqual(run(.lower, "Hello"), "hello")
        XCTAssertEqual(run(.titleCase, "the quick brown fox"), "The Quick Brown Fox")
        XCTAssertEqual(run(.joinWithComma, "a\n b \n\nc\n"), "a, b, c")
        XCTAssertEqual(run(.splitCommas, "a, b ,,c"), "a\nb\nc")
        XCTAssertEqual(run(.statistics, "hello world\nbye"), "Characters: 15\nWords: 3\nLines: 2\nBytes (UTF-8): 15")
    }

    func testEscapeUnescapeRoundTrip() {
        let s = "line1\nline2\t\"quoted\" back\\slash \u{1}"
        let e = run(.escape, s)!
        XCTAssertEqual(e, #"line1\nline2\t\"quoted\" back\\slash \u0001"#)
        XCTAssertEqual(run(.unescape, e), s)
        XCTAssertEqual(run(.unescape, #"snow ☃ and 😀 \q"#), "snow ☃ and 😀 \\q") // unicode, surrogate pair, unknown escape kept
        XCTAssertEqual(run(.unescape, #"bad \u12"#), #"bad \u12"#)
    }

    func testEveryTransformRejectsEmptyInput() {
        for t in TextTransform.allCases {
            XCTAssertEqual(t.apply("").mapError { $0 }, .failure(.empty), t.title)
            XCTAssertFalse(t.keywords.isEmpty); XCTAssertFalse(t.symbol.isEmpty)
        }
    }
}

final class JSONToYAMLTests: XCTestCase {
    func yaml(_ s: String) -> String? { try? TextTransform.jsonToYAML.apply(s).get() }

    // "n" and "y" are YAML 1.1 booleans, so keys named like that are quoted on purpose.
    func testStructureKeyOrderAndQuoting() {
        let src = #"{"name":"app","version":"1.0","n":1.50,"on":"yes","empty":"","list":[1,"two",{"a":1,"b":[true,null]}],"nested":{"x":{},"y":[]},"multi":"line1\nline2\n"}"#
        XCTAssertEqual(yaml(src), """
        name: app
        version: "1.0"
        "n": 1.50
        "on": "yes"
        empty: ""
        list:
          - 1
          - two
          - a: 1
            b:
              - true
              - null
        nested:
          x: {}
          "y": []
        multi: |
          line1
          line2
        """)
    }

    func testTopLevelShapes() {
        XCTAssertEqual(yaml("[[1,2],[3]]"), "- - 1\n  - 2\n- - 3")
        XCTAssertEqual(yaml(#""hello""#), "hello")
        XCTAssertEqual(yaml("42"), "42")
        XCTAssertEqual(yaml("{}"), "{}")
        XCTAssertEqual(yaml(#"{"s":"no newline\nat end"}"#), "s: |-\n  no newline\n  at end")
    }

    func testStringsYAMLWouldMisreadAreQuoted() {
        for s in ["true", "No", "null", "~", "3", "1e3", "0x1F", "", " lead", "trail ", "#tag", "a: b", "ends:", "- item", "@at", "&anchor", "{x}"] {
            XCTAssertTrue(YAMLEmitter.needsQuotes(s), "'\(s)' should be quoted")
        }
        for s in ["hello", "héllo wörld", "v1.2.3", "a#b", "path/to/file", "foo-bar", "https://example.com/x?y=1", "2026-10-23", "it's, \"fine\" mid-string"] {
            XCTAssertFalse(YAMLEmitter.needsQuotes(s), "'\(s)' should stay plain")
        }
        XCTAssertEqual(yaml(#"{"k":"a\"b: c"}"#), #"k: "a\"b: c""#)
    }

    func testUnicodeEscapesAndDeepNesting() {
        XCTAssertEqual(yaml(#"{"e":"\u00e9\ud83d\ude00"}"#), "e: é😀")
        XCTAssertEqual(yaml(#"{"a":{"b":{"c":[{"d":1},{"e":[2]}]}}}"#), "a:\n  b:\n    c:\n      - d: 1\n      - e:\n          - 2")
    }

    func testInvalidJSONIsRejectedWithAPosition() {
        for bad in [#"{"a":1,}"#, "{'a':1}", "[1 2]", #"{"a"}"#, "01", "[1,]", "tru", #"{"a":"unterminated"#, "{} extra"] {
            guard case .failure(.invalid(let m)) = TextTransform.jsonToYAML.apply(bad) else { XCTFail("accepted: \(bad)"); continue }
            XCTAssertTrue(m.hasPrefix("Not valid JSON"), bad)
        }
    }
}

final class LineDiffTests: XCTestCase {
    func d(_ a: String, _ b: String) -> [DiffLine] { try! LineDiff.diff(a, b).get() }
    func marks(_ x: [DiffLine]) -> String { x.map { ($0.kind == .added ? "+" : $0.kind == .removed ? "-" : " ") + $0.text }.joined(separator: "|") }

    func testBasicDiffs() {
        XCTAssertEqual(marks(d("a\nb\nc", "a\nB\nc")), " a|-b|+B| c")
        XCTAssertEqual(marks(d("a\nb", "a\nb")), " a| b")
        XCTAssertEqual(marks(d("", "x\ny")), "+x|+y")
        XCTAssertEqual(marks(d("x\ny", "")), "-x|-y")
        XCTAssertEqual(marks(d("a\nb\nc\nd", "a\nc\nd\ne")), " a|-b| c| d|+e")
        XCTAssertEqual(marks(d("1\n2\n3", "3\n2\n1")), "-1|-2| 3|+2|+1") // a valid LCS of length 1
        XCTAssertEqual(marks(d("one\r\ntwo\r\n", "one\ntwo\n")), " one| two") // CRLF and trailing newline are not differences
    }

    func testStatsAndUnified() {
        let x = d("a\nb\nc\nd\ne\nf\ng\nh\ni\nj", "a\nb\nc\nd\ne\nf\ng\nh\ni\nJ")
        XCTAssertEqual(LineDiff.stats(x).added, 1); XCTAssertEqual(LineDiff.stats(x).removed, 1)
        XCTAssertEqual(LineDiff.unified(x), "@@ 6 unchanged lines @@\n  g\n  h\n  i\n- j\n+ J")
        XCTAssertEqual(LineDiff.rows(d("same", "same")), [.skipped(1)])
        XCTAssertEqual(LineDiff.unified(d("x", "x")), "@@ 1 unchanged line @@")
    }

    func testReapplyingTheDiffReproducesTheNewText() {
        let a = (1...40).map { "line \($0)" }.joined(separator: "\n")
        var b = (1...40).map { "line \($0)" }
        b.remove(at: 5); b.insert("inserted", at: 20); b[30] = "changed"; b.append("tail")
        let x = d(a, b.joined(separator: "\n"))
        XCTAssertEqual(x.filter { $0.kind != .removed }.map(\.text), b)
        XCTAssertEqual(x.filter { $0.kind != .added }.map(\.text), (1...40).map { "line \($0)" })
    }

    func testHugeDifferentTextsAreRefused() {
        let a = (0..<5000).map { "a\($0)" }.joined(separator: "\n"), b = (0..<5000).map { "b\($0)" }.joined(separator: "\n")
        guard case .failure(.invalid) = LineDiff.diff(a, b) else { return XCTFail("expected refusal") }
        // but a large file with a few edits is fine (shared head/tail are trimmed first)
        let big = (0..<20_000).map { "row \($0)" }
        var edited = big; edited[10_000] = "changed"
        XCTAssertEqual(LineDiff.stats(try! LineDiff.diff(big.joined(separator: "\n"), edited.joined(separator: "\n")).get()).added, 1)
    }
}
