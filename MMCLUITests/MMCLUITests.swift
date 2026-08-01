//
//  MMCLUITests.swift
//  MMCLUITests
//
//  Created by 星音 on 2026/5/27.
//

import XCTest

final class MMCLUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesInForeground() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--mmcl-ui-testing")
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
