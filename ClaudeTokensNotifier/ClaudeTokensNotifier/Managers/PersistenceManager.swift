import Foundation

class PersistenceManager {
    static let shared = PersistenceManager()
    private let defaults = UserDefaults.standard
    private let prefix = "ClaudeTokensNotifier."

    private init() {}

    func save<T: Codable>(key: String, value: T?) {
        let fullKey = prefix + key
        if let value = value {
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: fullKey)
            }
        } else {
            defaults.removeObject(forKey: fullKey)
        }
    }

    func load<T: Codable>(key: String, defaultValue: T?) -> T? {
        let fullKey = prefix + key
        guard let data = defaults.data(forKey: fullKey) else { return defaultValue }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? defaultValue
    }

    func load<T: Codable>(key: String, defaultValue: T) -> T {
        let fullKey = prefix + key
        guard let data = defaults.data(forKey: fullKey) else { return defaultValue }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? defaultValue
    }
}
