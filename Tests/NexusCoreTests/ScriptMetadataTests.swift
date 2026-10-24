import XCTest
@testable import NexusCore

final class ScriptMetadataTests: XCTestCase {
    func testFullHeader() {
        let src = """
        #!/bin/bash
        # @nexus.title Say Hello
        # @nexus.description Greets someone
        # @nexus.icon hand.wave
        # @nexus.mode clipboard
        # @nexus.keywords Hi, greet ,
        # @nexus.argument Your name
        echo hi
        """
        let s = ScriptMetadata.parse(src, path: "/x/hello.sh")!
        XCTAssertEqual(s.title, "Say Hello")
        XCTAssertEqual(s.description, "Greets someone")
        XCTAssertEqual(s.icon, "hand.wave")
        XCTAssertEqual(s.mode, .clipboard)
        XCTAssertEqual(s.keywords, ["hi", "greet"])
        XCTAssertEqual(s.argument, "Your name")
        XCTAssertEqual(s.id, "/x/hello.sh")
    }

    func testDefaultsAndOtherCommentStyles() {
        let py = "#!/usr/bin/env python3\n# @nexus.title Py\nprint(1)"
        let s = ScriptMetadata.parse(py, path: "/x/a.py")!
        XCTAssertEqual(s.mode, .output); XCTAssertEqual(s.icon, "terminal"); XCTAssertNil(s.argument); XCTAssertEqual(s.description, "")
        XCTAssertEqual(ScriptMetadata.parse("// @nexus.title JS\n// @nexus.argument\n", path: "a.js")?.argument, "Argument")
        XCTAssertEqual(ScriptMetadata.parse("-- @nexus.title Lua\n", path: "a.lua")?.title, "Lua")
    }

    func testUnknownModeFallsBackToOutput() {
        XCTAssertEqual(ScriptMetadata.parse("# @nexus.title T\n# @nexus.mode explode\n", path: "t")?.mode, .output)
    }

    func testFilesWithoutATitleAreNotCommands() {
        XCTAssertNil(ScriptMetadata.parse("#!/bin/bash\necho nope\n", path: "a.sh"))
        XCTAssertNil(ScriptMetadata.parse("# @nexus.title\n", path: "a.sh"))
        XCTAssertNil(ScriptMetadata.parse("echo '# @nexus.title Not a header'\n", path: "a.sh")) // must be a comment line
    }

    func testOnlyTheTopOfTheFileIsScanned() {
        let src = String(repeating: "echo x\n", count: 50) + "# @nexus.title Too Late\n"
        XCTAssertNil(ScriptMetadata.parse(src, path: "a.sh"))
    }
}
