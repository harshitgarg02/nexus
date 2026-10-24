import AppKit
import os

/// Hotkey → overlay drawn. Measured CPU-side: from the hotkey handler to the end of a forced layout + display.
/// (Window-server compositing adds a few ms on top.) Also emits an os_signpost interval for Instruments.
enum LatencyMeter {
    private static let signposter = OSSignposter(subsystem: AppIdentity.bundleID, category: "latency")
    private static var t0: CFTimeInterval = 0
    private static var state: OSSignpostIntervalState?
    private(set) static var samples: [Double] = []
    private static var currentLaps: [(String, Double)] = []
    /// Phase breakdown of the most recent completed open: (name, ms since hotkey).
    private(set) static var lastLaps: [(String, Double)] = []

    static func lap(_ name: String) {
        guard t0 > 0 else { return }
        currentLaps.append((name, (CACurrentMediaTime() - t0) * 1000))
    }

    static func begin() {
        currentLaps = []
        t0 = CACurrentMediaTime()
        state = signposter.beginInterval("open")
    }

    static var isRunning: Bool { t0 > 0 }

    static func cancel() { t0 = 0; state = nil }

    static func end() {
        guard t0 > 0 else { return }
        samples.append((CACurrentMediaTime() - t0) * 1000)
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
        lastLaps = currentLaps
        if let s = state { signposter.endInterval("open", s) }
        t0 = 0; state = nil
    }

    static func reset() { samples.removeAll() }

    struct Stats { let count: Int; let last: Double; let mean: Double; let p95: Double; let max: Double }

    static func stats(_ s: [Double]? = nil) -> Stats? {
        let v = s ?? samples
        guard !v.isEmpty else { return nil }
        let sorted = v.sorted()
        return Stats(count: v.count, last: v.last!, mean: v.reduce(0, +) / Double(v.count),
                     p95: sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], max: sorted.last!)
    }
}
