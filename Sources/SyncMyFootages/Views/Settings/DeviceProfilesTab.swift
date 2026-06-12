import SwiftUI

struct DeviceProfilesTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Device Profiles") {
                ForEach(appState.deviceProfiles) { profile in
                    HStack {
                        Image(systemName: profile.deviceType.iconName)
                            .frame(width: 24)
                        Text(profile.deviceType.rawValue)
                            .frame(width: 160, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { profile.syncBehavior },
                            set: { newValue in
                                if let index = appState.deviceProfiles.firstIndex(where: { $0.id == profile.id }) {
                                    appState.deviceProfiles[index].syncBehavior = newValue
                                    appState.saveSettings()
                                }
                            }
                        )) {
                            ForEach(DeviceProfile.SyncBehavior.allCases, id: \.self) { behavior in
                                Text(behavior.rawValue).tag(behavior)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            Section {
                Text("Profiles determine how the app reacts when a device is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if appState.deviceProfiles.isEmpty {
                appState.deviceProfiles = DeviceProfile.defaults
                appState.saveSettings()
            }
        }
    }
}
