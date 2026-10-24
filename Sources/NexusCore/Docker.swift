import Foundation

public struct DockerContainer: Identifiable, Equatable {
    public let id: String        // short container ID
    public let name: String
    public let image: String
    public let state: String     // running, exited, paused, created, restarting…
    public let status: String    // "Up 2 hours", "Exited (0) 3 days ago"
    public let ports: String
    /// First published host port, e.g. 8080 for "0.0.0.0:8080->80/tcp".
    public let hostPort: Int?

    public var isRunning: Bool { state == "running" }
}

public enum DockerCLI {
    /// Where a docker CLI usually lives (Docker Desktop, Homebrew, OrbStack, system).
    public static func locate(home: String = NSHomeDirectory(), fileManager fm: FileManager = .default) -> String? {
        [home + "/.orbstack/bin/docker", "/usr/local/bin/docker", "/opt/homebrew/bin/docker",
         "/Applications/Docker.app/Contents/Resources/bin/docker", "/usr/bin/docker"].first { fm.isExecutableFile(atPath: $0) }
    }

    /// Output of `docker ps -a --format '{{json .}}'`: one JSON object per line. Running containers first, then by name.
    public static func parsePS(_ output: String) -> [DockerContainer] {
        let port = try! NSRegularExpression(pattern: #":(\d+)->"#)
        return output.split(separator: "\n").compactMap { line -> DockerContainer? in
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let id = obj["ID"] as? String else { return nil }
            let ports = obj["Ports"] as? String ?? ""
            let hostPort = port.firstMatch(in: ports, range: NSRange(ports.startIndex..., in: ports))
                .flatMap { Range($0.range(at: 1), in: ports) }.flatMap { Int(ports[$0]) }
            return DockerContainer(id: id, name: (obj["Names"] as? String ?? "").split(separator: ",").first.map(String.init) ?? id,
                                   image: obj["Image"] as? String ?? "", state: obj["State"] as? String ?? "",
                                   status: obj["Status"] as? String ?? "", ports: ports, hostPort: hostPort)
        }
        .sorted { a, b in
            a.isRunning != b.isRunning ? a.isRunning : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
