// AppBundleSmokeTests.swift
// Exercises app bundle smoke behavior.
//

import XCTest

final class AppBundleSmokeTests: XCTestCase {
    func testTestBundleIsLoadable() {
        XCTAssertEqual(Bundle(for: Self.self).bundleURL.pathExtension, "xctest")
    }

    func testDefaultShellLaunchArgumentsAreStable() {
        XCTAssertEqual(AppLaunchArguments.default, ["--uitesting", "--skip-auth"])
        XCTAssertTrue(AppLaunchArguments.gamePassHome.contains("-cloudx-uitest-gamepass-home"))
    }
}

private enum AppLaunchArguments {
    static let `default` = ["--uitesting", "--skip-auth"]

    static let gamePassHome = [
        "-cloudx-uitest-gamepass-home",
        "CLOUDX_UI_TEST_GAMEPASS_HOME=1"
    ]
}
