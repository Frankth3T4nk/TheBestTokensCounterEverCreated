import Foundation
import Combine
import ServiceManagement

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var notificationThresholds: [Int] {
        didSet { UserDefaults.standard.set(notificationThresholds, forKey: Keys.thresholds) }
    }

    @Published var pollingInterval: Double {
        didSet { UserDefaults.standard.set(pollingInterval, forKey: Keys.pollingInterval) }
    }

    @Published var completionNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(completionNotificationsEnabled, forKey: Keys.completionNotifications) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    @Published var customEndpoint: String {
        didSet { UserDefaults.standard.set(customEndpoint, forKey: Keys.customEndpoint) }
    }

    @Published var customFilePath: String {
        didSet { UserDefaults.standard.set(customFilePath, forKey: Keys.customFilePath) }
    }

    @Published var anthropicApiKey: String {
        didSet { UserDefaults.standard.set(anthropicApiKey, forKey: Keys.anthropicApiKey) }
    }

    private enum Keys {
        static let thresholds = "notificationThresholds"
        static let pollingInterval = "pollingInterval"
        static let completionNotifications = "completionNotificationsEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let customEndpoint = "customEndpoint"
        static let customFilePath = "customFilePath"
        static let anthropicApiKey = "anthropicApiKey"
    }

    private init() {
        let defaults = UserDefaults.standard

        if let saved = defaults.array(forKey: Keys.thresholds) as? [Int], !saved.isEmpty {
            notificationThresholds = saved
        } else {
            notificationThresholds = [75, 50, 25, 0]
        }

        let savedInterval = defaults.double(forKey: Keys.pollingInterval)
        pollingInterval = savedInterval > 0 ? savedInterval : 60.0

        if defaults.object(forKey: Keys.completionNotifications) != nil {
            completionNotificationsEnabled = defaults.bool(forKey: Keys.completionNotifications)
        } else {
            completionNotificationsEnabled = true
        }

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        customEndpoint = defaults.string(forKey: Keys.customEndpoint) ?? ""
        customFilePath = defaults.string(forKey: Keys.customFilePath) ?? ""
        anthropicApiKey = defaults.string(forKey: Keys.anthropicApiKey) ?? ""
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[SettingsManager] Launch at login error: \(error.localizedDescription)")
            }
        }
    }

    func addThreshold(_ value: Int) {
        let clamped = max(0, min(100, value))
        if !notificationThresholds.contains(clamped) {
            notificationThresholds.append(clamped)
            notificationThresholds.sort(by: >)
        }
    }

    func removeThreshold(_ value: Int) {
        notificationThresholds.removeAll { $0 == value }
    }

    func resetToDefaults() {
        notificationThresholds = [75, 50, 25, 0]
        pollingInterval = 60.0
        completionNotificationsEnabled = true
        customEndpoint = ""
        customFilePath = ""
        anthropicApiKey = ""
    }
}
