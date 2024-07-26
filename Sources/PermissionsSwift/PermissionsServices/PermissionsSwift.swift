// The Swift Programming Language
// https://docs.swift.org/swift-book
#if os(iOS)
import CoreBluetooth
import UserNotifications
import CoreLocation
import CoreMotion
import UIKit
import os

typealias EmptyBlock = () -> Void
typealias PermissionBlock = (PermissionType) -> Void

enum PermissionType: Int, CaseIterable, RawRepresentable {
    case location = 0
    case motionAndFitness
    case backgroundRefresh
    case notifications
}

protocol PermissionService: AnyObject {
    func isFreshInstall(_ completion: @escaping (Bool) -> Void)
    func isAllPermissionsAvailable(_ completion: @escaping (Bool) -> Void)
    func checkPermissionAvailable(for type: PermissionType) async -> Bool
    func requestPermissionWithHandler(for type: PermissionType, completion: @escaping EmptyBlock)
    func requestLastPermissionScreen() -> PermissionScreen
    func requestLastPermissionScreenWrapper(completion: @escaping (PermissionScreen) -> Void)
}

final class PermissionManager: NSObject, PermissionService {
    let locationManager = CLLocationManager()
    let motionActivityManager = CMMotionActivityManager()
    let userNotificationsCenter = UNUserNotificationCenter.current()
    @Defaults<String>(key: .lastStepScreen) var lastStepScreen
    @Defaults<String>(key: .firstInstall) var isFirstInstall
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

    init(
        permissionScreens: [PermissionScreen]
    ) {
        self.permissionScreens = permissionScreens
        super.init()
        self.locationManager.delegate = self
    }
    
    func isAllPermissionsAvailable(_ completion: @escaping (Bool) -> Void) {
        Task {
            let allAvailable = await isAllPermissionsAvailable()
            completion(allAvailable)
        }
    }
    
    func isAllPermissionsAvailable() async -> Bool {
        let isLocationAvailable             = await checkLocationAndAccuracyPermission()
        let isNotificationsAvailable        = await checkNotificationPermission()
        let isMotionAndFitnessAvailable     = await checkMotionAndFitnessPermission()
        let isBackgroundAppRefreshAvailable = await checkBackgroundAppRefresh()
        
        let allAvailable = isLocationAvailable
                        && isNotificationsAvailable
                        && isMotionAndFitnessAvailable
                        && isBackgroundAppRefreshAvailable
        
        return allAvailable
    }

    func isFreshInstall(_ completion: @escaping (Bool) -> Void) {
        Task {
            let allNotDetermined = await isFreshInstall()
            completion(allNotDetermined)
        }
    }

    func isFreshInstall() async -> Bool {
        let isLocationNotDetermined         = await checkIfPermissionsAreNotDetermined(for: .location)
        let isNotificationsNotDetermined    = await checkIfPermissionsAreNotDetermined(for: .notifications)
        let isMotionAndFitnessNotDetermined = await checkIfPermissionsAreNotDetermined(for: .motionAndFitness)
        let containsNotDetermined = isLocationNotDetermined
                                    || isNotificationsNotDetermined
                                    || isMotionAndFitnessNotDetermined

        return containsNotDetermined
    }

    func checkIfPermissionsAreNotDetermined(for type: PermissionType) async -> Bool {
        switch type {
        case .notifications:
            let settings = await userNotificationsCenter.notificationSettings()
            return settings.authorizationStatus == .notDetermined
        case .location, .backgroundRefresh:
            return locationManager.authorizationStatus == .notDetermined
        case .motionAndFitness:
            return CMMotionActivityManager.authorizationStatus() == .notDetermined
        }
    }
    
    func checkPermissionAvailable(for type: PermissionType) async -> Bool {
        switch type {
        case .notifications:
            return await checkNotificationPermission()
        case .location:
            return await checkLocationAndAccuracyPermission()
        case .backgroundRefresh:
            return await checkBackgroundAppRefresh()
        case .motionAndFitness:
            return await checkMotionAndFitnessPermission()
        }
    }

    func requestPermissionWithHandler(for type: PermissionType, completion: @escaping EmptyBlock) {
        switch type {
        case .notifications:
            requestAuthorizationForNotifications {
                completion()
            }
        case .location:
            requestWhenInUseAuthorizationForLocation {
                completion()
            }
        case .backgroundRefresh:
            requestAlwaysAuthorizationForLocation {
                completion()
            }
        case .motionAndFitness:
            requestAuthorizationForMotionActivity {
                completion()
            }
        }
    }

    func requestLastPermissionScreenWrapper(completion: @escaping (PermissionScreen) -> Void) {
        Task {
            let allNotDetermined = await isFreshInstall()
            if allNotDetermined {
                completion(PermissionScreen.location)
            } else {
                guard let storedPermission = lastStepScreen,
                      let indexOfPermission = PermissionScreen.allScreens.firstIndex(of: storedPermission),
                      let screen = PermissionScreen(rawValue: indexOfPermission) else {
                    if isFirstInstall != nil {
                        completion(PermissionScreen.complete)
                    } else {
                        completion(PermissionScreen.location)
                    }
                    return
                }

                completion(screen)
            }
        }
    }

    func requestLastPermissionScreen() -> PermissionScreen {
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
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
