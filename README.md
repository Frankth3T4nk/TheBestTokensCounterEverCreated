# Claude Tokens Notifier by Frank Leurs

A native macOS menu bar app that monitors Claude Code token usage and sends notifications.

## Features

- **Token Usage Monitoring** – Real-time display of remaining/total tokens with a visual gauge
- **Reset Notifications** – Alert when your token limit resets
- **Low Token Warnings** – Configurable thresholds (default: 75%, 50%, 25%, 0%)
- **Completion Detection** – Notifies when Claude finishes generating a response
- **Menu Bar Integration** – Lives in the menu bar, no Dock icon
- **Settings UI** – Full SwiftUI settings panel
- **Launch at Login** – Optional auto-start
- **Graceful Fallback** – Tries HTTP → local file → CLI in sequence

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Apple Developer account (free tier works for local builds)

## Building

### 1. Set Up Icons

Place your `AppIcon.png` (1024×1024 PNG) in the `ClaudeTokensNotifier/` project root, then run:

```bash
cd ClaudeTokensNotifier
bash Scripts/generate_icons.sh AppIcon.png
```

### 2. Open in Xcode

```bash
open ClaudeTokensNotifier.xcodeproj
```

### 3. Configure Signing

1. Select the `ClaudeTokensNotifier` target
2. Go to **Signing & Capabilities**
3. Set your **Team** (Apple ID works for local builds)
4. Bundle ID: `com.frankleurs.ClaudeTokensNotifier`

### 4. Build & Run

Press **⌘R** or go to **Product → Run**.

The app will appear in the menu bar.

## Creating a DMG for Distribution

### Prerequisites

```bash
brew install create-dmg
```

### Package

```bash
cd ClaudeTokensNotifier
bash Scripts/package_dmg.sh
```

Output: `build/dmg/Claude-Tokens-Notifier-1.0.0.dmg`

## Claude Code Integration

The app tries these data sources in order:

| Priority | Method | Description |
|----------|--------|-------------|
| 1 | HTTP endpoint | `http://localhost:PORT/token-status` (tries 27681, 3000, 8080, 9000) |
| 2 | Local file | `~/Library/Application Support/ClaudeCode/token_status.json` |
| 3 | CLI | `claude status --json` |

You can override both in **Settings → Connection**.

### Expected JSON Format

```json
{
  "remaining_tokens": 85000,
  "total_tokens": 200000,
  "reset_time": "2024-01-15T18:00:00Z"
}
```

Also supports: `remainingTokens`, `tokens_remaining`, `percent_remaining`, etc.

## Project Structure

```
ClaudeTokensNotifier/
├── ClaudeTokensNotifier.xcodeproj/
├── ClaudeTokensNotifier/
│   ├── ClaudeTokensNotifierApp.swift   # App entry point + AppDelegate
│   ├── Managers/
│   │   ├── AppState.swift              # Central state, monitoring logic
│   │   ├── NotificationManager.swift   # UserNotifications wrapper
│   │   ├── SettingsManager.swift       # User preferences (UserDefaults)
│   │   └── PersistenceManager.swift    # Codable state persistence
│   ├── Services/
│   │   ├── TokenService.swift          # HTTP / file / CLI fetching
│   │   └── ClaudeMonitorService.swift  # Process + log monitoring
│   ├── Views/
│   │   ├── MenuBarView.swift           # Menu bar popover UI
│   │   └── SettingsView.swift          # Settings window (tabbed)
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/
│   │   └── MenuBarIcon.imageset/
│   ├── Info.plist
│   └── ClaudeTokensNotifier.entitlements
└── Scripts/
    ├── generate_icons.sh               # Generate all icon sizes from source PNG
    └── package_dmg.sh                  # Build + package DMG
```

## Notifications

| Event | Message |
|-------|---------|
| Token reset | 👍🏼 Your Claude Code token limit has been reset |
| Low tokens | ⚠️ Claude Code tokens at X% remaining |
| Completion | ✅ Claude has finished generating your response |

## Settings

- **Thresholds** – Add/remove percentage thresholds for low-token alerts
- **Polling interval** – 10–300 seconds (default: 60s)
- **Completion notifications** – Toggle on/off
- **Custom endpoint** – Override HTTP URL
- **Custom file path** – Override local file path
- **Launch at login** – Auto-start with macOS

## License

Copyright © 2024 Frank Leurs. All rights reserved.
