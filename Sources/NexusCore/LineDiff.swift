import Foundation

public enum DiffKind: Equatable { case same, added, removed }

public struct DiffLine: Equatable {
    public let kind: DiffKind
    public let text: String
}

/// One row of a collapsed diff: a line, or a run of unchanged lines that was folded away.
public enum DiffRow: Equatable {
    case line(DiffLine)
    case skipped(Int)
}

public enum LineDiff {
    /// Above this many cells in the comparison table we give up rather than freeze the launcher.
    static let maxCells = 16_000_000

    static func lines(_ s: String) -> [String] {
        var l = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if l.last == "" { l.removeLast() } // a trailing newline isn't an extra empty line
        return l
    }

    /// Line diff from `old` to `new` (longest common subsequence, after trimming the shared head and tail).
    public static func diff(_ old: String, _ new: String) -> Result<[DiffLine], TransformError> {
        let a = lines(old), b = lines(new)
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head, tail < b.count - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let ma = Array(a[head..<(a.count - tail)]), mb = Array(b[head..<(b.count - tail)])
        let (n, m) = (ma.count, mb.count)
        guard (n + 1) * (m + 1) <= maxCells else { return .failure(.invalid("These texts are too large and too different to compare.")) }

        var out = a[..<head].map { DiffLine(kind: .same, text: $0) }
        if n == 0 { out += mb.map { DiffLine(kind: .added, text: $0) } }
        else if m == 0 { out += ma.map { DiffLine(kind: .removed, text: $0) } }
        else {
            // table[i][j] = length of the LCS of ma[i...] and mb[j...]
            var t = [Int32](repeating: 0, count: (n + 1) * (m + 1))
            let w = m + 1
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    t[i * w + j] = ma[i] == mb[j] ? t[(i + 1) * w + j + 1] + 1 : max(t[(i + 1) * w + j], t[i * w + j + 1])
                }
            }
            var i = 0, j = 0
            while i < n || j < m {
                if i < n, j < m, ma[i] == mb[j] { out.append(DiffLine(kind: .same, text: ma[i])); i += 1; j += 1 }
                else if i < n, j == m || t[(i + 1) * w + j] >= t[i * w + j + 1] { out.append(DiffLine(kind: .removed, text: ma[i])); i += 1 } // removals before additions, like diff(1)
                else { out.append(DiffLine(kind: .added, text: mb[j])); j += 1 }
            }
        }
        out += a[(a.count - tail)...].map { DiffLine(kind: .same, text: $0) }
        return .success(out)
    }

    public static func stats(_ d: [DiffLine]) -> (added: Int, removed: Int) {
        (d.filter { $0.kind == .added }.count, d.filter { $0.kind == .removed }.count)
    }

    /// Folds unchanged runs, keeping `context` lines around each change (like `diff -U3`).
    public static func rows(_ d: [DiffLine], context: Int = 3) -> [DiffRow] {
        var keep = [Bool](repeating: false, count: d.count)
        for (i, l) in d.enumerated() where l.kind != .same {
            for k in max(0, i - context)...min(d.count - 1, i + context) { keep[k] = true }
        }
        var out: [DiffRow] = []
        var skipped = 0
        for (i, l) in d.enumerated() {
            if keep[i] {
                if skipped > 0 { out.append(.skipped(skipped)); skipped = 0 }
                out.append(.line(l))
            } else { skipped += 1 }
        }
        if skipped > 0 { out.append(.skipped(skipped)) }
        return out
    }

    /// Plain "+ / - / space" text, for copying.
    public static func unified(_ d: [DiffLine], context: Int = 3) -> String {
        rows(d, context: context).map { r -> String in
            switch r {
            case .skipped(let n): return "@@ \(n) unchanged line\(n == 1 ? "" : "s") @@"
            case .line(let l): return (l.kind == .added ? "+ " : l.kind == .removed ? "- " : "  ") + l.text
            }
        }.joined(separator: "\n")
    }
}
