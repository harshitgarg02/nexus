import XCTest
@testable import NexusCore

final class CalculatorTests: XCTestCase {
    // Fri 23 Oct 2026 14:55:44 UTC
    let now = Date(timeIntervalSince1970: 1_792_767_344)
    let utc = TimeZone(identifier: "UTC")!

    func eval(_ s: String) -> [CalcRow] { Calculator.evaluate(s, now: now, timeZone: utc) }
    func first(_ s: String) -> String? { eval(s).first?.title }

    func testMath() {
        XCTAssertEqual(first("2+3*4"), "14")
        XCTAssertEqual(first("(2+3)*4"), "20")
        XCTAssertEqual(first("2^10"), "1,024")
        XCTAssertEqual(first("1.5k * 2"), "3,000")
        XCTAssertEqual(first("20% of 50"), "10")
        XCTAssertEqual(first("200 + 15%"), "230")
        XCTAssertEqual(first("sqrt(16) + 1"), "5")
        XCTAssertEqual(first("255 to hex"), "0xff")
        XCTAssertEqual(first("0xff + 1"), "256")
        XCTAssertEqual(eval("2+3").first?.copy, "5")
    }

    func testNotACalculation() {
        XCTAssertTrue(eval("5").isEmpty)
        XCTAssertTrue(eval("safari").isEmpty)
        XCTAssertTrue(eval("2+").isEmpty)
        XCTAssertTrue(eval("").isEmpty)
    }

    func testUnits() {
        XCTAssertEqual(first("5 km to miles"), "3.1068559612 miles")
        XCTAssertEqual(first("100 f to c"), "37.7777777778 c")
        XCTAssertEqual(first("2gb to mb"), "2,000 mb")
    }

    func testEpoch() {
        let r = eval("1792767344")
        XCTAssertEqual(r[0].title, "Fri 23 Oct 2026, 2:55:44 PM GMT")
        XCTAssertEqual(r[2].title, "2026-10-23T14:55:44Z")
        XCTAssertEqual(r.first { $0.subtitle.hasPrefix("Epoch seconds") }?.title, "1792767344.000000")

        let ms = eval("1792767344123")
        XCTAssertEqual(ms[0].title, "Fri 23 Oct 2026, 2:55:44.123000 PM GMT")

        let us = eval("1792767344123456")
        XCTAssertEqual(us[0].title, "Fri 23 Oct 2026, 2:55:44.123456 PM GMT")
        XCTAssertEqual(us.first { $0.subtitle == "Epoch milliseconds" }?.title, "1792767344123")

        let ns = eval("1792767344123456789")
        XCTAssertEqual(ns[0].title, "Fri 23 Oct 2026, 2:55:44.123456 PM GMT")

        let dec = eval("1792767344.5")
        XCTAssertEqual(dec[0].title, "Fri 23 Oct 2026, 2:55:44.500000 PM GMT")

        // out of range / wrong length -> not epoch
        XCTAssertTrue(eval("12345").isEmpty)
        XCTAssertTrue(eval("9999999999").isEmpty)
    }

    func testDateDiff() {
        XCTAssertEqual(first("25 dec 2026 - today"), "63 days")
        XCTAssertEqual(first("today - 25 dec 2026"), "-63 days")
        XCTAssertEqual(eval("25 dec 2026 - today")[1].title, "9 weeks")
        XCTAssertEqual(eval("2026-01-01 - 2025-01-01").first?.title, "365 days")
        XCTAssertEqual(first("9:30 - 6:45"), "2h 45m")
        XCTAssertEqual(eval("9:30 - 6:45")[1].title, "2:45")
        XCTAssertEqual(eval("6:45 - 9:30")[1].title, "-2:45")
        XCTAssertEqual(eval("23:59 - 6:18")[1].title, "17:41")
    }

    func testDateShift() {
        XCTAssertEqual(first("today + 90 days"), "Thu 21 Jan 2027")
        XCTAssertEqual(first("1 jan 2026 + 10 bd"), "Thu 15 Jan 2026")
        XCTAssertEqual(first("now + 3h"), "Fri 23 Oct 2026, 5:55:44 PM GMT")
        XCTAssertTrue(eval("today + 90 days").contains { $0.subtitle == "Epoch milliseconds" })
    }

    func testTimeZones() {
        XCTAssertEqual(first("3pm ist to utc"), "Fri 23 Oct 2026, 9:30:00 AM GMT")
        XCTAssertNotNil(first("now in tokyo"))
    }
}

final class NamedDateTests: XCTestCase {
    // Fri 23 Oct 2026 14:55:44 UTC
    let now = Date(timeIntervalSince1970: 1_792_767_344)
    let utc = TimeZone(identifier: "UTC")!
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }
    func eval(_ s: String) -> [CalcRow] { Calculator.evaluate(s, now: now, timeZone: utc) }
    func ymd(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    func holiday(_ s: String) -> Holiday? { Holidays.resolve(s, now: now, calendar: cal) }

    func testDaysUntil() {
        XCTAssertEqual(eval("days until christmas").first?.title, "63 days")
        XCTAssertEqual(eval("how many days until halloween").first?.title, "8 days")
        XCTAssertEqual(eval("days to new year").first?.title, "70 days")
        XCTAssertEqual(eval("until easter").first?.title, "156 days") // Easter 2027-03-28
        XCTAssertEqual(eval("days since christmas 2025").first?.title, "302 days")
    }

    func testBareNameShowsDateAndDaysAway() {
        let r = eval("christmas")
        XCTAssertEqual(r[0].title, "Fri 25 Dec 2026")
        XCTAssertEqual(r[1].title, "in 63 days")
        XCTAssertEqual(eval("eid")[0].subtitle, "Eid al-Fitr (approx.)")
        XCTAssertEqual(eval("halloween")[1].title, "in 8 days")
    }

    func testRolesToNextYearWhenPassed() {
        XCTAssertEqual(ymd(holiday("republic day")!.date), "2027-01-26")
        XCTAssertEqual(ymd(holiday("republic day 2026")!.date), "2026-01-26") // explicit year wins, even if past
    }

    func testRuleBasedDates() {
        XCTAssertEqual(ymd(holiday("easter 2026")!.date), "2026-04-05")
        XCTAssertEqual(ymd(holiday("good friday 2026")!.date), "2026-04-03")
        XCTAssertEqual(ymd(holiday("thanksgiving 2026")!.date), "2026-11-26")
        XCTAssertEqual(ymd(holiday("mother's day 2026")!.date), "2026-05-10")
        XCTAssertEqual(ymd(holiday("fathers day 2026")!.date), "2026-06-21")
        XCTAssertEqual(ymd(holiday("labor day 2026")!.date), "2026-09-07")
        XCTAssertEqual(ymd(holiday("chinese new year 2026")!.date), "2026-02-17")
        XCTAssertEqual(ymd(holiday("chinese new year 2027")!.date), "2027-02-06")
    }

    func testApproximateDates() {
        XCTAssertTrue(holiday("eid al adha 2026")!.approximate)
        // Umm al-Qura can differ from the moon sighting by a day: accept 2026-03-19...21 / 05-26...28
        XCTAssertTrue(["2026-03-19", "2026-03-20", "2026-03-21"].contains(ymd(holiday("eid 2026")!.date)))
        XCTAssertTrue(["2026-05-26", "2026-05-27", "2026-05-28"].contains(ymd(holiday("eid al adha 2026")!.date)))
        XCTAssertNil(holiday("diwali")) // lunisolar festivals aren't built in
    }

    func testNamesInArithmeticAndNonHolidays() {
        XCTAssertEqual(eval("halloween - today").first?.title, "8 days")
        XCTAssertTrue(eval("safari").isEmpty)
        XCTAssertTrue(eval("days until nothing").isEmpty)
    }
}
