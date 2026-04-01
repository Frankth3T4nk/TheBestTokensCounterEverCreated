import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @StateObject private var settings = SettingsManager.shared

    @State private var newThresholdText: String = ""
    @State private var newThresholdError: String? = nil
    @State private var showResetConfirm = false

    var body: some View {
        TabView {
            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            connectionTab
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 520, height: 560)
        .padding(20)
    }

    // MARK: - Notifications Tab
    private var notificationsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Token Thresholds", icon: "chart.bar")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Receive a notification when token usage reaches these percentages:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    // Threshold list
                    VStack(spacing: 4) {
                        ForEach(settings.notificationThresholds.sorted(by: >), id: \.self) { threshold in
                            HStack {
                                Image(systemName: "percent")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text("\(threshold)%")
                                    .font(.system(size: 13))
                                Spacer()
                                Button(action: { settings.removeThreshold(threshold) }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .disabled(settings.notificationThresholds.count <= 1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }

                    // Add threshold
                    HStack(spacing: 8) {
                        TextField("e.g. 80", text: $newThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: newThresholdText) { _ in
                                newThresholdError = nil
                            }
                        Text("%")
                            .foregroundColor(.secondary)
                        Button("Add") {
                            addThreshold()
                        }
                        .disabled(newThresholdText.isEmpty)

                        if let error = newThresholdError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                    }
                }

                Divider()

                sectionHeader("Completion Notifications", icon: "checkmark.circle")

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Notify when Claude finishes generating", isOn: $settings.completionNotificationsEnabled)
                        .font(.system(size: 13))

                    Text("Shows \"✅ Claude has finished generating your response\" after Claude completes a task.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Connection Tab
    private var connectionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Anthropic API Key", icon: "key")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-ant-...", text: $settings.anthropicApiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Clear") {
                            settings.anthropicApiKey = ""
                        }
                        .disabled(settings.anthropicApiKey.isEmpty)
                    }
                    Text("Enter your Anthropic API key to read live token rate-limit data. Get one at console.anthropic.com.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                sectionHeader("Polling Interval", icon: "timer")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Slider(
                            value: $settings.pollingInterval,
                            in: 10...300,
                            step: 10
                        ) {
                            Text("Interval")
                        }
                        Text("\(Int(settings.pollingInterval))s")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 45, alignment: .trailing)
                    }
                    Text("How often the app checks token usage. Lower values are more accurate but use more resources.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Divider()

                sectionHeader("Data Source", icon: "server.rack")

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom HTTP Endpoint")
                            .font(.system(size: 12, weight: .medium))
                        HStack {
                            TextField("http://localhost:PORT/token-status", text: $settings.customEndpoint)
                                .textFieldStyle(.roundedBorder)
                            Button("Clear") {
                                settings.customEndpoint = ""
                            }
                            .disabled(settings.customEndpoint.isEmpty)
                        }
                        Text("Leave empty to auto-detect on common ports (27681, 3000, 8080, 9000)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom File Path")
                            .font(.system(size: 12, weight: .medium))
                        HStack {
                            TextField("~/Library/Application Support/ClaudeCode/token_status.json",
                                      text: $settings.customFilePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                browseFile()
                            }
                            Button("Clear") {
                                settings.customFilePath = ""
                            }
                            .disabled(settings.customFilePath.isEmpty)
                        }
                        Text("Override the default file paths for reading token data")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Connection status display
                sectionHeader("Status", icon: "info.circle")

                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.connectionStatus.color)
                        .frame(width: 10, height: 10)
                    Text(appState.connectionStatus.displayString)
                        .font(.system(size: 12))

                    Spacer()

                    Button("Refresh Now") {
                        appState.manualRefresh()
                    }
                }

                if let error = appState.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(4)
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Startup", icon: "power")

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                        .font(.system(size: 13))
                    Text("Automatically start Claude Tokens Notifier when you log in to your Mac.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Divider()

                sectionHeader("About", icon: "info.circle")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude Tokens Notifier")
                                .font(.system(size: 14, weight: .semibold))
                            Text("by Frank Leurs")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("Version 1.0.0")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let icon = NSImage(named: "AppIcon") {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Text("Monitors Claude Code token usage and notifies you about token limits, resets, and completion.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                sectionHeader("Reset", icon: "arrow.counterclockwise")

                VStack(alignment: .leading, spacing: 8) {
                    Button("Reset All Settings to Defaults") {
                        showResetConfirm = true
                    }
                    .foregroundColor(.red)
                    .confirmationDialog(
                        "Reset all settings?",
                        isPresented: $showResetConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            settings.resetToDefaults()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will restore all settings to their default values.")
                    }

                    Text("Resets thresholds, polling interval, and connection settings.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Helpers
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func addThreshold() {
        let text = newThresholdText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(text) else {
            newThresholdError = "Must be a number"
            return
        }
        guard (0...100).contains(value) else {
            newThresholdError = "Must be 0–100"
            return
        }
        if settings.notificationThresholds.contains(value) {
            newThresholdError = "Already added"
            return
        }
        settings.addThreshold(value)
        newThresholdText = ""
        newThresholdError = nil
    }

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.title = "Select token_status.json"
        if panel.runModal() == .OK, let url = panel.url {
            settings.customFilePath = url.path
        }
    }
}
