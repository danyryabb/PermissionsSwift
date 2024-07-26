import Foundation

@propertyWrapper
struct Defaults<T> {
    enum Key: String {
        case lastStepScreen
        case requestToReview
        case firstInstall
    }

    let key: Key
    private var storage: UserDefaults = .standard

    var wrappedValue: T? {
        get {
            storage.value(forKey: key.rawValue) as? T
        }
        set {
            storage.setValue(newValue, forKey: key.rawValue)
        }
    }

    init(key: Key) {
        self.key = key
    }
}
