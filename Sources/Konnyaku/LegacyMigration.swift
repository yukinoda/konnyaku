import Foundation
import os

/// One-time carry-over of data from the app's former identity ("konjac",
/// bundle ID org.konjac.app) to Konnyaku.
enum LegacyMigration {
    static let legacyBundleID = "org.konjac.app"
    static let settingsMarkerKey = "migratedFromKonjac"
    static let settingsKeys = ["modelSize"]
    private static let logger = Logger(subsystem: "io.github.yukinoda.konnyaku", category: "migration")

    /// Moves the old models directory to the new location when only the old
    /// one exists. A failed move is ignored: the models are simply
    /// downloaded again.
    static func moveDirectory(
        from legacy: URL,
        to current: URL,
        fileManager: FileManager = .default
    ) {
        let hasLegacy = fileManager.fileExists(atPath: legacy.path)
        let hasCurrent = fileManager.fileExists(atPath: current.path)
        if !hasLegacy || hasCurrent {
            return
        }
        do {
            try fileManager.moveItem(at: legacy, to: current)
        } catch {
            logger.error("Could not move the old models directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Copies settings from the old bundle ID's defaults into `defaults`,
    /// without overwriting anything already set, and runs only once.
    static func copySettings(
        from legacy: UserDefaults?,
        to defaults: UserDefaults = .standard
    ) {
        if defaults.bool(forKey: settingsMarkerKey) {
            return
        }
        defaults.set(true, forKey: settingsMarkerKey)
        guard let legacy else {
            return
        }
        for key in settingsKeys {
            let alreadySet = defaults.object(forKey: key) != nil
            let legacyValue = legacy.object(forKey: key)
            if alreadySet {
                continue
            }
            if let legacyValue {
                defaults.set(legacyValue, forKey: key)
            }
        }
    }

    static func copyLegacySettings() {
        copySettings(from: UserDefaults(suiteName: legacyBundleID))
    }
}
