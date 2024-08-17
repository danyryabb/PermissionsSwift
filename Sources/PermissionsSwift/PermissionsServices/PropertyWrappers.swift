import Foundation

@propertyWrapper
public struct Defaults<T> {
    public enum Key: String {
        case lastStepScreen
        case requestToReview
        case firstInstall
    }

    let key: Key
    private var storage: UserDefaults = .standard

    public var wrappedValue: T? {
        get {
            storage.value(forKey: key.rawValue) as? T
        }
        set {
            storage.setValue(newValue, forKey: key.rawValue)
        }
    }

    public init(key: Key) {
        self.key = key
    }
}
