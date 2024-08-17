
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
    static let motionAndFitness = "ActivityMonitoringScreen"
    static let backgroundRefresh = "BackgroundOperationsScreen"
    static let notifications = "NotificationsScreen"
    static let media = "LibraryScreen"
    static let microphone = "MicrophoneScreen"
    static let camera = "CameraScreen"
    static let completed = "Completed"
}

public enum PermissionType: Int, CaseIterable, RawRepresentable {
    case location = 0
    case motionAndFitness
    case backgroundRefresh
    case notifications
    case media
    case microphone
    case camera
    
    case completed
    
    public func isLast(lastInSequence: PermissionType) -> Bool {
        self ==  lastInSequence
    }
    
    static var allScreens: [String] { [
        ScreensNamesConstants.location,
        ScreensNamesConstants.motionAndFitness,
        ScreensNamesConstants.backgroundRefresh,
        ScreensNamesConstants.notifications,
        ScreensNamesConstants.media,
        ScreensNamesConstants.microphone,
        ScreensNamesConstants.camera,
        ScreensNamesConstants.completed
    ]}
    
    public var name: String {
        switch self {
        case .location:
            ScreensNamesConstants.location
        case .motionAndFitness:
            ScreensNamesConstants.motionAndFitness
        case .backgroundRefresh:
            ScreensNamesConstants.backgroundRefresh
        case .notifications:
            ScreensNamesConstants.notifications
        case .media:
            ScreensNamesConstants.media
        case .microphone:
            ScreensNamesConstants.microphone
        case .camera:
            ScreensNamesConstants.camera
        case .completed:
            ScreensNamesConstants.completed
        }
    }
}

public protocol PermissionService: AnyObject {
    func isFreshInstall() async -> Bool
    func isAllPermissionsAvailable() async -> Bool
    func checkPermissionAvailable(for type: PermissionType) async -> Bool
    func requestPermissionWithHandler(for type: PermissionType, completion: @escaping EmptyBlock)
    func requestLastPermissionScreen() async -> PermissionType
}

final public class PermissionManager: NSObject, PermissionService {
    let locationManager = CLLocationManager()
    let motionActivityManager = CMMotionActivityManager()
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

    override public init() {
        super.init()
        self.locationManager.delegate = self
    }
    
    public func isAllPermissionsAvailable() async -> Bool {
        let notAvailable = await PermissionType
            .allCases
            .filter({ $0 != .completed })
            .asyncMap { type in
                await checkPermissionAvailable(for: type)
            }
            .contains(false)
        
        return !notAvailable
    }

    public func isFreshInstall() async -> Bool {
        let containsNotDetermined = await PermissionType
            .allCases
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
        case .location, .backgroundRefresh:
            return locationManager.authorizationStatus == .notDetermined
        case .motionAndFitness:
            return CMMotionActivityManager.authorizationStatus() == .notDetermined
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
        case .media:
            return PHPhotoLibrary.authorizationStatus() == .notDetermined
        case .microphone:
            return AVAudioSession.sharedInstance().recordPermission == .undetermined
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
        case .backgroundRefresh:
            return await checkBackgroundAppRefresh()
        case .motionAndFitness:
            return await checkMotionAndFitnessPermission()
        case .media:
            return await checkLibraryPermission()
        case .microphone:
            return await checkMicroPermission()
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
        case .backgroundRefresh:
            requestAlwaysAuthorizationForLocation { completion() }
        case .motionAndFitness:
            requestAuthorizationForMotionActivity { completion() }
        case .media:
            requestAuthorizationForLibraryUsage { completion() }
        case .microphone:
            requestAuthorizationForMicroUsage { completion() }
        case .camera:
            requestAuthorizationForCameraUsage { completion() }
        case .completed:
            completion()
        }
    }

    public func requestLastPermissionScreen() async -> PermissionType {
        guard let storedPermission = lastStepScreen,
              let indexOfPermission = PermissionType.allScreens.firstIndex(of: storedPermission),
              let screen = PermissionType(rawValue: indexOfPermission) else {
            let permissionsGiven = await isAllPermissionsAvailable()
            return permissionsGiven ? .completed : .location
        }
        
        return screen
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
        if #available(iOS 14.0, *) {
            return self.locationStatus == .authorizedAlways && locationManager.accuracyAuthorization == .fullAccuracy
        } else {
            return self.locationStatus == .authorizedAlways
        }
    }
    
    func checkBackgroundAppRefresh() async -> Bool {
        let status = await UIApplication.shared.backgroundRefreshStatus
        return status == .available
    }

    func checkMotionAndFitnessPermission() async -> Bool {
        let authorizationStatus = CMMotionActivityManager.authorizationStatus()
        return authorizationStatus == .authorized
    }
    
    func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized
    }
    
    func checkLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized
    }
    
    func checkMicroPermission() async -> Bool {
        let status = AVAudioSession.sharedInstance().recordPermission
        return status == .granted
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
    
    func requestAuthorizationForMicroUsage(completion: @escaping EmptyBlock) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            completion()
        }
    }

    func requestAuthorizationForMotionActivity(completion: @escaping EmptyBlock) {
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            if self?.motionPermissionShown == false {
                self?.motionPermissionShown = true
                completion()
            }
        }

        motionActivityManager.queryActivityStarting(from: Date(), to: Date(), to: .main, withHandler: { [weak self] activities, error in
            if let error, self?.motionPermissionShown == false {
                self?.motionPermissionShown = true
                self?.logger.debug("CMError - \(error.localizedDescription)")
                completion()
            }
        })
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
