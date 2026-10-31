// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// A bundle without the identity keys of make-app.sh is plain XeonLLM, so its data, logs,
/// Keychain entries and updates stay where they always were.
final class AppIdentityTests: XCTestCase {
    func testABundleWithoutIdentityKeysIsXeonLLM() {
        XCTAssertEqual(AppInfo.name, "XeonLLM")
        XCTAssertEqual(AppInfo.identifier, "dev.xeonllm.app")
        XCTAssertEqual(AppInfo.dataFolder, "XeonLLM")
        XCTAssertEqual(AppInfo.productVersion, AppInfo.version)
        XCTAssertTrue(AppInfo.updatesEnabled)
        XCTAssertFalse(AppInfo.isRebranded)
        XCTAssertEqual(AppInfo.branded("Welcome to XeonLLM"), "Welcome to XeonLLM")
        XCTAssertEqual(AppSupport.directory.lastPathComponent, "XeonLLM")
    }
}
