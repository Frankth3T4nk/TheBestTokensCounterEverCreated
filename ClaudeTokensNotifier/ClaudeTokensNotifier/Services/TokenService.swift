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
        // Option A: HTTP endpoint
        if let status = try? await fetchFromHTTP() {
            return status
        }

        // Option B: Local file
        if let status = try? await fetchFromFile() {
            return status
        }

        // Option C: CLI
        if let status = try? await fetchFromCLI() {
            return status
        }

        throw TokenServiceError.noDataAvailable
    }

    // MARK: - Option A: HTTP endpoint
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

    // MARK: - Option B: Local file
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

    // MARK: - Option C: CLI
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
