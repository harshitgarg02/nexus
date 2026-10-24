import Foundation

struct ScriptOutcome {
    var stdout = ""
    var stderr = ""
    var status: Int32 = 0
    var timedOut = false
    var launchError: String?

    var succeeded: Bool { status == 0 && !timedOut && launchError == nil }
    /// stdout without the trailing newline most scripts print.
    var text: String { stdout.hasSuffix("\n") ? String(stdout.dropLast()) : stdout }
}

enum ScriptRunner {
    static let timeout: TimeInterval = 30
    private static let maxBytes = 1_000_000

    /// Runs the script file directly (it needs its shebang and execute permission). The GUI PATH is minimal,
    /// so common tool locations are added. The argument, if any, is passed as `$1`.
    static func run(_ path: String, argument: String?, completion: @escaping (ScriptOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var out = ScriptOutcome()
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = argument.map { [$0] } ?? []
            p.currentDirectoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
            p.environment = env
            let outPipe = Pipe(), errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch {
                out.launchError = FileManager.default.isExecutableFile(atPath: path)
                    ? error.localizedDescription
                    : "Not executable. Run: chmod +x \"\(path)\""
                DispatchQueue.main.async { completion(out) }
                return
            }
            let timer = DispatchWorkItem { out.timedOut = true; p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

            let group = DispatchGroup()
            var errData = Data()
            group.enter()
            DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            p.waitUntilExit()
            timer.cancel()

            out.status = p.terminationStatus
            out.stdout = String(decoding: outData.prefix(maxBytes), as: UTF8.self)
            out.stderr = String(decoding: errData.prefix(maxBytes), as: UTF8.self)
            DispatchQueue.main.async { completion(out) }
        }
    }
}
