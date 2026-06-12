import SwiftUI

@main
struct SyncMyFootagesApp: App {
    @State private var appState = AppState()

    init() {
        // Migrate UserDefaults from bundle domain to executable domain (or vice versa)
        // so settings persist whether launched from .app bundle or debug binary
        Self.migrateUserDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appState)
        } label: {
            Label("Sync My Footages", systemImage: appState.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }

    /// Ensure UserDefaults are available regardless of launch method
    private static func migrateUserDefaults() {
        let bundleID = Constants.appIdentifier
        let currentDomain = Bundle.main.bundleIdentifier ?? "SyncMyFootages"

        // If we're running from .app bundle, the domain is already correct
        guard currentDomain != bundleID else { return }

        // Running from debug binary — import settings from the bundle domain
        guard let bundleDefaults = UserDefaults(suiteName: bundleID) else { return }
        let keysToMigrate = ["destinationDisks", "deviceProfiles", "organizationPattern",
                             "defaultVerificationLevel", "autoHashAfterSync", "showNotifications",
                             "fileTypeMapping", "lastSyncTimestamps"]

        for key in keysToMigrate {
            if UserDefaults.standard.object(forKey: key) == nil,
               let value = bundleDefaults.object(forKey: key) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }

        // Also migrate sync destination selections (syncDestinations_*)
        let bundleDict = bundleDefaults.dictionaryRepresentation()
        for (key, value) in bundleDict where key.hasPrefix("syncDestinations_") {
            if UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
}
