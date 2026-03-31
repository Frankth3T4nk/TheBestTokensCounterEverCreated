import Foundation

class ClaudeMonitorService {
    private var onCompletion: (() -> Void)
    private var monitorTask: Task<Void, Never>?
    private var lastSeenProcesses: Set<Int32> = []
    private var logWatcher: LogWatcher?
    private var lastCompletionTime: Date?
    private let dedupeInterval: TimeInterval = 5.0

    init(onCompletion: @escaping (() -> Void)) {
        self.onCompletion = onCompletion
    }

    func start() {
        startProcessMonitoring()
        startLogWatching()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        logWatcher?.stop()
        logWatcher = nil
    }

    // MARK: - Process Monitoring
    private func startProcessMonitoring() {
        monitorTask = Task {
            while !Task.isCancelled {
                checkClaudeProcesses()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func checkClaudeProcesses() {
        let currentProcesses = getClaudeProcessIDs()

        // Find processes that were running before but are now gone
        let completedProcesses = lastSeenProcesses.subtracting(currentProcesses)

        if !completedProcesses.isEmpty && !lastSeenProcesses.isEmpty {
            fireCompletionIfNeeded()
        }

        lastSeenProcesses = currentProcesses
    }

    private func getClaudeProcessIDs() -> Set<Int32> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "pgrep -f 'claude' 2>/dev/null || true"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var pids = Set<Int32>()
        do {
            try process.launch()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let pid = Int32(trimmed) {
                        pids.insert(pid)
                    }
                }
            }
        } catch {
            // Process monitoring unavailable
        }
        return pids
    }

    // MARK: - Log Watching
    private func startLogWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logPaths = [
            home.appendingPathComponent(".claude/logs/claude.log"),
            home.appendingPathComponent("Library/Logs/Claude/claude.log"),
            home.appendingPathComponent("Library/Application Support/ClaudeCode/claude.log")
        ]

        for path in logPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                logWatcher = LogWatcher(fileURL: path) { [weak self] line in
                    self?.handleLogLine(line)
                }
                logWatcher?.start()
                break
            }
        }
    }

    private func handleLogLine(_ line: String) {
        let completionMarkers = [
            "generation complete",
            "response complete",
            "finished generating",
            "task complete",
            "done",
            "assistant:",
            "[done]",
            "stop_reason: end_turn"
        ]

        let lowercased = line.lowercased()
        for marker in completionMarkers {
            if lowercased.contains(marker) {
                fireCompletionIfNeeded()
                break
            }
        }
    }

    // MARK: - Deduplication
    private func fireCompletionIfNeeded() {
        let now = Date()
        if let last = lastCompletionTime, now.timeIntervalSince(last) < dedupeInterval {
            return
        }
        lastCompletionTime = now
        onCompletion()
    }
}

// MARK: - Log File Watcher
class LogWatcher {
    private let fileURL: URL
    private let lineHandler: (String) -> Void
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0

    init(fileURL: URL, lineHandler: @escaping (String) -> Void) {
        self.fileURL = fileURL
        self.lineHandler = lineHandler
    }

    func start() {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return }
        self.fileHandle = fh

        // Seek to end so we only watch new content
        lastOffset = fh.seekToEndOfFile()

        let fd = fh.fileDescriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )

        source?.setEventHandler { [weak self] in
            self?.readNewContent()
        }
        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileHandle?.closeFile()
        fileHandle = nil
    }

    private func readNewContent() {
        guard let fh = fileHandle else { return }
        fh.seek(toFileOffset: lastOffset)
        let data = fh.readDataToEndOfFile()
        lastOffset = fh.offsetInFile

        if let text = String(data: data, encoding: .utf8) {
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    lineHandler(trimmed)
                }
            }
        }
    }
}
