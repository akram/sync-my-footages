import Foundation

/// Represents a type of DJI capture device
enum DJIDeviceType: String, Codable, CaseIterable, Sendable {
    case osmoPocket3 = "Osmo Pocket 3"
    case action5Pro = "Action 5 Pro"
    case neo2 = "Neo 2"
    case unknown = "Unknown DJI Device"

    var iconName: String {
        switch self {
        case .osmoPocket3: return "movieclapper.fill"
        case .action5Pro: return "camera.fill"
        case .neo2: return "drone.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// A DJI device currently connected via USB or SD card adapter
struct DJIDevice: Identifiable, Hashable, Sendable {
    let id: String
    let volumePath: URL
    let volumeName: String
    let deviceType: DJIDeviceType
    let dcimFolders: [URL]
    let storageType: StorageType

    enum StorageType: String, Codable, Sendable {
        case internalStorage = "Internal"
        case sdCard = "SD Card"
        case unknown = "Unknown"
    }

    init(volumePath: URL, volumeName: String, deviceType: DJIDeviceType, dcimFolders: [URL], storageType: StorageType = .unknown) {
        self.id = volumePath.path
        self.volumePath = volumePath
        self.volumeName = volumeName
        self.deviceType = deviceType
        self.dcimFolders = dcimFolders
        self.storageType = storageType
    }
}
