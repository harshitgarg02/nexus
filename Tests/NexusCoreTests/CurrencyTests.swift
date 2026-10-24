import XCTest
@testable import NexusCore

final class CurrencyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_767_344)
    lazy var rates = CurrencyRates(base: "USD", rates: ["USD": 1, "INR": 83.5, "EUR": 0.5, "JPY": 150], updated: now.addingTimeInterval(-7200), fetched: now)

    func eval(_ s: String, _ state: CurrencyState) -> [CalcRow] { Calculator.evaluate(s, now: now, currency: state) }

    func testConvertsViaBaseAndCopiesRawNumber() {
        let r = eval("100 usd to inr", .ready(rates))
        XCTAssertEqual(r[0].title, "8,350 INR")
        XCTAssertEqual(r[0].copy, "8350")
        XCTAssertEqual(eval("100 eur to inr", .ready(rates))[0].title, "16,700 INR") // cross rate: 100 / 0.5 * 83.5
        XCTAssertEqual(r[1].title, "1 USD = 83.5 INR")
        XCTAssertEqual(r[1].subtitle, "Rate · updated 2 h ago")
    }

    func testSymbolsAndSeparators() {
        XCTAssertEqual(eval("$1,000 to eur", .ready(rates))[0].title, "500 EUR")
        XCTAssertEqual(eval("₹835 in usd", .ready(rates))[0].title, "10 USD")
        XCTAssertEqual(eval("100 USD TO jpy", .ready(rates))[0].title, "15,000 JPY")
    }

    func testOffAndLoadingShowHintsOnlyForRealCurrencyPairs() {
        XCTAssertEqual(eval("100 usd to inr", .disabled).first?.title, "Currency conversion is off")
        XCTAssertEqual(eval("100 usd to inr", .loading).first?.title, "Fetching exchange rates…")
        XCTAssertTrue(eval("5 foo to bar", .disabled).isEmpty)
        XCTAssertTrue(eval("5 foo to bar", .ready(rates)).isEmpty) // unknown code: no row
    }

    func testUnitsStillWinOverCurrency() {
        XCTAssertEqual(eval("5 km to mi", .ready(rates)).first?.title, "3.1068559612 mi")
        XCTAssertEqual(eval("100 f to c", .ready(rates)).first?.title, "37.7777777778 c")
    }

    func testParseProviderResponse() {
        let codes = (0..<12).map { "\"C\($0)\":\($0 + 1).5" }.joined(separator: ",")
        let body = #"{"result":"success","time_last_update_unix":1792713600,"base_code":"USD","rates":{"USD":1,"INR":83.5,"# + codes + "}}"
        let p = CurrencyRates.parse(Data(body.utf8), fetched: now)
        XCTAssertEqual(p?.base, "USD")
        XCTAssertEqual(p?.rates["INR"], 83.5)
        XCTAssertEqual(p?.updated, Date(timeIntervalSince1970: 1_792_713_600))
        XCTAssertNil(CurrencyRates.parse(Data(#"{"result":"error"}"#.utf8)))
        XCTAssertNil(CurrencyRates.parse(Data("nope".utf8)))
    }
}
