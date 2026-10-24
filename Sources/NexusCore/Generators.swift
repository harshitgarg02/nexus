import Foundation

/// Per-process state for MongoDB ObjectIds: a 5-byte random value and a 3-byte counter that starts random.
public struct ObjectIdState {
    var processRandom: [UInt8]
    var counter: UInt32

    public init<R: RandomNumberGenerator>(using rng: inout R) {
        processRandom = Generators.randomBytes(5, &rng)
        counter = UInt32.random(in: 0...0xFF_FFFF, using: &rng)
    }
}

/// Developer id/token generators. All take an explicit RNG so tests can be deterministic;
/// the app uses the system's cryptographically secure generator.
public enum Generators {
    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let nanoAlphabet = Array("useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict")
    static let lower = Array("abcdefghijklmnopqrstuvwxyz")
    static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let digits = Array("0123456789")
    static let symbols = Array("!@#$%^&*-_=+?")

    public static func randomBytes<R: RandomNumberGenerator>(_ n: Int, _ rng: inout R) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(UInt8.random(in: 0...255, using: &rng)) }
        return out
    }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    // MARK: UUID

    private static func format(uuid b: [UInt8]) -> String {
        let h = hex(b)
        let i = h.startIndex
        func s(_ a: Int, _ z: Int) -> String { String(h[h.index(i, offsetBy: a)..<h.index(i, offsetBy: z)]) }
        return [s(0, 8), s(8, 12), s(12, 16), s(16, 20), s(20, 32)].joined(separator: "-")
    }

    /// Random UUID (RFC 9562 v4).
    public static func uuid4<R: RandomNumberGenerator>(_ rng: inout R) -> String {
        var b = randomBytes(16, &rng)
        b[6] = (b[6] & 0x0f) | 0x40
        b[8] = (b[8] & 0x3f) | 0x80
        return format(uuid: b)
    }

    /// Time-ordered UUID (RFC 9562 v7): 48-bit Unix milliseconds, then random bits.
    public static func uuid7<R: RandomNumberGenerator>(now: Date, _ rng: inout R) -> String {
        let ms = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        var b = (0..<6).map { UInt8((ms >> UInt64(8 * (5 - $0))) & 0xff) } + randomBytes(10, &rng)
        b[6] = (b[6] & 0x0f) | 0x70
        b[8] = (b[8] & 0x3f) | 0x80
        return format(uuid: b)
    }

    // MARK: ObjectId

    /// MongoDB ObjectId: 4-byte timestamp, 5-byte per-process random, 3-byte counter.
    public static func objectId(now: Date, state: inout ObjectIdState) -> String {
        let secs = UInt32(max(0, now.timeIntervalSince1970))
        state.counter = (state.counter &+ 1) & 0xFF_FFFF
        let t = (0..<4).map { UInt8((secs >> UInt32(8 * (3 - $0))) & 0xff) }
        let c = (0..<3).map { UInt8((state.counter >> UInt32(8 * (2 - $0))) & 0xff) }
        return hex(t + state.processRandom + c)
    }

    // MARK: ULID

    /// Crockford base32: 48-bit millisecond timestamp (10 chars) + 80 random bits (16 chars).
    public static func ulid<R: RandomNumberGenerator>(now: Date, _ rng: inout R) -> String {
        var ms = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        var time = [Character](repeating: "0", count: 10)
        for i in stride(from: 9, through: 0, by: -1) { time[i] = crockford[Int(ms & 31)]; ms >>= 5 }
        var bits = 0, acc: UInt32 = 0
        var rand = ""
        for byte in randomBytes(10, &rng) {
            acc = (acc << 8) | UInt32(byte); bits += 8
            while bits >= 5 { bits -= 5; rand.append(crockford[Int((acc >> UInt32(bits)) & 31)]) }
        }
        return String(time) + rand
    }

    // MARK: others

    public static func nanoid<R: RandomNumberGenerator>(size: Int = 21, _ rng: inout R) -> String {
        String(randomBytes(max(1, min(size, 128)), &rng).map { nanoAlphabet[Int($0 & 63)] })
    }

    public static func hexString<R: RandomNumberGenerator>(length: Int, _ rng: inout R) -> String {
        let n = max(1, min(length, 256))
        return String(hex(randomBytes((n + 1) / 2, &rng)).prefix(n))
    }

    public static func alnum<R: RandomNumberGenerator>(length: Int, _ rng: inout R) -> String {
        let set = lower + upper + digits
        return String((0..<max(1, min(length, 256))).map { _ in set[Int.random(in: 0..<set.count, using: &rng)] })
    }

    /// Always includes a lowercase, uppercase and digit (and a symbol when asked), then shuffles.
    public static func password<R: RandomNumberGenerator>(length: Int, symbols withSymbols: Bool = true, _ rng: inout R) -> String {
        let n = max(4, min(length, 128))
        var sets = [lower, upper, digits]
        if withSymbols { sets.append(symbols) }
        let all = sets.flatMap { $0 }
        var chars = sets.map { $0[Int.random(in: 0..<$0.count, using: &rng)] }
        while chars.count < n { chars.append(all[Int.random(in: 0..<all.count, using: &rng)]) }
        chars.shuffle(using: &rng)
        return String(chars)
    }

    public static func number<R: RandomNumberGenerator>(_ a: Int, _ b: Int, _ rng: inout R) -> Int {
        Int.random(in: min(a, b)...max(a, b), using: &rng)
    }

    // MARK: decoders (the reverse direction: id → embedded time)

    /// ObjectId → Unix seconds. Nil unless 24 hex chars with a plausible date (2009…2100).
    public static func objectIdSeconds(_ s: String) -> Int? {
        guard s.count == 24, s.allSatisfy(\.isHexDigit), let secs = UInt32(s.prefix(8), radix: 16) else { return nil }
        return (1_230_768_000...4_102_444_800).contains(Int(secs)) ? Int(secs) : nil
    }

    /// UUID v7 → Unix milliseconds.
    public static func uuid7Milliseconds(_ s: String) -> UInt64? {
        let c = Array(s.lowercased())
        guard c.count == 36, c[8] == "-", c[13] == "-", c[18] == "-", c[23] == "-", c[14] == "7" else { return nil }
        let hexPart = String(c[0..<8]) + String(c[9..<13])
        guard hexPart.allSatisfy(\.isHexDigit), let ms = UInt64(hexPart, radix: 16) else { return nil }
        return ms
    }

    /// ULID → Unix milliseconds. Nil if not 26 valid Crockford chars or the timestamp would overflow 48 bits.
    public static func ulidMilliseconds(_ s: String) -> UInt64? {
        let c = Array(s.uppercased())
        guard c.count == 26, c.allSatisfy({ crockford.contains($0) }), c[0] <= "7" else { return nil }
        var ms: UInt64 = 0
        for ch in c[0..<10] { ms = ms << 5 | UInt64(crockford.firstIndex(of: ch)!) }
        return ms
    }
}
