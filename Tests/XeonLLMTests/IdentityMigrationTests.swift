// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs (fork of ToshLLM)
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import Security
@testable import XeonLLM

/// Exercises the one-time migration from ToshLLM (dev.engel.toshllm) to XeonLLM
/// (dev.xeonllm.app) against a throwaway UserDefaults suite, a temp support
/// directory, and no Keychain access. The old data is never deleted.
final class IdentityMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var supportDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "xeonllm-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        supportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeonllm-support-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: supportDir)
        super.tearDown()
    }

    /// Place an old-app data folder with a marker file inside the support dir.
    private func makeOldDataFolder(_ name: String = "ToshLLM") -> URL {
        let old = supportDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: old.appendingPathComponent("marker.txt").path,
                                       contents: Data("old".utf8))
        return old
    }

    func testCopiesSettingsAndDataFolder() throws {
        let old = makeOldDataFolder()
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["theme": "dark", "modelsDir": "/tmp/models"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(defaults.string(forKey: "theme"), "dark")
        XCTAssertEqual(defaults.string(forKey: "modelsDir"), "/tmp/models")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: supportDir.appendingPathComponent("XeonLLM/marker.txt").path))
        // The old data is never deleted.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: old.appendingPathComponent("marker.txt").path))
        XCTAssertTrue(try XCTUnwrap(defaults.bool(forKey: IdentityMigration.markerKey) as Bool?))
    }

    func testDoesNotOverwriteAnExistingSetting() throws {
        _ = makeOldDataFolder()
        defaults.set("already-set", forKey: "theme")
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["theme": "from-old"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)
        // A value the new app already has is never replaced by the old one.
        XCTAssertEqual(defaults.string(forKey: "theme"), "already-set")
    }

    func testDoesNotTouchAnExistingNewDataFolder() throws {
        _ = makeOldDataFolder()
        let newFolder = supportDir.appendingPathComponent("XeonLLM", isDirectory: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: newFolder.appendingPathComponent("mine.txt").path,
                                       contents: Data("new".utf8))
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["k": "v"], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        // The pre-existing new folder keeps its own content unchanged.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: newFolder.appendingPathComponent("mine.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: newFolder.appendingPathComponent("marker.txt").path))
    }

    func testNeverDeletesTheOldDataFolder() throws {
        let old = makeOldDataFolder()
        IdentityMigration.run(defaults: defaults,
                              oldDomain: [:], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: old.appendingPathComponent("marker.txt").path))
    }

    func testASecondRunCopiesNothing() throws {
        _ = makeOldDataFolder()
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["first": "1"], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(defaults.string(forKey: "first"), "1")
        // A second run with different old data is a no-op: the marker guards it.
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["second": "2"], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(defaults.string(forKey: "second"), nil)
        XCTAssertEqual(defaults.string(forKey: "first"), "1")
    }

    func testSkipsSystemStateKeys() throws {
        _ = makeOldDataFolder()
        // NS* keys hold window frames; Apple* keys are system state. Neither travels.
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["NSWindowFrame": "{0,0,100,100}",
                                          "AppleLocaleUserDictionary": ["en"],
                                          "aRealSetting": "kept"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)
        XCTAssertNil(defaults.object(forKey: "NSWindowFrame"))
        XCTAssertNil(defaults.object(forKey: "AppleLocaleUserDictionary"))
        XCTAssertEqual(defaults.string(forKey: "aRealSetting"), "kept")
    }

    func testKeychainItemsAreCopiedNotMovedOrOverwritten() throws {
        let old = "xeonllm-test-old-\(UUID().uuidString)", new = "xeonllm-test-new-\(UUID().uuidString)"
        func add(_ service: String, _ account: String, _ value: String) {
            let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                       kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
            XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        }
        func read(_ service: String, _ account: String) -> String? {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
            var r: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        defer {
            for service in [old, new] {
                SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
            }
        }
        add(old, "a", "old-a"); add(old, "b", "old-b"); add(new, "b", "new-b")
        IdentityMigration.copyKeychainItems(oldService: old, newService: new)
        XCTAssertEqual(read(new, "a"), "old-a")
        XCTAssertEqual(read(new, "b"), "new-b")
        XCTAssertEqual(read(old, "a"), "old-a")
    }
}
