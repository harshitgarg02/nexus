import XCTest
@testable import NexusCore

final class SmallToolsTests: XCTestCase {
    func testHTTPLookup() {
        XCTAssertEqual(HTTPStatus.lookup("404").first?.name, "Not Found")
        XCTAssertEqual(HTTPStatus.lookup("418").first?.name, "I'm a Teapot")
        XCTAssertEqual(HTTPStatus.lookup("503").first?.category, "Server error")
        XCTAssertEqual(HTTPStatus.lookup("4xx").count, HTTPStatus.all.filter { $0.code / 100 == 4 }.count)
        XCTAssertEqual(HTTPStatus.lookup("3").first?.code, 300)
        XCTAssertEqual(HTTPStatus.lookup("teapot").map(\.code), [418])
        XCTAssertEqual(HTTPStatus.lookup("too many").map(\.code), [429])
        XCTAssertTrue(HTTPStatus.lookup("799").isEmpty)
        XCTAssertEqual(HTTPStatus.all.count, Set(HTTPStatus.all.map(\.code)).count) // no duplicate codes
        XCTAssertTrue(HTTPStatus.all.allSatisfy { !$0.name.isEmpty && !$0.meaning.isEmpty })
    }

    func testNumberBaseParseAndFormat() {
        let v = NumberBase.parse("255")!
        XCTAssertEqual(v.string(radix: 16, prefix: "0x", uppercase: true), "0xFF")
        XCTAssertEqual(v.string(radix: 2, prefix: "0b"), "0b11111111")
        XCTAssertEqual(v.string(radix: 8, prefix: "0o"), "0o377")
        XCTAssertEqual(v.string(radix: 36), "73")
        XCTAssertEqual(NumberBase.parse("0xFF")?.magnitude, 255)
        XCTAssertEqual(NumberBase.parse("0b1111_0000")?.magnitude, 240)
        XCTAssertEqual(NumberBase.parse("0o17")?.magnitude, 15)
        XCTAssertEqual(NumberBase.parse("1,000")?.magnitude, 1000)
        XCTAssertEqual(NumberBase.parse("ff", radix: 16)?.magnitude, 255)
        XCTAssertEqual(NumberBase.parse("1010", radix: 2)?.magnitude, 10)
        XCTAssertEqual(NumberBase.parse("0xff", radix: 16)?.magnitude, 255) // matching prefix is fine
        XCTAssertNil(NumberBase.parse("0xff", radix: 10))                  // conflicting prefix
        XCTAssertNil(NumberBase.parse("12", radix: 2))                     // digit out of range
        XCTAssertNil(NumberBase.parse("ff"))                               // letters need an explicit base
        XCTAssertNil(NumberBase.parse("99999999999999999999"))             // > 64 bits
        XCTAssertEqual(NumberBase.parse("-255")?.string(radix: 16, prefix: "0x"), "-0xff")
        XCTAssertEqual(NumberBase.parse("-0")?.string(radix: 10), "0")
    }

    func testLoremIsDeterministicAndSized() {
        XCTAssertEqual(Lorem.words(5), "Lorem ipsum dolor sit amet.")
        XCTAssertEqual(Lorem.words(200).split(separator: " ").count, 200)
        XCTAssertEqual(Lorem.words(100_000).split(separator: " ").count, Lorem.maxWords) // capped
        let p = Lorem.paragraphs(3)
        XCTAssertEqual(p.count, 3)
        XCTAssertTrue(p[0].hasPrefix("Lorem ipsum dolor sit amet, consectetur adipiscing elit"))
        XCTAssertNotEqual(p[1], p[2])
        XCTAssertEqual(Lorem.paragraphs(3), p) // same input, same text
        XCTAssertEqual(Lorem.sentences(4).filter { $0 == "." }.count, 4)
        XCTAssertEqual(Lorem.paragraphs(1000).count, Lorem.maxParagraphs)
        XCTAssertTrue(p.allSatisfy { $0.hasSuffix(".") && $0.first!.isUppercase })
    }
}

final class CronTests: XCTestCase {
    // Fri 23 Oct 2026 14:55:44 UTC
    let now = Date(timeIntervalSince1970: 1_792_767_344)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func schedule(_ s: String) -> CronSchedule { try! CronSchedule.parse(s).get() }
    func runs(_ s: String, _ n: Int = 3) -> [String] {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return schedule(s).nextRuns(after: now, count: n, calendar: cal).map(f.string)
    }

    func testNextRuns() {
        XCTAssertEqual(runs("*/5 * * * *"), ["2026-10-23 15:00", "2026-10-23 15:05", "2026-10-23 15:10"])
        XCTAssertEqual(runs("30 9 * * *"), ["2026-10-24 09:30", "2026-10-25 09:30", "2026-10-26 09:30"])
        XCTAssertEqual(runs("0 9 * * 1-5"), ["2026-10-26 09:00", "2026-10-27 09:00", "2026-10-28 09:00"]) // Fri 23rd is past 9:00; next is Monday
        XCTAssertEqual(runs("0 0 1 * *", 2), ["2026-11-01 00:00", "2026-12-01 00:00"])
        XCTAssertEqual(runs("0 12 29 2 *", 1), ["2028-02-29 12:00"]) // leap day found years ahead
        XCTAssertEqual(runs("@hourly", 2), ["2026-10-23 15:00", "2026-10-23 16:00"])
        XCTAssertEqual(runs("0 0 * * 7", 1), runs("0 0 * * 0", 1)) // 7 is Sunday too
    }

    func testDayOfMonthOrDayOfWeekWhenBothRestricted() {
        // 15th of the month OR any Monday (Vixie cron)
        XCTAssertEqual(runs("0 0 15 * 1", 3), ["2026-10-26 00:00", "2026-11-02 00:00", "2026-11-09 00:00"])
        XCTAssertEqual(runs("0 0 31 4 *", 1), []) // April has no 31st: never runs
    }

    func testNamesRangesAndSteps() {
        XCTAssertEqual(runs("0 8 * jan,feb mon", 1), ["2027-01-04 08:00"])
        XCTAssertEqual(runs("10-20/5 3 * * *", 4), ["2026-10-24 03:10", "2026-10-24 03:15", "2026-10-24 03:20", "2026-10-25 03:10"])
        XCTAssertEqual(schedule("0 0 * * MON-FRI").daysOfWeek, [1, 2, 3, 4, 5])
    }

    func testDescriptions() {
        XCTAssertEqual(schedule("* * * * *").describe(), "Every minute every day")
        XCTAssertEqual(schedule("*/5 * * * *").describe(), "Every 5 minutes every day")
        XCTAssertEqual(schedule("0 * * * *").describe(), "At the start of every hour every day")
        XCTAssertEqual(schedule("30 9 * * *").describe(), "At 09:30 every day")
        XCTAssertEqual(schedule("0 9 * * 1-5").describe(), "At 09:00 on Monday through Friday")
        XCTAssertEqual(schedule("0 0 1 * *").describe(), "At 00:00 on day 1 of the month")
        XCTAssertEqual(schedule("0 0 15 * 1").describe(), "At 00:00 on day 15 of the month or on Monday")
        XCTAssertEqual(schedule("15 14 1 jan,jul *").describe(), "At 14:15 on day 1 of the month in January and July")
        XCTAssertEqual(schedule("@daily").describe(), "At 00:00 every day")
        XCTAssertEqual(schedule("0 0 * * 0,6").describe(), "At 00:00 on weekends")
    }

    func testInvalidExpressions() {
        for bad in ["* * * *", "* * * * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "*/0 * * * *", "a * * * *", "5-1 * * * *", ", * * * *"] {
            XCTAssertThrowsError(try CronSchedule.parse(bad).get(), bad)
        }
        XCTAssertThrowsError(try CronSchedule.parse("@reboot").get()) { XCTAssertEqual(($0 as? CronError)?.errorDescription?.contains("starts"), true) }
    }
}

final class RegexToolTests: XCTestCase {
    func ok(_ p: String, _ t: String, _ f: RegexFlags = RegexFlags()) -> [RegexMatch] {
        guard case .success(let m) = RegexTool.matches(pattern: p, flags: f, in: t) else { XCTFail("expected success for \(p)"); return [] }
        return m
    }

    func testMatchesGroupsAndRanges() {
        let m = ok(#"(\d+)-(\d+)"#, "call 555-1234 or 800-9999")
        XCTAssertEqual(m.map(\.text), ["555-1234", "800-9999"])
        XCTAssertEqual(m[0].groups, ["555", "1234"])
        XCTAssertEqual(m[0].range, NSRange(location: 5, length: 8))
    }

    func testNamedGroupsAndOptionalGroups() {
        let m = ok(#"(?<year>\d{4})-(?<month>\d{2})(-(\d{2}))?"#, "2026-10")
        XCTAssertEqual(m[0].named.map(\.name), ["year", "month"])
        XCTAssertEqual(m[0].named.map(\.text), ["2026", "10"])
        XCTAssertEqual(m[0].groups.last!, nil) // the optional group didn't participate
    }

    func testFlags() {
        XCTAssertEqual(ok("hello", "Hello HELLO").count, 0)
        XCTAssertEqual(ok("hello", "Hello HELLO", RegexFlags(ignoreCase: true)).count, 2)
        XCTAssertEqual(ok("^b", "a\nb").count, 0)
        XCTAssertEqual(ok("^b", "a\nb", RegexFlags(multiline: true)).count, 1)
        XCTAssertEqual(ok("a.b", "a\nb").count, 0)
        XCTAssertEqual(ok("a.b", "a\nb", RegexFlags(dotAll: true)).count, 1)
    }

    func testInvalidPatternAndLimits() {
        guard case .failure(.invalid(let m)) = RegexTool.matches(pattern: "(", in: "x") else { return XCTFail("expected failure") }
        XCTAssertTrue(m.hasPrefix("Invalid pattern"))
        XCTAssertEqual(ok("", "anything").count, 0)
        XCTAssertEqual(ok("a", String(repeating: "a", count: 2000)).count, RegexTool.matchLimit)
        XCTAssertEqual(ok(".*", "x").map(\.text), ["x", ""]) // empty trailing match is reported
    }

    func testParseTyped() {
        let p = RegexTool.parseTyped(#"/(\d+)\/(\d+)/i see 3/4 now"#)!
        XCTAssertEqual(p.pattern, #"(\d+)\/(\d+)"#)
        XCTAssertTrue(p.flags.ignoreCase); XCTAssertFalse(p.flags.multiline)
        XCTAssertEqual(p.text, "see 3/4 now")
        XCTAssertEqual(RegexTool.parseTyped("/a/gms text")?.flags, RegexFlags(ignoreCase: false, multiline: true, dotAll: true))
        XCTAssertNil(RegexTool.parseTyped("a/b/ text")); XCTAssertNil(RegexTool.parseTyped("/unterminated text")); XCTAssertNil(RegexTool.parseTyped("// text"))
    }
}
