import Foundation

public enum ScreensNamesConstants {
    static let location = "LocationScreen"
    static let activityMonitoring = "ActivityMonitoringScreen"
    static let backgroundOperations = "BackgroundOperationsScreen"
    static let notifications = "NotificationsScreen"
    static let complete = "Complete"
}

public enum PermissionScreen: Int {
    case location
    case activityMonitoring
    case backgroundOperations
    case notifications

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
        }
    }

    static var allScreens: [String] { [
        ScreensNamesConstants.location,
        ScreensNamesConstants.activityMonitoring,
        ScreensNamesConstants.backgroundOperations,
        ScreensNamesConstants.notifications,
        ScreensNamesConstants.complete
    ]}
}
