import Foundation

public struct ListeningPort: Equatable, Identifiable {
    public let port: Int
    public let pid: Int32
    public let name: String
    public let uid: UInt32
    public var id: String { "\(port)-\(pid)" }
}

public enum PortScanner {
    /// Parses `lsof -nP +c 0 -iTCP -sTCP:LISTEN -F pcun` output. The row number is the **port**; the PID is the
    /// listening process (only shown in the kill actions). IPv4/IPv6 duplicates collapse; sorted by port.
    public static func parse(_ output: String) -> [ListeningPort] {
        var out: [ListeningPort] = []
        var seen = Set<String>()
        var pid: Int32?, name = "", uid: UInt32 = 0
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p": pid = Int32(value); name = ""; uid = 0
            case "c": name = String(value)
            case "u": uid = UInt32(value) ?? 0
            case "n":
                guard let pid, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                let p = ListeningPort(port: port, pid: pid, name: name, uid: uid)
                if seen.insert(p.id).inserted { out.append(p) }
            default: break
            }
        }
        return out.sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
    }

    /// Runs lsof (a few tens of ms). Empty on failure.
    public static func scan() -> [ListeningPort] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "+c", "0", "-iTCP", "-sTCP:LISTEN", "-F", "pcun"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }
}
