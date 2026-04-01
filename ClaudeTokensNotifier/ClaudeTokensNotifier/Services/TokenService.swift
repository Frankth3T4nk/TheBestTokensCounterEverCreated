import Foundation

enum TokenServiceError: LocalizedError {
    case noDataAvailable
    case decodingFailed(String)
    case networkError(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .noDataAvailable: return "No token data available from any source"
        case .decodingFailed(let msg): return "Decoding failed: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .fileNotFound: return "Token status file not found"
        }
    }
}

class TokenService {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func fetchTokenStatus() async throws -> TokenStatus {
        // Option A: Anthropic API rate-limit headers (requires API key in Settings)
        if let status = try? await fetchFromAnthropicAPI() {
            return status
        }

        // Option B: Custom HTTP endpoint
        if let status = try? await fetchFromHTTP() {
            return status
        }

        // Option C: Local file
        if let status = try? await fetchFromFile() {
            return status
        }

        // Option D: Claude Code session JSONL files (~/.claude/projects/)
        if let status = try? await fetchFromClaudeSessionFiles() {
            return status
        }

        // Option E: CLI (claude status --json)
        if let status = try? await fetchFromCLI() {
            return status
        }

        throw TokenServiceError.noDataAvailable
    }

    // MARK: - Option A: Anthropic API rate-limit headers
    private func fetchFromAnthropicAPI() async throws -> TokenStatus {
        let apiKey = SettingsManager.shared.anthropicApiKey
        guard !apiKey.isEmpty else {
            throw TokenServiceError.noDataAvailable
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw TokenServiceError.networkError("Invalid Anthropic API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenServiceError.networkError("No HTTP response from Anthropic API")
        }

        // 401 means bad key — surface that clearly
        if httpResponse.statusCode == 401 {
            throw TokenServiceError.networkError("Invalid API key — check Settings")
        }

        // Extract token rate-limit headers (present on all Anthropic API responses)
        let headers = httpResponse.allHeaderFields as? [String: String] ?? [:]

        // Try both header casing variants (URLSession lowercases them on some OS versions)
        func header(_ name: String) -> String? {
            headers[name] ?? headers[name.lowercased()]
        }

        let remaining = header("anthropic-ratelimit-tokens-remaining").flatMap { Int($0) }
        let limit     = header("anthropic-ratelimit-tokens-limit").flatMap { Int($0) }
        let resetTime = header("anthropic-ratelimit-tokens-reset")

        guard let remaining, let limit else {
            throw TokenServiceError.noDataAvailable
        }

        var status = TokenStatus()
        status.remainingTokens = remaining
        status.totalTokens = limit
        status.resetTime = resetTime
        return status
    }

    // MARK: - Option B: HTTP endpoint
    private func fetchFromHTTP() async throws -> TokenStatus {
        let customEndpoint = SettingsManager.shared.customEndpoint
        let ports = customEndpoint.isEmpty ? [27681, 3000, 8080, 9000] : []

        if !customEndpoint.isEmpty {
            return try await fetchFromURL(customEndpoint)
        }

        var lastError: Error = TokenServiceError.noDataAvailable
        for port in ports {
            do {
                let status = try await fetchFromURL("http://localhost:\(port)/token-status")
                return status
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func fetchFromURL(_ urlString: String) async throws -> TokenStatus {
        guard let url = URL(string: urlString) else {
            throw TokenServiceError.networkError("Invalid URL: \(urlString)")
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TokenServiceError.networkError("Bad HTTP response")
        }

        do {
            return try decoder.decode(TokenStatus.self, from: data)
        } catch {
            // Try flexible parsing
            return try parseFlexibleJSON(data: data)
        }
    }

    // MARK: - Option C: Local file
    private func fetchFromFile() async throws -> TokenStatus {
        let customPath = SettingsManager.shared.customFilePath

        let paths: [URL]
        if !customPath.isEmpty {
            paths = [URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)]
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            paths = [
                home.appendingPathComponent("Library/Application Support/ClaudeCode/token_status.json"),
                home.appendingPathComponent(".claude/token_status.json"),
                home.appendingPathComponent("Library/Application Support/Claude/token_status.json")
            ]
        }

        for fileURL in paths {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                do {
                    return try decoder.decode(TokenStatus.self, from: data)
                } catch {
                    return try parseFlexibleJSON(data: data)
                }
            }
        }

        throw TokenServiceError.fileNotFound
    }

    // MARK: - Option C: Claude Code session JSONL files
    private func fetchFromClaudeSessionFiles() async throws -> TokenStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            throw TokenServiceError.fileNotFound
        }

        // Collect all JSONL files across project subdirectories
        let projectDirs = (try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        var allJSONLFiles: [(URL, Date)] = []
        for dir in projectDirs {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "jsonl" }) ?? []

            for file in files {
                let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                let modDate = attrs?.contentModificationDate ?? Date.distantPast
                allJSONLFiles.append((file, modDate))
            }
        }

        // Also check ~/.claude/*.jsonl (legacy location)
        let legacyDir = home.appendingPathComponent(".claude")
        let legacyFiles = (try? FileManager.default.contentsOfDirectory(
            at: legacyDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "jsonl" }) ?? []
        for file in legacyFiles {
            let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            let modDate = attrs?.contentModificationDate ?? Date.distantPast
            allJSONLFiles.append((file, modDate))
        }

        // Most recently modified file = active session
        allJSONLFiles.sort { $0.1 > $1.1 }

        guard let mostRecentFile = allJSONLFiles.first else {
            throw TokenServiceError.fileNotFound
        }

        return try parseSessionJSONL(at: mostRecentFile.0, modDate: mostRecentFile.1)
    }

    private func parseSessionJSONL(at url: URL, modDate: Date) throws -> TokenStatus {
        let data = try Data(contentsOf: url)
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Each API call sends the full context, so the LAST assistant message's
        // input_tokens reflects the current context window usage.
        var lastInputTokens: Int?
        var lastOutputTokens = 0
        var detectedModel: String?
        var sessionStartTimestamp: String?

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // Capture session start time from the first entry
            if sessionStartTimestamp == nil, let ts = entry["timestamp"] as? String {
                sessionStartTimestamp = ts
            }

            guard let type = entry["type"] as? String, type == "assistant",
                  let message = entry["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            if let model = message["model"] as? String {
                detectedModel = model
            }

            if let inputToks = usage["input_tokens"] as? Int {
                lastInputTokens = inputToks
            }
            if let outputToks = usage["output_tokens"] as? Int {
                lastOutputTokens = outputToks
            }
        }

        guard let inputTokens = lastInputTokens else {
            throw TokenServiceError.noDataAvailable
        }

        // Determine context window size based on model (all modern Claude = 200k)
        let contextWindow: Int
        if let model = detectedModel, model.contains("haiku") {
            contextWindow = 200_000
        } else {
            contextWindow = 200_000
        }

        let usedTokens = inputTokens + lastOutputTokens
        let remaining = max(0, contextWindow - inputTokens)

        var status = TokenStatus()
        status.remainingTokens = remaining
        status.totalTokens = contextWindow
        status.usedTokens = usedTokens
        status.resetTime = sessionStartTimestamp

        return status
    }

    // MARK: - Option D: CLI
    private func fetchFromCLI() async throws -> TokenStatus {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "claude status --json 2>/dev/null || npx claude status --json 2>/dev/null"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.launch()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if data.isEmpty {
                    continuation.resume(throwing: TokenServiceError.noDataAvailable)
                    return
                }

                do {
                    let status = try JSONDecoder().decode(TokenStatus.self, from: data)
                    continuation.resume(returning: status)
                } catch {
                    do {
                        let status = try self.parseFlexibleJSON(data: data)
                        continuation.resume(returning: status)
                    } catch {
                        continuation.resume(throwing: TokenServiceError.decodingFailed(error.localizedDescription))
                    }
                }
            } catch {
                continuation.resume(throwing: TokenServiceError.networkError(error.localizedDescription))
            }
        }
    }

    // MARK: - Flexible JSON parser
    private func parseFlexibleJSON(data: Data) throws -> TokenStatus {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenServiceError.decodingFailed("Not a valid JSON object")
        }

        var status = TokenStatus()

        // Try multiple key variations
        let remainingKeys = ["remaining_tokens", "remainingTokens", "remaining", "tokens_remaining", "tokensRemaining"]
        let totalKeys = ["total_tokens", "totalTokens", "total", "limit", "token_limit", "tokenLimit"]
        let resetKeys = ["reset_time", "resetTime", "reset_at", "resetAt", "next_reset"]
        let percentKeys = ["percent_remaining", "percentRemaining", "percent", "percentage_remaining"]

        for key in remainingKeys {
            if let val = json[key] as? Int { status.remainingTokens = val; break }
            if let val = json[key] as? Double { status.remainingTokens = Int(val); break }
        }
        for key in totalKeys {
            if let val = json[key] as? Int { status.totalTokens = val; break }
            if let val = json[key] as? Double { status.totalTokens = Int(val); break }
        }
        for key in resetKeys {
            if let val = json[key] as? String { status.resetTime = val; break }
        }
        for key in percentKeys {
            if let val = json[key] as? Double { status.percentRemaining = val; break }
            if let val = json[key] as? Int { status.percentRemaining = Double(val); break }
        }

        if status.remainingTokens == nil && status.percentRemaining == nil {
            throw TokenServiceError.decodingFailed("Could not find token data in JSON response")
        }

        return status
    }
}
