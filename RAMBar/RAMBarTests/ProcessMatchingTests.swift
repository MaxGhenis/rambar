import XCTest
@testable import RAMBarLib

final class ProcessMatchingTests: XCTestCase {

    // MARK: - Pattern matching

    func testClaudeCliMatchesClaude() {
        XCTAssertTrue(
            matchesAppPattern("claude --dangerously-skip-permissions", pattern: "^claude"),
            "Actual claude CLI should match"
        )
    }

    func testClaudeDesktopAppDoesNotMatch() {
        // macOS ps shows full path for .app bundles
        XCTAssertFalse(
            matchesAppPattern("/Applications/Claude.app/Contents/MacOS/Claude", pattern: "^claude"),
            "Claude desktop app (full path) should not match prefix pattern"
        )
    }

    func testNodeMcpServerWithClaudePathDoesNotMatchClaude() {
        let cmd = "/usr/local/bin/node /Users/max/.claude/mcp-servers/some-server/index.js"
        XCTAssertFalse(
            matchesAppPattern(cmd, pattern: "^claude"),
            "Node MCP server with .claude/ in path should NOT match Claude Code"
        )
    }

    func testNodeWorkerWithClaudeInPathDoesNotMatchClaude() {
        let cmd = "/opt/homebrew/bin/node /Users/max/.claude/local/agent-tool-runner.mjs"
        XCTAssertFalse(
            matchesAppPattern(cmd, pattern: "^claude"),
            "Node worker spawned by claude should NOT match Claude Code"
        )
    }

    func testContainsPatternStillWorksForChrome() {
        let cmd = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        XCTAssertTrue(
            matchesAppPattern(cmd, pattern: "Google Chrome"),
            "Contains-based pattern should still work for Chrome"
        )
    }

    func testContainsPatternStillWorksForSlack() {
        let cmd = "/Applications/Slack.app/Contents/MacOS/Slack Helper (Renderer)"
        XCTAssertTrue(
            matchesAppPattern(cmd, pattern: "Slack"),
            "Contains-based pattern should still work for Slack"
        )
    }

    func testGranolaPatternMatches() {
        let cmd = "/Applications/Granola.app/Contents/Frameworks/Granola Helper (Renderer).app/Contents/MacOS/Granola Helper (Renderer)"
        XCTAssertTrue(
            matchesAppPattern(cmd, pattern: "Granola"),
            "Granola should match its pattern"
        )
    }

    // MARK: - App categorization

    func testCategorizeProcesses_ClaudeNotOvercounted() {
        let processes: [TestProcess] = [
            TestProcess(command: "claude --dangerously-skip-permissions", memory: 1_600_000_000),
            TestProcess(command: "claude --dangerously-skip-permissions --dangerously-skip-permissions", memory: 800_000_000),
            TestProcess(command: "/opt/homebrew/bin/node /Users/max/.claude/mcp-servers/voice-mode/server.js", memory: 60_000_000),
            TestProcess(command: "/opt/homebrew/bin/node /Users/max/.claude/local/agent-tool-runner.mjs", memory: 120_000_000),
        ]

        let result = categorizeProcesses(processes, patterns: defaultAppPatterns)

        let claudeEntry = result.first { $0.name == "Claude Code" }
        let nodeEntry = result.first { $0.name == "Node.js" }

        XCTAssertNotNil(claudeEntry, "Should have Claude Code entry")
        XCTAssertEqual(claudeEntry?.processCount, 2, "Only 2 actual claude CLI processes")
        XCTAssertEqual(claudeEntry?.memory, 2_400_000_000, "Memory should be sum of 2 CLI processes only")

        XCTAssertNotNil(nodeEntry, "Node workers should be categorized as Node.js")
        XCTAssertEqual(nodeEntry?.processCount, 2, "2 node worker processes")
    }

    func testCategorizeProcesses_GranolaNotMissing() {
        let processes: [TestProcess] = [
            TestProcess(command: "/Applications/Granola.app/Contents/MacOS/Granola", memory: 200_000_000),
            TestProcess(command: "/Applications/Granola.app/Contents/Frameworks/Granola Helper (Renderer).app/Contents/MacOS/Granola Helper (Renderer)", memory: 500_000_000),
        ]

        let result = categorizeProcesses(processes, patterns: defaultAppPatterns)

        let granolaEntry = result.first { $0.name == "Granola" }
        XCTAssertNotNil(granolaEntry, "Granola should appear as its own category")
        XCTAssertEqual(granolaEntry?.processCount, 2)
        XCTAssertEqual(granolaEntry?.memory, 700_000_000)
    }

    func testCategorizeProcesses_GranolaNotInOther() {
        let processes: [TestProcess] = [
            TestProcess(command: "/Applications/Granola.app/Contents/Frameworks/Granola Helper (Renderer).app/Contents/MacOS/Granola Helper (Renderer)", memory: 8_000_000_000),
        ]

        let result = categorizeProcesses(processes, patterns: defaultAppPatterns)

        let otherEntry = result.first { $0.name == "Other" }
        XCTAssertNil(otherEntry, "Granola should NOT end up in Other")
    }

    // MARK: - Claude session detection

    func testFilterClaudeSessions_OnlyCliProcesses() {
        let processes: [TestProcess] = [
            TestProcess(pid: 100, command: "claude --dangerously-skip-permissions", memory: 1_600_000_000),
            TestProcess(pid: 101, command: "claude --dangerously-skip-permissions --dangerously-skip-permissions", memory: 800_000_000),
            TestProcess(pid: 102, command: "/opt/homebrew/bin/node /Users/max/.claude/mcp-servers/voice-mode/server.js", memory: 60_000_000),
            TestProcess(pid: 103, command: "/opt/homebrew/bin/node /Users/max/.claude/local/agent-tool-runner.mjs", memory: 120_000_000),
        ]

        let sessions = filterClaudeSessions(processes)

        XCTAssertEqual(sessions.count, 2, "Only actual claude CLI processes should be sessions")
        XCTAssertTrue(sessions.allSatisfy { $0.command.hasPrefix("claude") })
    }
}
