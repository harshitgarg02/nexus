import Foundation

/// "uuid", "objectid 3", "password 24", "random 1 100"… → generated values, and the reverse:
/// pasting an ObjectId / UUID v7 / ULID shows the time embedded in it.
enum GeneratorCalc {
    /// One per process, like a real ObjectId generator: the random bytes stay fixed and the counter increments.
    nonisolated(unsafe) static var objectIdState: ObjectIdState = {
        var r = SystemRandomNumberGenerator()
        return ObjectIdState(using: &r)
    }()

    static func rows(_ input: String, now: Date, timeZone: TimeZone) -> [CalcRow]? {
        var rng = SystemRandomNumberGenerator()
        return rows(input, now: now, timeZone: timeZone, rng: &rng, objectIds: &objectIdState)
    }

    static func rows<R: RandomNumberGenerator>(_ input: String, now: Date, timeZone: TimeZone, rng: inout R,
                                               objectIds: inout ObjectIdState) -> [CalcRow]? {
        let text = input.trimmingCharacters(in: .whitespaces)
        if let r = decode(text, now: now, timeZone: timeZone) { return r }

        let t = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let head = t.first else { return nil }
        let args = Array(t.dropFirst())
        func count(_ a: [String], max m: Int = 10) -> Int? {
            if a.isEmpty { return 1 }
            guard a.count == 1, let n = Int(a[0]), n >= 1 else { return nil }
            return min(n, m)
        }
        func gen(_ label: String, _ n: Int, _ make: () -> String) -> [CalcRow] {
            (0..<n).map { _ in let v = make(); return CalcRow(title: v, subtitle: label, generated: true) }
        }

        switch head {
        case "uuid", "guid", "uuid4", "uuidv4":
            var rest = args
            var v7 = false
            if head == "uuid" || head == "guid", let f = rest.first, f == "v7" || f == "v4" { v7 = f == "v7"; rest.removeFirst() }
            guard let n = count(rest) else { return nil }
            if v7 { return gen("UUID v7 (time-ordered)", n) { Generators.uuid7(now: now, &rng) } }
            if n > 1 || !rest.isEmpty { return gen("UUID v4", n) { Generators.uuid4(&rng) } }
            let u = Generators.uuid4(&rng)
            return [CalcRow(title: u, subtitle: "UUID v4", generated: true),
                    CalcRow(title: u.uppercased(), subtitle: "UUID v4 · uppercase", generated: true),
                    CalcRow(title: u.replacingOccurrences(of: "-", with: ""), subtitle: "UUID v4 · no dashes", generated: true),
                    CalcRow(title: Generators.uuid7(now: now, &rng), subtitle: "UUID v7 (time-ordered)", generated: true)]
        case "uuid7", "uuidv7":
            guard let n = count(args) else { return nil }
            return gen("UUID v7 (time-ordered)", n) { Generators.uuid7(now: now, &rng) }
        case "objectid", "oid", "object":
            var a = args
            if head == "object" { guard a.first == "id" else { return nil }; a.removeFirst() }
            guard let n = count(a) else { return nil }
            return gen("MongoDB ObjectId", n) { Generators.objectId(now: now, state: &objectIds) }
        case "ulid":
            guard let n = count(args) else { return nil }
            return gen("ULID", n) { Generators.ulid(now: now, &rng) }
        case "nanoid":
            guard args.count <= 1, let n = args.isEmpty ? 21 : Int(args[0]), n >= 1 else { return nil }
            return gen("nanoid (\(min(n, 128)) chars)", 1) { Generators.nanoid(size: n, &rng) }
        // Words that are also app names ("Passwords", "Hex Fiend") only trigger with an argument,
        // so a bare "hex" still launches the app instead of copying random hex on ↵.
        case "password":
            guard args.count == 1, let n = Int(args[0]), n >= 1 else { return nil }
            let len = max(4, min(n, 128))
            return [CalcRow(title: Generators.password(length: len, &rng), subtitle: "Password (\(len) chars)", generated: true),
                    CalcRow(title: Generators.password(length: len, symbols: false, &rng), subtitle: "Password · letters and digits only", generated: true)]
        case "string":
            guard args.count == 1, let n = Int(args[0]), n >= 1 else { return nil }
            return gen("Random string (\(min(n, 256)))", 1) { Generators.alnum(length: n, &rng) }
        case "hex":
            guard args.count == 1, let n = Int(args[0]), n >= 1 else { return nil }
            return gen("Random hex (\(min(n, 256)))", 1) { Generators.hexString(length: n, &rng) }
        case "random":
            let nums = args.compactMap(Int.init)
            guard !nums.isEmpty, nums.count == args.count, nums.count <= 2 else { return nil }
            let (lo, hi) = nums.count == 2 ? (nums[0], nums[1]) : (1, nums[0])
            return gen("Random number (\(min(lo, hi))–\(max(lo, hi)))", 1) { String(Generators.number(lo, hi, &rng)) }
        default:
            return nil
        }
    }

    private static func decode(_ s: String, now: Date, timeZone: TimeZone) -> [CalcRow]? {
        if let secs = Generators.objectIdSeconds(s) {
            return EpochCalc.rows(micros: Int64(secs) * 1_000_000, precise: false, timeZone: timeZone, now: now)
        }
        if let ms = Generators.uuid7Milliseconds(s) ?? Generators.ulidMilliseconds(s), ms / 1000 <= 4_102_444_800 {
            return EpochCalc.rows(micros: Int64(ms) * 1000, precise: ms % 1000 != 0, timeZone: timeZone, now: now)
        }
        return nil
    }
}
