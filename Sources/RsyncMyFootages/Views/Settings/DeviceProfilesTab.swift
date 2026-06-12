import SwiftUI

struct DeviceProfilesTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Device Profiles") {
                ForEach($state.deviceProfiles) { $profile in
                    HStack {
                        Image(systemName: profile.deviceType.iconName)
                            .frame(width: 24)
                        Text(profile.deviceType.rawValue)
                            .frame(width: 120, alignment: .leading)
                        Picker("Behavior", selection: $profile.syncBehavior) {
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
            }
        }
    }
}
