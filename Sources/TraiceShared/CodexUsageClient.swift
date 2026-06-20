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

