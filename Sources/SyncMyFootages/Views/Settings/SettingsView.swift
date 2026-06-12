import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = 0

    private let tabs = [
        (label: "Devices", icon: "camera"),
        (label: "Destinations", icon: "externaldrive"),
        (label: "Sync", icon: "arrow.triangle.2.circlepath"),
        (label: "File Types", icon: "doc.badge.gearshape"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.title3)
                        Text(tabs[index].label)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(selectedTab == index ? .blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(selectedTab == index ? .blue : .secondary)
                    .onTapGesture { selectedTab = index }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
                .padding(.top, 4)

            // Content
            Group {
                switch selectedTab {
                case 0: DeviceProfilesTab()
                case 1: DestinationsTab()
                case 2: SyncSettingsTab()
                case 3: FileTypeMappingTab()
                default: EmptyView()
                }
            }
        }
        .frame(width: 620, height: 520)
    }
}
