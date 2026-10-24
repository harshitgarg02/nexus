import Foundation

/// Deterministic lorem ipsum: the same request always gives the same text.
public enum Lorem {
    private static let classic = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
    private static let vocabulary = """
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua \
    enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure in \
    reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt culpa \
    qui officia deserunt mollit anim id est laborum
    """.split(separator: " ").map(String.init)

    public static let maxWords = 2000
    public static let maxParagraphs = 50

    /// n words from the classic opening, then the vocabulary cycled. Starts capitalized, ends with a period.
    public static func words(_ n: Int) -> String {
        let count = max(1, min(n, maxWords))
        let w = (0..<count).map { vocabulary[$0 % vocabulary.count] }
        return w.joined(separator: " ").prefix(1).uppercased() + w.joined(separator: " ").dropFirst() + "."
    }

    public static func sentences(_ n: Int) -> String {
        sentenceList(max(1, min(n, 200)), seed: 1).joined(separator: " ")
    }

    public static func paragraphs(_ n: Int) -> [String] {
        (0..<max(1, min(n, maxParagraphs))).map { i in
            let sentenceCount = 4 + (i * 7 + 3) % 3 // 4...6 sentences
            return sentenceList(sentenceCount, seed: UInt64(i + 1), openWithClassic: i == 0).joined(separator: " ")
        }
    }

    private static func sentenceList(_ count: Int, seed: UInt64, openWithClassic: Bool = true) -> [String] {
        var rng = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        func next(_ bound: Int) -> Int {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17 // xorshift
            return Int(rng % UInt64(bound))
        }
        var out: [String] = []
        for i in 0..<count {
            if i == 0 && openWithClassic && seed <= 1 { out.append(classic); continue }
            let length = 8 + next(9) // 8...16 words
            var w = (0..<length).map { _ in vocabulary[next(vocabulary.count)] }
            if length > 10 { w[length / 2 - 1] += "," }
            out.append(w.joined(separator: " ").prefix(1).uppercased() + w.joined(separator: " ").dropFirst() + ".")
        }
        return out
    }
}
