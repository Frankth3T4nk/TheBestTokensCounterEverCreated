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
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func fetchTokenStatus() async throws -> TokenStatus {
        let apiKey = SettingsManager.shared.anthropicApiKey

        // Option A: Anthropic API — POST /v1/messages (max_tokens:1) returns
        // anthropic-ratelimit-tokens-* headers showing live rate-limit window.
        // NOTE: count_tokens does NOT return these headers; only /v1/messages does.
        if !apiKey.isEmpty {
            return try await fetchFromAnthropicAPI()
        }

        // Option B: Custom HTTP endpoint
        if let status = try? await fetchFromHTTP() {
            return status
        }

        // Option C: Local JSON file
        if let status = try? await fetchFromFile() {
            return status
        }

        // Option D: Claude Code session JSONL files
        // Checks both ~/.claude/projects/ and ~/.config/claude/projects/
        if let status = try? await fetchFromClaudeSessionFiles() {
            return status
        }

        // Option E: CLI fallback
        if let status = try? await fetchFromCLI() {
            return status
        }

        throw TokenServiceError.noDataAvailable
    }

    // MARK: - Option A: Anthropic API (live rate-limit headers)

    private func fetchFromAnthropicAPI() async throws -> TokenStatus {
        let apiKey = SettingsManager.shared.anthropicApiKey

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw TokenServiceError.networkError("Invalid Anthropic API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Minimal request — cheapest possible call (Haiku, 1 output token).
        // /v1/messages is the only endpoint that returns anthropic-ratelimit-tokens-* headers.
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TokenServiceError.networkError("No HTTP response from Anthropic API")
        }

        if http.statusCode == 401 {
            throw TokenServiceError.networkError("Invalid API key — update it in Settings → Connection")
        }
        if http.statusCode == 529 {
            throw TokenServiceError.networkError("Anthropic API overloaded — will retry next poll")
        }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 429 else {
            throw TokenServiceError.networkError("Anthropic API returned HTTP \(http.statusCode)")
        }

        // HTTPURLResponse.value(forHTTPHeaderField:) is case-insensitive (RFC 7230).
        let remaining = http.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-remaining").flatMap { Int($0) }
        let limit     = http.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-limit").flatMap { Int($0) }
        let resetTime = http.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-reset")

        guard let remaining, let limit else {
            throw TokenServiceError.networkError("API key valid but token rate-limit headers missing")
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

        if !customEndpoint.isEmpty {
            return try await fetchFromURL(customEndpoint)
        }

        var lastError: Error = TokenServiceError.noDataAvailable
        for port in [27681, 3000, 8080, 9000] {
            do {
                return try await fetchFromURL("http://localhost:\(port)/token-status")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func fetchFromURL(_ urlString: String) async throws -> TokenStatus {
        guard let url = URL(string: urlString) else {
            throw TokenServiceError.networkError("Invalid URL: \(urlString)")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TokenServiceError.networkError("Bad HTTP response")
        }
        do {
            return try decoder.decode(TokenStatus.self, from: data)
        } catch {
            return try parseFlexibleJSON(data: data)
        }
    }

    // MARK: - Option C: Local JSON file

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
                do { return try decoder.decode(TokenStatus.self, from: data) }
                catch { return try parseFlexibleJSON(data: data) }
            }
        }
        throw TokenServiceError.fileNotFound
    }

    // MARK: - Option D: Claude Code session JSONL files

    private func fetchFromClaudeSessionFiles() async throws -> TokenStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Claude Code stores sessions in one of two root directories depending on version:
        // ~/.claude/projects/          — classic location
        // ~/.config/claude/projects/  — default since Claude Code 1.0.30
        let rootCandidates = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects")
        ]

        var allJSONLFiles: [(URL, Date)] = []

        for root in rootCandidates {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }

            let projectDirs = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )) ?? []

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
        }

        // Most recently modified file = active session
        allJSONLFiles.sort { $0.1 > $1.1 }

        guard let (fileURL, _) = allJSONLFiles.first else {
            throw TokenServiceError.fileNotFound
        }

        return try parseSessionJSONL(at: fileURL)
    }

    private func parseSessionJSONL(at url: URL) throws -> TokenStatus {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Each Claude Code API call sends the entire accumulated context, so the LAST
        // assistant message's token counts reflect current context window usage.
        var lastInputTokens: Int?
        var lastCacheRead = 0
        var lastCacheCreation = 0
        var lastOutputTokens = 0
        var detectedModel: String?
        var sessionStartTimestamp: String?

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if sessionStartTimestamp == nil {
                sessionStartTimestamp = entry["timestamp"] as? String
            }

            guard let type = entry["type"] as? String, type == "assistant",
                  let message = entry["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            if let model = message["model"] as? String { detectedModel = model }

            // All three fields contribute to context window consumption.
            lastInputTokens    = usage["input_tokens"] as? Int
            lastCacheRead      = usage["cache_read_input_tokens"] as? Int ?? 0
            lastCacheCreation  = usage["cache_creation_input_tokens"] as? Int ?? 0
            lastOutputTokens   = usage["output_tokens"] as? Int ?? 0
        }

        guard let inputTokens = lastInputTokens else {
            throw TokenServiceError.noDataAvailable
        }

        // True context window usage = uncached + cached-read + cache-creation tokens.
        let contextUsed = inputTokens + lastCacheRead + lastCacheCreation
        let contextWindow = 200_000  // all current Claude models (Haiku/Sonnet/Opus)
        let remaining = max(0, contextWindow - contextUsed)
        let usedTotal = contextUsed + lastOutputTokens

        var status = TokenStatus()
        status.remainingTokens = remaining
        status.totalTokens = contextWindow
        status.usedTokens = usedTotal
        status.resetTime = sessionStartTimestamp

        if let model = detectedModel {
            // Embed model name in resetTime field as fallback display hint
            // Only if no real timestamp was found
            if status.resetTime == nil { status.resetTime = "Session: \(model)" }
        }

        return status
    }

    // MARK: - Option E: CLI

    private func fetchFromCLI() async throws -> TokenStatus {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "claude status --json 2>/dev/null"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.launch()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard !data.isEmpty else {
                    continuation.resume(throwing: TokenServiceError.noDataAvailable)
                    return
                }
                do {
                    continuation.resume(returning: try JSONDecoder().decode(TokenStatus.self, from: data))
                } catch {
                    do {
                        continuation.resume(returning: try self.parseFlexibleJSON(data: data))
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

        let remainingKeys = ["remaining_tokens", "remainingTokens", "remaining", "tokens_remaining", "tokensRemaining"]
        let totalKeys     = ["total_tokens", "totalTokens", "total", "limit", "token_limit", "tokenLimit"]
        let resetKeys     = ["reset_time", "resetTime", "reset_at", "resetAt", "next_reset"]
        let percentKeys   = ["percent_remaining", "percentRemaining", "percent", "percentage_remaining"]

        for key in remainingKeys {
            if let val = json[key] as? Int    { status.remainingTokens = val;      break }
            if let val = json[key] as? Double { status.remainingTokens = Int(val); break }
        }
        for key in totalKeys {
            if let val = json[key] as? Int    { status.totalTokens = val;      break }
            if let val = json[key] as? Double { status.totalTokens = Int(val); break }
        }
        for key in resetKeys {
            if let val = json[key] as? String { status.resetTime = val; break }
        }
        for key in percentKeys {
            if let val = json[key] as? Double { status.percentRemaining = val;        break }
            if let val = json[key] as? Int    { status.percentRemaining = Double(val); break }
        }

        if status.remainingTokens == nil && status.percentRemaining == nil {
            throw TokenServiceError.decodingFailed("Could not find token data in JSON response")
        }

        return status
    }
}
