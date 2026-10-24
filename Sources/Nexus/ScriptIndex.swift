import Foundation
import NexusCore

/// Script commands live in ~/Library/Application Support/Nexus/Scripts. Each file with a `@nexus.title`
/// header becomes a command. Scripts run with your privileges, so only keep files there that you trust.
final class ScriptIndex {
    static let shared = ScriptIndex()

    let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nexus/Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private(set) var scripts: [ScriptInfo] = []
    /// Files that look like scripts but can't be run (no execute permission).
    private(set) var notExecutable = Set<String>()

    func reload() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        var out: [ScriptInfo] = []
        var blocked = Set<String>()
        for url in files {
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard v?.isRegularFile == true, (v?.fileSize ?? 0) < 512_000,
                  let data = try? Data(contentsOf: url), let text = String(data: data.prefix(8192), encoding: .utf8),
                  let info = ScriptMetadata.parse(text, path: url.path) else { continue }
            out.append(info)
            if !fm.isExecutableFile(atPath: url.path) { blocked.insert(url.path) }
        }
        scripts = out.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        notExecutable = blocked
    }

    static let exampleName = "say-hello.sh"
    static let example = """
    #!/bin/bash
    # @nexus.title Say Hello
    # @nexus.description Example script command. Edit it or delete it.
    # @nexus.icon hand.wave
    # @nexus.mode output
    # @nexus.keywords example, hello
    # @nexus.argument Your name
    echo "Hello, ${1:-world}! It is $(date '+%H:%M')."
    """

    /// Writes the example (never overwrites). Returns its URL.
    @discardableResult
    func createExample() -> URL? {
        let url = folder.appendingPathComponent(Self.exampleName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        do {
            try (Self.example + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            reload()
            return url
        } catch { return nil }
    }
}
