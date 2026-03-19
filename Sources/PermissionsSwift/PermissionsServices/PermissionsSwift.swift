
#if os(iOS)
import CoreBluetooth
import UserNotifications
import CoreLocation
import CoreMotion
import UIKit
import os
import AVKit
import Photos

public typealias EmptyBlock = () -> Void
public typealias PermissionBlock = (PermissionType) -> Void

public enum ScreensNamesConstants {
    static let location = "LocationScreen"
    static let notifications = "NotificationsScreen"
    static let media = "LibraryScreen"
    static let camera = "CameraScreen"
    static let completed = "Completed"
}

public enum PermissionType: Int, CaseIterable, RawRepresentable {
    case location = 0
    case notifications
    case media
    case camera
    // must be included always
    case completed
    
    public func isLast(lastInSequence: PermissionType) -> Bool {
        self == lastInSequence
    }
    
    public var name: String {
        switch self {
        case .location:
            ScreensNamesConstants.location
        case .notifications:
            ScreensNamesConstants.notifications
        case .media:
            ScreensNamesConstants.media
        case .camera:
            ScreensNamesConstants.camera
        case .completed:
            ScreensNamesConstants.completed
        }
    }
}

public protocol PermissionService: AnyObject {
    var locationManager: CLLocationManager { get }

    func isFreshInstall() async -> Bool
    func isAllPermissionsAvailable() async -> Bool
    func checkPermissionAvailable(for type: PermissionType) async -> Bool
    func requestPermissionWithHandler(for type: PermissionType, completion: @escaping EmptyBlock)
    func requestLastPermissionScreen() async -> PermissionType
}

final public class PermissionManager: NSObject, PermissionService {
    public var locationManager = CLLocationManager()
    let userNotificationsCenter = UNUserNotificationCenter.current()
    @Defaults<String>(key: .lastStepScreen) var lastStepScreen
    private(set) var locationCompletion: EmptyBlock? = nil
    private(set) var motionPermissionShown: Bool = false
    private var locationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PermissionManager.self)
    )
    
    private let includedPermissions: [PermissionType]
    private var localizedPermissions: [String] {
        includedPermissions.map({ $0.name })
    }

    public init(includedPermissions: [PermissionType]) {
        self.includedPermissions = includedPermissions
        super.init()
        self.locationManager.delegate = self
    }
    
    public func isAllPermissionsAvailable() async -> Bool {
        let notAvailable = await includedPermissions
            .filter({ $0 != .completed })
            .asyncMap { type in
                await checkPermissionAvailable(for: type)
            }
            .contains(false)
        
        return !notAvailable
    }

    public func isFreshInstall() async -> Bool {
        let containsNotDetermined = await includedPermissions
            .filter({ $0 != .completed })
            .asyncMap { type in
                await checkIfPermissionsAreNotDetermined(for: type)
            }
            .contains(true)
        
        return containsNotDetermined
    }

    public func checkIfPermissionsAreNotDetermined(for type: PermissionType) async -> Bool {
        switch type {
        case .notifications:
            let settings = await userNotificationsCenter.notificationSettings()
            return settings.authorizationStatus == .notDetermined
        case .location:
            return locationManager.authorizationStatus == .notDetermined
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
        case .media:
            return PHPhotoLibrary.authorizationStatus() == .notDetermined
        case .completed:
            return false
        }
    }
    
    public func checkPermissionAvailable(for type: PermissionType) async -> Bool {
        switch type {
        case .notifications:
            return await checkNotificationPermission()
        case .location:
            return await checkLocationAndAccuracyPermission()
        case .media:
            return await checkLibraryPermission()
        case .camera:
            return await checkCameraPermission()
        case .completed:
            return true
        }
    }

    public func requestPermissionWithHandler(for type: PermissionType, completion: @escaping EmptyBlock) {
        switch type {
        case .notifications:
            requestAuthorizationForNotifications { completion() }
        case .location:
            requestWhenInUseAuthorizationForLocation { completion() }
        case .media:
            requestAuthorizationForLibraryUsage { completion() }
        case .camera:
            requestAuthorizationForCameraUsage { completion() }
        case .completed:
            completion()
        }
    }

    public func requestLastPermissionScreen() async -> PermissionType {
        guard let storedPermission = lastStepScreen,
              let indexOfPermission = localizedPermissions.firstIndex(of: storedPermission),
              let screen = PermissionType(rawValue: indexOfPermission) else {
            let permissionsGiven = await isAllPermissionsAvailable()
            return permissionsGiven ? .completed : .location
        }
        
        return screen == .completed ? screen : screen.next()
    }
}

private extension PermissionManager {
    func checkNotificationPermission() async -> Bool {
        let settings = await userNotificationsCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    func checkLocationAndAccuracyPermission() async -> Bool {
        return (self.locationStatus == .authorizedWhenInUse || self.locationStatus == .authorizedAlways) && locationManager.accuracyAuthorization == .fullAccuracy
    }
    
    func checkBackgroundAppRefresh() async -> Bool {
        let status = await UIApplication.shared.backgroundRefreshStatus
        return status == .available
    }
    
    func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized
    }
    
    func checkLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized
    }
}

private extension PermissionManager {
    func requestAuthorizationForNotifications(completion: @escaping EmptyBlock) {
        userNotificationsCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            self?.userNotificationsCenter.getNotificationSettings(completionHandler: { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    DispatchQueue.main.async { [weak self] in
                        UIApplication.shared.registerForRemoteNotifications()
                        let isRegistered = UIApplication.shared.isRegisteredForRemoteNotifications
                        self?.logger.debug("application.isRegisteredForRemoteNotifications : \(isRegistered)")
                    }
                    completion()
                case .denied:
                    completion()
                default:
                    break
                }
            })
        }
    }
    
    func requestWhenInUseAuthorizationForLocation(completion: @escaping EmptyBlock) {
        locationCompletion = completion
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestAlwaysAuthorizationForLocation(completion: @escaping EmptyBlock) {
        switch locationStatus {
        case .denied, .restricted:
            completion()
        default:
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil)
            
            locationCompletion = completion
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    func requestAuthorizationForLibraryUsage(completion: @escaping EmptyBlock) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            completion()
        }
    }
    
    func requestAuthorizationForCameraUsage(completion: @escaping EmptyBlock) {
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
            completion()
        }
    }
}

extension PermissionManager: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.locationCompletion?()
        self.locationCompletion = nil
    }
}

extension PermissionManager {
    @objc func didBecomeActive() {
        guard let locationCompletion else {
            return
        }

        locationCompletion()
        self.locationCompletion = nil
        NotificationCenter.default.removeObserver(self)
    }
}
#endif
