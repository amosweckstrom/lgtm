import XCTest
@testable import LGTM

/// Pins the total invocation resolver: `resolvedInvocation` must always yield a
/// runnable command, compensating for the one nil case `invocation` exposes.
final class AgentsTests: XCTestCase {

    // A known id resolves to its configured command.
    func testResolvedInvocationForKnownID() {
        XCTAssertEqual(
            Agents.resolvedInvocation(for: "gemini", customCommand: ""),
            "gemini -i")
    }

    // Custom selected but blank falls back to the default agent's command.
    func testResolvedInvocationForBlankCustomFallsBackToDefault() {
        XCTAssertEqual(
            Agents.resolvedInvocation(for: "custom", customCommand: ""),
            "claude")
    }

    // Custom with a non-blank command is trimmed of surrounding whitespace.
    func testResolvedInvocationForCustomTrimsWhitespace() {
        XCTAssertEqual(
            Agents.resolvedInvocation(for: "custom", customCommand: "  aider --message  "),
            "aider --message")
    }

    // An unknown id falls back to the default command.
    func testResolvedInvocationForUnknownIDFallsBackToDefault() {
        XCTAssertEqual(
            Agents.resolvedInvocation(for: "nope-not-an-agent", customCommand: ""),
            "claude")
    }

    // The one nil case the resolver compensates for: custom selected but blank.
    func testInvocationReturnsNilForBlankCustom() {
        XCTAssertNil(Agents.invocation(for: "custom", customCommand: ""))
    }
}
