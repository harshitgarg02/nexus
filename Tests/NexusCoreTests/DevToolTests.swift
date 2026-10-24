import XCTest
@testable import NexusCore

final class DevToolTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_767_344) // 2026-10-23 14:55:44 UTC
    let utc = TimeZone(identifier: "UTC")!
    func eval(_ s: String) -> [CalcRow] { Calculator.evaluate(s, now: now, timeZone: utc) }
    func hex(_ a: Hashes.Algorithm, _ s: String) -> String { Hashes.hex(a, Data(s.utf8)) }

    // MARK: base64 / url

    func testBase64EncodeDecode() {
        XCTAssertEqual(eval("base64 hello").map(\.title), ["aGVsbG8=", "aGVsbG8"])
        XCTAssertEqual(eval("base64 ???>>>").map(\.title), ["Pz8/Pj4+", "Pz8_Pj4-"]) // + / vs - _
        XCTAssertEqual(eval("unbase64 aGVsbG8=").first?.title, "hello")
        XCTAssertEqual(eval("unbase64 aGVsbG8").first?.title, "hello")          // missing padding
        XCTAssertEqual(eval("b64d Pz8_Pj4-").first?.title, "???>>>")            // url-safe alphabet
        XCTAssertEqual(eval("unbase64 3q2+7w==").first?.subtitle, "Decoded: 4 bytes, not text (hex)")
        XCTAssertEqual(eval("unbase64 3q2+7w==").first?.title, "deadbeef")
        XCTAssertTrue(eval("unbase64 not base64!").isEmpty)
        XCTAssertEqual(eval("base64 héllo ✓").first.map { Base64Tools.decode($0.title).flatMap { String(data: $0, encoding: .utf8) } }, "héllo ✓")
    }

    func testURLEncodeDecode() {
        XCTAssertEqual(eval("urlencode a b&c=d/é").map(\.title), ["a%20b%26c%3Dd%2F%C3%A9", "a+b%26c%3Dd%2F%C3%A9"])
        XCTAssertEqual(eval("urldecode a%20b%26c").map(\.title), ["a b&c"])
        XCTAssertEqual(eval("urldecode a%20b+c").map(\.title), ["a b+c", "a b c"]) // both readings when a + is present
        XCTAssertTrue(eval("urldecode %zz").isEmpty)
    }

    // MARK: hashes

    func testHashesMatchKnownVectors() {
        XCTAssertEqual(hex(.md5, "hello"), "5d41402abc4b2a76b9719d911017c592")
        XCTAssertEqual(hex(.sha1, "hello"), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        XCTAssertEqual(hex(.sha256, "hello"), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertTrue(hex(.sha512, "hello").hasPrefix("9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca7"))
        XCTAssertEqual(eval("sha256 hello").first?.title, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertEqual(eval("hash hello").map(\.subtitle), ["MD5", "SHA1", "SHA256", "SHA512"])
        XCTAssertEqual(eval("md5 ").count, 0) // needs text
        XCTAssertEqual(eval("md5").count, 0)  // a bare word still searches apps
    }

    // MARK: JWT

    func token(header: String, payload: String, sig: String = "c2lnbmF0dXJl") -> String {
        Base64Tools.encode(Data(header.utf8), urlSafe: true) + "." + Base64Tools.encode(Data(payload.utf8), urlSafe: true) + "." + sig
    }

    func testJWTDecode() {
        let t = token(header: #"{"alg":"HS256","typ":"JWT"}"#, payload: #"{"sub":"123","name":"Ada","exp":1792763744,"iat":1792760144}"#)
        let r = eval(t) // pasted bare
        XCTAssertEqual(r[0].title, "Fri 23 Oct 2026, 1:55:44 PM GMT")
        XCTAssertEqual(r[0].subtitle, "Expired 1 hour ago")
        XCTAssertEqual(r.first { $0.subtitle == "Payload" }?.title, #"{"exp":1792763744,"iat":1792760144,"name":"Ada","sub":"123"}"#)
        XCTAssertEqual(r.first { $0.subtitle == "Header" }?.title, #"{"alg":"HS256","typ":"JWT"}"#)
        XCTAssertTrue(r.first { $0.subtitle == "Payload" }!.copy.contains("\n  \"name\" : \"Ada\"")) // copy is pretty-printed
        XCTAssertEqual(r.first { $0.subtitle.hasPrefix("Issued") }?.subtitle, "Issued 2 hours ago")
        XCTAssertEqual(r.last?.title, "Signature not verified")
        XCTAssertEqual(eval("jwt " + t).count, r.count)
    }

    func testJWTExpiryDirection() {
        let future = token(header: #"{"alg":"none"}"#, payload: #"{"exp":1792774544}"#, sig: "") // +2h, unsigned
        XCTAssertEqual(eval(future).first?.subtitle, "Expires in 2 hours")
        let past = token(header: #"{"alg":"none"}"#, payload: #"{"exp":1792594544}"#)
        XCTAssertEqual(eval(past).first?.subtitle, "Expired 2 days ago")
        XCTAssertTrue(eval("eyJhbGciOiJIUzI1NiJ9.notjson.sig").isEmpty)
        XCTAssertTrue(eval("jwt nope").isEmpty)
    }

    // MARK: colours

    func testColorConversions() {
        XCTAssertEqual(eval("#ff5733").map(\.title), ["#FF5733", "rgb(255, 87, 51)", "hsl(11, 100%, 60%)", "Color(red: 1.000, green: 0.341, blue: 0.200)"])
        XCTAssertEqual(eval("#f00").first?.title, "#FF0000")
        XCTAssertEqual(eval("rgb(0, 128, 255)").first?.title, "#0080FF")
        XCTAssertEqual(eval("rgb(0 128 255)").first?.title, "#0080FF")
        XCTAssertEqual(eval("hsl(120, 100%, 50%)").first?.title, "#00FF00")
        XCTAssertEqual(eval("hsl(0, 0%, 50%)").map(\.title)[1], "rgb(128, 128, 128)")
        let a = eval("#ff573380")
        XCTAssertEqual(a[0].title, "#FF573380"); XCTAssertEqual(a[1].title, "rgba(255, 87, 51, 0.5)")
        XCTAssertTrue(eval("#zzz").isEmpty)
        XCTAssertTrue(eval("rgb(300, 0, 0)").isEmpty)
        XCTAssertTrue(eval("face").isEmpty) // hex-looking word without # is not a colour
    }

    // MARK: case

    func testWordSplitting() {
        XCTAssertEqual(CaseTools.words("getHTTPResponse_code"), ["get", "HTTP", "Response", "code"])
        XCTAssertEqual(CaseTools.words("my-var name"), ["my", "var", "name"])
        XCTAssertEqual(CaseTools.words("version2Update"), ["version2", "Update"])
        XCTAssertEqual(CaseTools.words("  --  "), [])
    }

    func testCaseConversions() {
        XCTAssertEqual(eval("camel my var name").first?.title, "myVarName")
        XCTAssertEqual(eval("pascal my var name").first?.title, "MyVarName")
        XCTAssertEqual(eval("snake HTTPServerError").first?.title, "http_server_error")
        XCTAssertEqual(eval("kebab Hello World").first?.title, "hello-world")
        XCTAssertEqual(eval("constant helloWorld").first?.title, "HELLO_WORLD")
        XCTAssertEqual(eval("case hello brave world").map(\.title),
                       ["helloBraveWorld", "HelloBraveWorld", "hello_brave_world", "hello-brave-world", "HELLO_BRAVE_WORLD",
                        "Hello Brave World", "hello brave world", "HELLO BRAVE WORLD"])
        XCTAssertTrue(eval("snake").isEmpty) // bare word: no hijack
    }
}

final class SmallToolRowTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_767_344) // Fri 23 Oct 2026 14:55:44 UTC
    let utc = TimeZone(identifier: "UTC")!
    func eval(_ s: String) -> [CalcRow] { Calculator.evaluate(s, now: now, timeZone: utc) }

    func testHTTP() {
        XCTAssertEqual(eval("http 404").first?.title, "404 Not Found")
        XCTAssertEqual(eval("http 404").first?.subtitle, "Client error · There is no resource at this URL.")
        XCTAssertEqual(eval("http teapot").first?.title, "418 I'm a Teapot")
        XCTAssertEqual(eval("http 5xx").count, HTTPStatus.all.filter { $0.code / 100 == 5 }.prefix(10).count)
        XCTAssertTrue(eval("http 799").isEmpty)
        XCTAssertTrue(eval("http").isEmpty) // bare word still searches apps
    }

    func testNumberBase() {
        XCTAssertEqual(eval("base 255").map(\.title), ["255", "0xFF", "0b11111111", "0o377", "73"])
        XCTAssertEqual(eval("base ff hex").first?.title, "255")
        XCTAssertEqual(eval("base 1010 2").first?.title, "10")
        XCTAssertEqual(eval("base 0b1010").first?.title, "10")
        XCTAssertEqual(eval("base zz 36").first?.title, "1295")
        XCTAssertTrue(eval("base ff").isEmpty)       // letters need an explicit base
        XCTAssertTrue(eval("base 12 2").isEmpty)
    }

    func testLorem() {
        XCTAssertEqual(eval("lorem").count, 1)
        XCTAssertTrue(eval("lorem 2").first!.subtitle.contains("2 paragraphs"))
        XCTAssertEqual(eval("lorem 2").first?.copy, Lorem.paragraphs(2).joined(separator: "\n\n"))
        XCTAssertEqual(eval("lorem 5 words").first?.copy, "Lorem ipsum dolor sit amet.")
        XCTAssertEqual(eval("lorem 3 sentences").first?.copy, Lorem.sentences(3))
        XCTAssertTrue(eval("lorem 0").isEmpty)
        XCTAssertTrue(eval("lorem ipsum dolor").isEmpty)
    }

    func testCron() {
        let r = eval("cron */5 * * * *")
        XCTAssertEqual(r[0].title, "Every 5 minutes every day")
        XCTAssertEqual(r[1].title, "Fri 23 Oct 2026, 15:00 GMT")
        XCTAssertEqual(r[1].subtitle, "Run 1 · in 4 minutes")
        XCTAssertEqual(r.count, 6)
        XCTAssertEqual(eval("*/5 * * * *").first?.title, r[0].title) // pasted bare
        XCTAssertEqual(eval("@daily").first?.title, "At 00:00 every day")
        XCTAssertEqual(eval("cron 61 * * * *").first?.subtitle, "Not a valid cron expression")
        XCTAssertTrue(eval("1 2 3 4 5").isEmpty) // five numbers without * or / are just numbers
        XCTAssertEqual(eval("cron 0 0 31 4 *")[1].title, "Never runs")
    }

    func testRegexTyped() {
        let r = eval(#"regex /(\d+)/ a1 b22"#)
        XCTAssertEqual(r[0].title, "2 matches")
        XCTAssertEqual(r[0].copy, "1\n22")
        XCTAssertEqual(r[2].title, "22")
        XCTAssertEqual(r[2].subtitle, "#2 · 4–6 · $1=22")
        XCTAssertEqual(eval("regex /x/ abc").first?.title, "No matches")
        XCTAssertTrue(eval("regex /(/ abc").first!.title.hasPrefix("Invalid pattern"))
        XCTAssertTrue(eval("regex nothing").first!.title.hasPrefix("Usage"))
    }

    func testMessagePack() {
        let all = #"[1,-1,300,-200,70000,-70000,1.5,"hi",null,true,false]"#
        XCTAssertEqual(eval(#"packb {"a":1}"#).first?.title, "81a16101")
        XCTAssertEqual(eval(#"packb {"a":1}"#)[1].title, #"b'\x81\xa1a\x01'"#)
        XCTAssertEqual(eval(#"packb {"a":1}"#)[2].title, "gaFhAQ==")
        let real = #"[0,0,1751093602895,1792671426308,"f037ee3c1f7a4c12",1,1751093602895,0,0]"#
        XCTAssertEqual(eval("packb \(real)")[1].title, #"b"\x99\x00\x00\xcf\x00\x00\x01\x97\xb5O\xeaO\xcf\x00\x00\x01\xa1c\x8b'\x04\xb0f037ee3c1f7a4c12\x01\xcf\x00\x00\x01\x97\xb5O\xeaO\x00\x00""#)
        XCTAssertEqual(eval("packb \(all)").first?.title, "9b01ffcd012cd1ff38ce00011170d2fffeee90cb3ff8000000000000a26869c0c3c2")
        XCTAssertEqual(eval("unpackb 9b01ffcd012cd1ff38ce00011170d2fffeee90cb3ff8000000000000a26869c0c3c2").first?.title,
                       #"[1,-1,300,-200,70000,-70000,1.5,"hi",null,true,false]"#)
        XCTAssertEqual(eval("unpackb 0x81 a1 61 01").first?.title, #"{"a":1}"#)
        XCTAssertEqual(eval(#"unpackb \x81\xa1\x61\x01"#).first?.title, #"{"a":1}"#)
        XCTAssertEqual(eval(#"unpackb b'\x81\xa1a\x01'"#).first?.title, #"{"a":1}"#)   // Python repr: "a" stands for 0x61
        XCTAssertEqual(eval(#"unpackb \x92\xa2\'x\xa1\\"#).first?.title, #"["'x","\\"]"#)
        XCTAssertEqual(eval(#"unpackb \x99\x00\x00\xcf\x00\x00\x01\x97\xb5O\xeaO\xcf\x00\x00\x01\xa1c\x8b'\x04\xb0f037ee3c1f7a4c12\x01\xcf\x00\x00\x01\x97\xb5O\xeaO\x00\x00"#).first?.title,
                       #"[0,0,1751093602895,1792671426308,"f037ee3c1f7a4c12",1,1751093602895,0,0]"#)
        XCTAssertEqual(eval("unpackb gaFhAQ==").first?.title, #"{"a":1}"#)
        XCTAssertEqual(eval("unpackb 81a16101")[1].subtitle, "Pretty-printed · 3 lines")
        XCTAssertEqual(eval("unpackb c40301ff02").first?.title, #""base64:Af8C""#)
        XCTAssertEqual(eval("unpackb ca3dcccccd").first?.title, "0.1")
        XCTAssertEqual(eval("unpackb d401ff").first?.title, #""ext1:ff""#)
        XCTAssertEqual(eval("unpackb 8201020304").first?.title, #"{"1":2,"3":4}"#)   // non-string keys become text
        XCTAssertTrue(eval("unpackb 9201").isEmpty)      // truncated
        XCTAssertTrue(eval("unpackb 0102").isEmpty)      // trailing bytes
        XCTAssertTrue(eval("unpackb c1").isEmpty)        // reserved type byte
        XCTAssertTrue(eval("packb hello").isEmpty)       // not JSON
    }
}
