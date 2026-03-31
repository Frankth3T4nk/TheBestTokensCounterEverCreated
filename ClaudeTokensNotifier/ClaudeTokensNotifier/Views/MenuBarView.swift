import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) var openSettings
    @StateObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Token status
            tokenSection

            Divider()

            // Quick toggles
            toggleSection

            Divider()

            // Actions
            actionSection
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Tokens Notifier")
                        .font(.system(size: 13, weight: .semibold))
                    Text("by Frank Leurs")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(appState.connectionStatus.color)
                .frame(width: 7, height: 7)
            Text(appState.connectionStatus == .connected ? "Live" : "Offline")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Token Section
    private var tokenSection: some View {
        VStack(spacing: 12) {
            // Token percentage gauge
            tokenGauge

            // Token details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let remaining = appState.tokenStatus.remainingTokens {
                        Text(formatNumber(remaining))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    } else {
                        Text("–")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let total = appState.tokenStatus.totalTokens {
                        Text(formatNumber(total))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    } else {
                        Text("–")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Last reset time
            if let resetTime = appState.tokenStatus.resetTime {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Resets: \(formatResetTime(resetTime))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // Last updated
            if let updated = appState.lastUpdated {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Updated \(timeAgo(updated))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { appState.manualRefresh() }) {
                        Text("Refresh")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tokenGauge: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Token Usage")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", appState.tokenStatus.computedPercent) + " remaining")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(gaugeColor(appState.tokenStatus.computedPercent))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(gaugeColor(appState.tokenStatus.computedPercent))
                        .frame(
                            width: max(4, geometry.size.width * CGFloat(appState.tokenStatus.computedPercent / 100.0)),
                            height: 8
                        )
                        .animation(.easeInOut(duration: 0.5), value: appState.tokenStatus.computedPercent)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Toggle Section
    private var toggleSection: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "Monitoring",
                subtitle: appState.isMonitoring ? "Active" : "Paused",
                icon: "waveform",
                isOn: Binding(
                    get: { appState.isMonitoring },
                    set: { _ in appState.toggleMonitoring() }
                )
            )

            Divider().padding(.leading, 44)

            toggleRow(
                title: "Completion Notifications",
                subtitle: "Alert when Claude finishes",
                icon: "bell",
                isOn: Binding(
                    get: { settings.completionNotificationsEnabled },
                    set: { val in settings.completionNotificationsEnabled = val }
                )
            )
        }
    }

    private func toggleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Action Section
    private var actionSection: some View {
        VStack(spacing: 0) {
            menuButton(title: "Open Settings", icon: "gear") {
                openSettings?()
            }

            Divider().padding(.leading, 44)

            menuButton(title: "Quit", icon: "power", color: .red) {
                NSApp.terminate(nil)
            }
        }
    }

    private func menuButton(title: String, icon: String, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color == .primary ? .accentColor : color)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(0.001) // for hover hit testing
        )
    }

    // MARK: - Helpers
    private func gaugeColor(_ percent: Double) -> Color {
        if percent > 50 { return .green }
        if percent > 25 { return .orange }
        return .red
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatResetTime(_ raw: String) -> String {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "MM/dd/yyyy HH:mm"
        ]
        let formatter = DateFormatter()
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                let display = DateFormatter()
                display.dateStyle = .none
                display.timeStyle = .short
                return display.string(from: date)
            }
        }
        return raw
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
