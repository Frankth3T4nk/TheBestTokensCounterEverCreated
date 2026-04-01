import SwiftUI
import UserNotifications

@main
struct ClaudeTokensNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appState = AppState.shared
        self.appState = appState

        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestPermission()

        setupMenuBar()
        appState.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopMonitoring()
    }

    @MainActor private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusBarItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? makeTemplateIcon()
        button.image?.isTemplate = true
        button.action = #selector(togglePopover)
        button.target = self

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(appState: AppState.shared)
                .onOpenSettings { [weak self] in
                    self?.openSettings()
                }
        )
        self.popover = popover

        AppState.shared.onIconUpdate = { [weak self] level in
            self?.updateMenuBarIcon(level: level)
        }
    }

    private func makeTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
        circle.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateMenuBarIcon(level: TokenLevel) {
        guard let button = statusBarItem?.button else { return }
        let imageName: String
        switch level {
        case .full, .high:
            imageName = "MenuBarIcon"
        case .medium:
            imageName = "MenuBarIconMedium"
        case .low:
            imageName = "MenuBarIconLow"
        case .critical:
            imageName = "MenuBarIconCritical"
        case .unknown:
            imageName = "MenuBarIcon"
        }
        if let img = NSImage(named: imageName) {
            img.isTemplate = true
            button.image = img
        } else {
            button.image = makeTemplateIcon()
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusBarItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func openSettings() {
        popover?.performClose(nil)
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsView(appState: AppState.shared)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Claude Tokens Notifier – Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Environment key for settings callback
private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var openSettings: (() -> Void)? {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}
extension View {
    func onOpenSettings(_ action: @escaping () -> Void) -> some View {
        environment(\.openSettings, action)
    }
}
