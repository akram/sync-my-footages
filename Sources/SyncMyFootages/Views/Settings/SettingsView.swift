import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Devices", systemImage: "camera") {
                DeviceProfilesTab()
            }

            Tab("Destinations", systemImage: "externaldrive") {
                DestinationsTab()
            }

            Tab("Sync", systemImage: "arrow.triangle.2.circlepath") {
                SyncSettingsTab()
            }

            Tab("File Types", systemImage: "doc.badge.gearshape") {
                FileTypeMappingTab()
            }
        }
        .frame(width: 620, height: 520)
    }
}
