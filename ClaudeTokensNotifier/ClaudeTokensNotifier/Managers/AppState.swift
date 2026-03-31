import Foundation
import Combine
import SwiftUI

enum TokenLevel {
    case full, high, medium, low, critical, unknown
}

struct TokenStatus: Codable {
    var remainingTokens: Int?
    var totalTokens: Int?
    var usedTokens: Int?
    var resetTime: String?
    var percentRemaining: Double?
    var isActive: Bool?

    // Support various JSON key formats from Claude
    enum CodingKeys: String, CodingKey {
        case remainingTokens = "remaining_tokens"
        case totalTokens = "total_tokens"
        case usedTokens = "used_tokens"
        case resetTime = "reset_time"
        case percentRemaining = "percent_remaining"
        case isActive = "is_active"
    }

    var computedPercent: Double {
        if let p = percentRemaining { return p }
        if let rem = remainingTokens, let total = totalTokens, total > 0 {
            return (Double(rem) / Double(total)) * 100.0
        }
        return 100.0
    }

    var level: TokenLevel {
        let p = computedPercent
        if p > 75 { return .full }
        if p > 50 { return .high }
        if p > 25 { return .medium }
        if p > 10 { return .low }
        return .critical
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var tokenStatus: TokenStatus = TokenStatus()
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isMonitoring: Bool = true
    @Published var lastUpdated: Date?
    @Published var lastResetTime: String?
    @Published var errorMessage: String?

    var onIconUpdate: ((TokenLevel) -> Void)?

    private let tokenService = TokenService()
    private let notificationManager = NotificationManager.shared
    private let persistenceManager = PersistenceManager.shared
    private var settingsManager: SettingsManager { SettingsManager.shared }
    private var pollingTask: Task<Void, Never>?
    private var claudeMonitorService: ClaudeMonitorService?

    private var triggeredThresholds: Set<Int> = []
    private var lastKnownResetTime: String?
    private var lastTokenCount: Int?

    private init() {
        loadPersistedState()
        claudeMonitorService = ClaudeMonitorService(onCompletion: { [weak self] in
            Task { @MainActor in
                self?.handleClaudeCompletion()
            }
        })
    }

    func startMonitoring() {
        guard isMonitoring else { return }
        schedulePoll()
        claudeMonitorService?.start()
    }

    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        claudeMonitorService?.stop()
    }

    func toggleMonitoring() {
        isMonitoring.toggle()
        persistenceManager.save(key: "isMonitoring", value: isMonitoring)
        if isMonitoring {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func schedulePoll() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await poll()
                let interval = SettingsManager.shared.pollingInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func poll() async {
        do {
            let status = try await tokenService.fetchTokenStatus()
            await MainActor.run {
                self.handleNewStatus(status)
            }
        } catch {
            await MainActor.run {
                self.connectionStatus = .error(error.localizedDescription)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleNewStatus(_ newStatus: TokenStatus) {
        let wasReset = detectReset(newStatus: newStatus)

        if wasReset {
            triggeredThresholds.removeAll()
            notificationManager.sendResetNotification()
        }

        checkThresholds(newStatus: newStatus)

        tokenStatus = newStatus
        lastUpdated = Date()
        connectionStatus = .connected
        errorMessage = nil

        lastKnownResetTime = newStatus.resetTime
        lastTokenCount = newStatus.remainingTokens

        onIconUpdate?(newStatus.level)
        persistState()
    }

    private func detectReset(newStatus: TokenStatus) -> Bool {
        // Detect by reset_time change
        if let newReset = newStatus.resetTime,
           let oldReset = lastKnownResetTime,
           newReset != oldReset {
            return true
        }

        // Detect by token count jump upward
        if let newCount = newStatus.remainingTokens,
           let oldCount = lastTokenCount,
           newCount > oldCount + 1000 {
            return true
        }

        return false
    }

    private func checkThresholds(newStatus: TokenStatus) {
        let percent = newStatus.computedPercent
        let thresholds = SettingsManager.shared.notificationThresholds.sorted(by: >)

        for threshold in thresholds {
            if percent <= Double(threshold) && !triggeredThresholds.contains(threshold) {
                triggeredThresholds.insert(threshold)
                notificationManager.sendLowTokenNotification(percent: percent, threshold: threshold)
            }
        }
    }

    private func handleClaudeCompletion() {
        guard SettingsManager.shared.completionNotificationsEnabled else { return }
        notificationManager.sendCompletionNotification()
    }

    private func loadPersistedState() {
        isMonitoring = persistenceManager.load(key: "isMonitoring", defaultValue: true)
        lastKnownResetTime = persistenceManager.load(key: "lastResetTime", defaultValue: nil as String?)
        lastTokenCount = persistenceManager.load(key: "lastTokenCount", defaultValue: nil as Int?)
        if let thresholds: [Int] = persistenceManager.load(key: "triggeredThresholds", defaultValue: nil) {
            triggeredThresholds = Set(thresholds)
        }
    }

    private func persistState() {
        persistenceManager.save(key: "lastResetTime", value: lastKnownResetTime)
        persistenceManager.save(key: "lastTokenCount", value: lastTokenCount)
        persistenceManager.save(key: "triggeredThresholds", value: Array(triggeredThresholds))
    }

    func manualRefresh() {
        Task {
            await poll()
        }
    }
}

enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case error(String)

    var displayString: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
