import Foundation

enum CodexUsageError: LocalizedError {
    case missingData
    case invalidHTTPResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingData:
            return "No response body returned."
        case .invalidHTTPResponse:
            return "The API returned a non-HTTP response."
        case .httpError(let code):
            return "HTTP \(code): \(HTTPURLResponse.localizedString(forStatusCode: code))"
        }
    }
}

final class CodexUsageClient {
    func fetchSnapshot(checkedAt: Date = Date()) async throws -> CodexUsageSnapshot {
        let tokens = try loadTokens()
        let usage: UsageResponse = try await fetchJSON(CodexUsageConfig.usageEndpoint, tokens: tokens)

        do {
            let resetCreditList: ResetCreditList = try await fetchJSON(CodexUsageConfig.resetCreditsEndpoint, tokens: tokens)
            return CodexUsageSnapshot(
                usage: usage,
                resetCreditList: resetCreditList,
                resetCreditError: nil,
                checkedAt: checkedAt
            )
        } catch {
            return CodexUsageSnapshot(
                usage: usage,
                resetCreditList: nil,
                resetCreditError: error.localizedDescription,
                checkedAt: checkedAt
            )
        }
    }

    private func loadTokens() throws -> Tokens {
        let data = try Data(contentsOf: URL(fileURLWithPath: CodexUsageFormatting.authPath()))
        return try JSONDecoder().decode(AuthFile.self, from: data).tokens
    }

    private func fetchJSON<T: Decodable>(_ url: URL, tokens: Tokens) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = CodexUsageFormatting.timeoutSeconds()
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodexUsageError.httpError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw CodexUsageError.missingData
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum CursorUsageError: LocalizedError {
    case disabled
    case missingAuthDatabase
    case missingAccessToken
    case invalidAccessToken
    case sqliteFailed(String)
    case invalidHTTPResponse
    case httpError(Int)
    case missingData

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Cursor usage is disabled."
        case .missingAuthDatabase:
            return "Cursor auth database was not found."
        case .missingAccessToken:
            return "Cursor access token was not found."
        case .invalidAccessToken:
            return "Cursor access token could not be parsed."
        case .sqliteFailed(let message):
            return "Could not read Cursor auth database: \(message)"
        case .invalidHTTPResponse:
            return "The Cursor API returned a non-HTTP response."
        case .httpError(let code):
            return "HTTP \(code): \(HTTPURLResponse.localizedString(forStatusCode: code))"
        case .missingData:
            return "No response body returned."
        }
    }
}

final class CursorUsageClient {
    func fetchSnapshot(checkedAt: Date = Date()) async -> CursorUsageSnapshot {
        do {
            let auth = try loadAuth()

            async let currentPeriodUsage: CursorCurrentPeriodUsageResponse? = optionalFetchCurrentPeriodUsage(auth: auth)
            async let legacyUsage: CursorLegacyUsageResponse? = optionalFetchLegacyUsage(auth: auth)
            async let stripe: CursorStripeResponse? = optionalFetchStripe(auth: auth)

            // TODO: Preserve a fetch error when every optional Cursor usage request fails.
            return CursorUsageSnapshot(
                currentPeriodUsage: await currentPeriodUsage,
                legacyUsage: await legacyUsage,
                stripe: await stripe,
                error: nil,
                checkedAt: checkedAt
            )
        } catch {
            return CursorUsageSnapshot(
                currentPeriodUsage: nil,
                legacyUsage: nil,
                stripe: nil,
                error: error.localizedDescription,
                checkedAt: checkedAt
            )
        }
    }

    private struct CursorAuth {
        let accessToken: String
        let userID: String
        let sessionToken: String
    }

    private func optionalFetchCurrentPeriodUsage(auth: CursorAuth) async -> CursorCurrentPeriodUsageResponse? {
        try? await fetchJSON(
            CursorUsageConfig.currentPeriodUsageEndpoint,
            method: "POST",
            body: "{}".data(using: .utf8),
            headers: [
                "Authorization": "Bearer \(auth.accessToken)",
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1"
            ]
        )
    }

    private func optionalFetchLegacyUsage(auth: CursorAuth) async -> CursorLegacyUsageResponse? {
        var components = URLComponents(url: CursorUsageConfig.usageEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user", value: auth.userID)]
        guard let url = components?.url else { return nil }

        return try? await fetchJSON(
            url,
            headers: [
                "Cookie": "WorkosCursorSessionToken=\(auth.sessionToken)"
            ]
        )
    }

    private func optionalFetchStripe(auth: CursorAuth) async -> CursorStripeResponse? {
        try? await fetchJSON(
            CursorUsageConfig.stripeEndpoint,
            headers: [
                "Cookie": "WorkosCursorSessionToken=\(auth.sessionToken)"
            ]
        )
    }

    private func loadAuth() throws -> CursorAuth {
        if ProcessInfo.processInfo.environment["CURSOR_USAGE_ENABLED"] == "0" {
            throw CursorUsageError.disabled
        }

        let path = CodexUsageFormatting.expandedPath(
            ProcessInfo.processInfo.environment["CURSOR_AUTH_DB_PATH"]
                ?? CursorUsageConfig.defaultAuthDatabasePath
        )
        guard FileManager.default.fileExists(atPath: path) else {
            throw CursorUsageError.missingAuthDatabase
        }

        let token = try readSQLiteValue(
            databasePath: path,
            key: "cursorAuth/accessToken"
        )
        guard !token.isEmpty else {
            throw CursorUsageError.missingAccessToken
        }

        let userID = try userID(fromJWT: token)
        return CursorAuth(
            accessToken: token,
            userID: userID,
            sessionToken: "\(userID)%3A%3A\(token)"
        )
    }

    private func readSQLiteValue(databasePath: String, key: String) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            databasePath,
            "select value from ItemTable where key = '\(key.replacingOccurrences(of: "'", with: "''"))' limit 1;"
        ]
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard process.terminationStatus == 0 else {
            throw CursorUsageError.sqliteFailed(errorText.isEmpty ? "sqlite3 exited with status \(process.terminationStatus)" : errorText)
        }

        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    private func userID(fromJWT token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { throw CursorUsageError.invalidAccessToken }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String else {
            throw CursorUsageError.invalidAccessToken
        }

        if subject.hasPrefix("auth0|") {
            return String(subject.dropFirst("auth0|".count))
        }
        return subject
    }

    private func fetchJSON<T: Decodable>(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeoutSeconds()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CursorUsageError.httpError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw CursorUsageError.missingData
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func timeoutSeconds() -> TimeInterval {
        let raw = ProcessInfo.processInfo.environment["CURSOR_USAGE_TIMEOUT"]
            ?? ProcessInfo.processInfo.environment["CODEX_USAGE_TIMEOUT"]
            ?? "60"
        return Double(raw) ?? 60
    }
}
