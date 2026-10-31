// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs (fork of ToshLLM)
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// One-time migration from ToshLLM (dev.engel.toshllm) to XeonLLM (dev.xeonllm.app).
/// Copies settings, data folders and keychain items once; never deletes the old data.
enum IdentityMigration {
    /// The bundle identifier ToshLLM used.
    static let oldIdentifier = "dev.engel.toshllm"
    
    /// The data folder name ToshLLM used.
    static let oldDataFolder = "ToshLLM"
    
    /// Marker key in UserDefaults indicating migration has been performed.
    static let markerKey = "migratedFromToshLLM"
    
    /// Run the one-time migration from ToshLLM to the current identity.
    ///
    /// - Parameters:
    ///   - defaults: UserDefaults instance to write the marker to (defaults to .standard).
    ///   - oldDomain: Optional preset value for UserDefaults(suiteName: oldIdentifier). If nil, read now.
    ///   - supportDir: Application Support base directory.
    ///   - newDataFolder: Target data folder name (from AppInfo.dataFolder).
    ///   - keychain: Whether to migrate keychain items (set false for tests).
    static func run(defaults: UserDefaults = .standard,
                    oldDomain: [String: Any]? = UserDefaults.standard.persistentDomain(forName: oldIdentifier),
                    supportDir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
                    newDataFolder: String = AppInfo.dataFolder,
                    keychain: Bool = true) {
        
        // Early return if already migrated or still using old identifier
        guard !defaults.bool(forKey: markerKey) else { return }
        guard AppInfo.identifier != oldIdentifier else { return }
        guard !AppInfo.isRebranded else { return } // Another product built from this tree
        
        let fm = FileManager.default
        
        // === Settings migration ===
        if let oldDomain = oldDomain {
            var copiedCount = 0
            for (key, value) in oldDomain where
                !key.hasPrefix("NS") &&
                !key.hasPrefix("Apple") &&
                defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
                copiedCount += 1
            }
            if copiedCount > 0 {
                AppLog.app.info("Migrated \(copiedCount) UserDefaults entries from \(oldIdentifier)")
            }
        }
        
        // === Data folder migration ===
        let oldPath = supportDir.appendingPathComponent(oldDataFolder)
        let newPath = supportDir.appendingPathComponent(newDataFolder)
        
        if fm.fileExists(atPath: oldPath.path) && !fm.fileExists(atPath: newPath.path) {
            do {
                try fm.copyItem(at: oldPath, to: newPath)
                AppLog.app.info("Copied data folder \(oldDataFolder) → \(newDataFolder)")
            } catch {
                AppLog.app.error("Could not copy data folder: \(error.localizedDescription)")
            }
        }
        
        // === Keychain migration ===
        if keychain {
            copyKeychainItems(oldService: oldIdentifier, newService: AppInfo.identifier)
        }
        
        // Set migration marker
        defaults.set(true, forKey: markerKey)
    }
    
    static func copyKeychainItems(oldService: String, newService: String) {
        // the file keychain rejects kSecMatchLimitAll with kSecReturnData, so list the accounts first
        for account in keychainAccounts(service: oldService) where keychainData(service: newService, account: account) == nil {
            guard let data = keychainData(service: oldService, account: account) else { continue }
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: newService,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
            ]
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess {
                AppLog.app.info("Copied keychain item for account '\(account)'")
            }
        }
    }

    private static func keychainAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private static func keychainData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
