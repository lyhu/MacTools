import XCTest

@testable import AIAssistantPlugin

@MainActor
final class AIAssistantBrowserAppleScriptSelectedTextCaptureTests: XCTestCase {
    private struct DelayedExecutor: BrowserAppleScriptExecuting {
        func execute(_ script: String) async throws -> String? {
            try await Task.sleep(nanoseconds: 300_000_000)
            return "selected browser text"
        }
    }

    func testBrowserSelectionCompletesAfterNormalAutomationDelay() async {
        let capture = BrowserAppleScriptSelectedTextCapture(executor: DelayedExecutor())
        let result = await capture.capture(context: SelectedTextCaptureContext(
            frontmostApplicationBundleID: "com.google.Chrome"
        ))

        XCTAssertEqual(result.text, "selected browser text")
        XCTAssertEqual(result.strategyID, .browserAppleScript)
        XCTAssertFalse(result.requiresUserConfirmation)
    }
}
