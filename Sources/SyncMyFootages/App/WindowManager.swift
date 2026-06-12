import SwiftUI
import AppKit

/// Opens SwiftUI views in standalone NSWindows — works reliably from MenuBarExtra
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]

    func openSyncConfig(device: CaptureDevice, appState: AppState) {
        let windowID = "sync-config-\(device.id)"

        if let existing = windows[windowID] {
            bringToFront(existing)
            return
        }

        let view = SyncConfigView(device: device)
            .environment(appState)

        let window = createWindow(
            id: windowID,
            title: "Sync — \(device.deviceType.rawValue)",
            content: view,
            width: 520,
            height: 560,
            resizable: false
        )
        bringToFront(window)
    }

    func openDashboard(appState: AppState) {
        let windowID = "redundancy"

        if let existing = windows[windowID] {
            bringToFront(existing)
            return
        }

        let view = RedundancyDashboardView()
            .environment(appState)

        let window = createWindow(
            id: windowID,
            title: "Redundancy Dashboard",
            content: view,
            width: 900,
            height: 650,
            resizable: true
        )
        bringToFront(window)
    }

    func openApplyProjects(appState: AppState) {
        let windowID = "apply-projects"

        if let existing = windows[windowID] {
            bringToFront(existing)
            return
        }

        let view = ApplyProjectsView()
            .environment(appState)

        let window = createWindow(
            id: windowID,
            title: "Apply Projects",
            content: view,
            width: 550,
            height: 450,
            resizable: false
        )
        bringToFront(window)
    }

    func openDuplicates() {
        let windowID = "duplicates"

        if let existing = windows[windowID] {
            bringToFront(existing)
            return
        }

        let view = DuplicatesView()

        let window = createWindow(
            id: windowID,
            title: "Duplicate Scanner",
            content: view,
            width: 750,
            height: 550,
            resizable: true
        )
        bringToFront(window)
    }

    func openSettings(appState: AppState) {
        let windowID = "settings"

        if let existing = windows[windowID] {
            bringToFront(existing)
            return
        }

        let view = SettingsView()
            .environment(appState)

        let window = createWindow(
            id: windowID,
            title: "Sync My Footages — Settings",
            content: view,
            width: 620,
            height: 520,
            resizable: false
        )
        bringToFront(window)
    }

    // MARK: - Private

    private func bringToFront(_ window: NSWindow) {
        // Temporarily make the app a regular app so it can take focus
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Reset window level after a short delay so it behaves normally
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            window.level = .normal
            // Go back to accessory if we were before — keeps dock icon hidden
            if previousPolicy == .accessory {
                // Only hide from dock again if no other windows are visible
                let hasVisibleWindows = self.windows.values.contains { $0.isVisible }
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func createWindow<V: View>(
        id: String,
        title: String,
        content: V,
        width: CGFloat,
        height: CGFloat,
        resizable: Bool
    ) -> NSWindow {
        let hostingView = NSHostingView(rootView: content)

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { styleMask.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        let windowID = id
        let delegate = WindowCleanupDelegate { [weak self] in
            self?.windows.removeValue(forKey: windowID)
        }
        objc_setAssociatedObject(window, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.delegate = delegate

        windows[id] = window
        return window
    }
}

/// Per-window delegate that cleans up the WindowManager reference and frees SwiftUI views on close
private final class WindowCleanupDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        // Free the SwiftUI hosting view to release memory
        if let window = notification.object as? NSWindow {
            window.contentView = nil
        }
        onClose()
    }
}
