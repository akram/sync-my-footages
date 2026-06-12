import Foundation

/// User-configured profile for a capture device type
struct DeviceProfile: Identifiable, Codable, Hashable, Sendable {
    var id: String { deviceType.rawValue }
    let deviceType: CaptureDeviceType
    var syncBehavior: SyncBehavior
    var defaultDestinationID: String?

    enum SyncBehavior: String, Codable, CaseIterable, Sendable {
        case autoSync = "Auto Sync"
        case confirmFirst = "Confirm First"
        case ignore = "Ignore"
    }

    static var defaults: [DeviceProfile] {
        CaptureDeviceType.allCases.compactMap { type in
            guard type != .unknown else { return nil }
            return DeviceProfile(deviceType: type, syncBehavior: .confirmFirst)
        }
    }
}
