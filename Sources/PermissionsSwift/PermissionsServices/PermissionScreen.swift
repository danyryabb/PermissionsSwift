import Foundation

public enum ScreensNamesConstants {
    static let location = "LocationScreen"
    static let activityMonitoring = "ActivityMonitoringScreen"
    static let backgroundOperations = "BackgroundOperationsScreen"
    static let notifications = "NotificationsScreen"
    static let library = "LibraryScreen"
    static let micro = "MicrophoneScreen"
    static let camera = "CameraScreen"
    static let complete = "Complete"
}

public enum PermissionScreen: Int {
    case location
    case activityMonitoring
    case backgroundOperations
    case notifications
    case library
    case micro
    case camera

    case complete

    init(_ permissionType: PermissionType) {
        switch permissionType {
        case .location:
            self = .location
        case .motionAndFitness:
            self = .activityMonitoring
        case .backgroundRefresh:
            self = .backgroundOperations
        case .notifications:
            self = .notifications
        case .media:
            self = .library
        case .microphone:
            self = .micro
        case .camera:
            self = .camera
        }
    }

    var localizedName: String {
        switch self {
        case .location:
            return ScreensNamesConstants.location
        case .activityMonitoring:
            return ScreensNamesConstants.activityMonitoring
        case .backgroundOperations:
            return ScreensNamesConstants.backgroundOperations
        case .notifications:
            return ScreensNamesConstants.notifications
        case .complete:
            return ScreensNamesConstants.complete
        case .library:
            return ScreensNamesConstants.library
        case .micro:
            return ScreensNamesConstants.micro
        case .camera:
            return ScreensNamesConstants.camera
        }
    }

    static var allScreens: [String] { [
        ScreensNamesConstants.location,
        ScreensNamesConstants.activityMonitoring,
        ScreensNamesConstants.backgroundOperations,
        ScreensNamesConstants.notifications,
        ScreensNamesConstants.library,
        ScreensNamesConstants.micro,
        ScreensNamesConstants.camera,
        ScreensNamesConstants.complete
    ]}
}
