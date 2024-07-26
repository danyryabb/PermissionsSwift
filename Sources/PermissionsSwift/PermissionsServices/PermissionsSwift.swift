
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

public enum PermissionType: Int, CaseIterable, RawRepresentable {
    case location = 0
    case motionAndFitness
    case backgroundRefresh
    case notifications
    case media
    case microphone
    case camera
}

public protocol PermissionService: AnyObject {
    func isFreshInstall(_ completion: @escaping (Bool) -> Void)
    func isAllPermissionsAvailable(_ completion: @escaping (Bool) -> Void)
    func checkPermissionAvailable(for type: PermissionType) async -> Bool
    func requestPermissionWithHandler(for type: PermissionType, completion: @escaping EmptyBlock)
    func requestLastPermissionScreen() -> PermissionScreen
    func requestLastPermissionScreenWrapper(completion: @escaping (PermissionScreen) -> Void)
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
    
    private(set) var permissionScreens: [PermissionScreen]
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PermissionManager.self)
    )

    public init(
        permissionScreens: [PermissionScreen] = []
    ) {
        self.permissionScreens = permissionScreens
        super.init()
        self.locationManager.delegate = self
    }
    
    public func isAllPermissionsAvailable(_ completion: @escaping (Bool) -> Void) {
        Task {
            let allAvailable = await isAllPermissionsAvailable()
            completion(allAvailable)
        }
    }
    
    public func isAllPermissionsAvailable() async -> Bool {
        let allAvailable = await PermissionType.allCases
            .asyncMap { type in
                await checkPermissionAvailable(for: type)
            }
            .contains(false)
        
        return !allAvailable
    }

    public func isFreshInstall(_ completion: @escaping (Bool) -> Void) {
        Task {
            let allNotDetermined = await isFreshInstall()
            completion(allNotDetermined)
        }
    }

    public func isFreshInstall() async -> Bool {
        let containsNotDetermined = await PermissionType.allCases
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
        }
    }

    public func requestLastPermissionScreenWrapper(completion: @escaping (PermissionScreen) -> Void) {
        Task {
            let allNotDetermined = await isFreshInstall()
            if allNotDetermined {
                completion(PermissionScreen.location)
            } else {
                guard let storedPermission = lastStepScreen,
                      let indexOfPermission = PermissionScreen.allScreens.firstIndex(of: storedPermission),
                      let screen = PermissionScreen(rawValue: indexOfPermission) else {
                    
                    let permissionsGiven = await isAllPermissionsAvailable()
                    permissionsGiven ? completion(PermissionScreen.complete) : completion(PermissionScreen.location)
                    return
                }

                completion(screen)
            }
        }
    }

    public func requestLastPermissionScreen() -> PermissionScreen {
        guard let storedPermission = lastStepScreen,
              let indexOfPermission = PermissionScreen.allScreens.firstIndex(of: storedPermission),
              let screen = PermissionScreen(rawValue: indexOfPermission) else {
            return .location
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
