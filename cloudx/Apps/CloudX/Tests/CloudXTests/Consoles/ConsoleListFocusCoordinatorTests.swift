// ConsoleListFocusCoordinatorTests.swift
// Exercises console list focus coordinator behavior.
//

import XCTest

#if canImport(CloudX)
@testable import CloudX
#endif

final class ConsoleListFocusCoordinatorTests: XCTestCase {
    func testPreferredTarget_usesLastFocusedConsoleWhenPresent() {
        XCTAssertEqual(
            ConsoleListFocusCoordinator.preferredTarget(
                isLoading: false,
                consoleIDs: ["console-a", "console-b"],
                lastFocusedConsoleID: "console-b"
            ),
            .console("console-b")
        )
    }

    func testPreferredTarget_fallsBackToRefreshWhenNoConsolesExist() {
        XCTAssertEqual(
            ConsoleListFocusCoordinator.preferredTarget(
                isLoading: false,
                consoleIDs: [],
                lastFocusedConsoleID: nil
            ),
            .refresh
        )
    }
}
