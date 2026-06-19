import Foundation

enum CodexUsageConfig {
    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    static let usageSettingsURL = URL(string: "https://chatgpt.com/codex/settings/usage")!
    static let defaultAuthPath = "~/.codex/auth.json"
    static let refreshInterval: TimeInterval = 5 * 60
}

struct AuthFile: Decodable {
    let tokens: Tokens
}

struct Tokens: Decodable {
    let accessToken: String
    let accountID: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

struct UsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?
    let resetCredits: ResetCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case resetCredits = "rate_limit_reset_credits"
    }
}

struct RateLimit: Decodable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct UsageWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

struct ResetCredits: Decodable {
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

struct ResetCreditList: Decodable {
    let credits: [ResetCredit]?
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case credits
        case availableCount = "available_count"
    }
}

struct ResetCredit: Decodable {
    let title: String?
    let status: String?
    let expiresAtRaw: String?
    let grantedAtRaw: String?

    enum CodingKeys: String, CodingKey {
        case title
        case status
        case expiresAtRaw = "expires_at"
        case grantedAtRaw = "granted_at"
    }
}

struct CodexUsageSnapshot {
    let usage: UsageResponse
    let resetCreditList: ResetCreditList?
    let resetCreditError: String?
    let checkedAt: Date
}

struct CodexUsageDisplay {
    let primaryPercent: String
    let weeklyPercent: String
    let primaryUsageValue: Double
    let weeklyUsageValue: Double
    let primaryResetText: String
    let weeklyResetText: String
    let primaryResetRelativeText: String
    let weeklyResetRelativeText: String
    let planType: String?
    let allowedText: String
    let limitReachedText: String
    let resetCreditCount: Int?
    let resetCreditError: String?
    let creditSummaries: [CodexResetCreditDisplay]
    let checkedAtText: String

    init(snapshot: CodexUsageSnapshot, timezone: TimeZone = CodexUsageFormatting.configuredTimeZone()) {
        let response = snapshot.usage
        let primary = response.rateLimit?.primaryWindow
        let weekly = response.rateLimit?.secondaryWindow
        let now = snapshot.checkedAt

        primaryPercent = CodexUsageFormatting.formatPercent(primary?.usedPercent)
        weeklyPercent = CodexUsageFormatting.formatPercent(weekly?.usedPercent)
        primaryUsageValue = CodexUsageFormatting.clampedUnitValue(primary?.usedPercent)
        weeklyUsageValue = CodexUsageFormatting.clampedUnitValue(weekly?.usedPercent)
        primaryResetText = CodexUsageFormatting.formatReset(primary, timezone: timezone, now: now)
        weeklyResetText = CodexUsageFormatting.formatReset(weekly, timezone: timezone, now: now)
        primaryResetRelativeText = CodexUsageFormatting.formatOptionalRelative(
            CodexUsageFormatting.resetDate(primary),
            now: now
        )
        weeklyResetRelativeText = CodexUsageFormatting.formatOptionalRelative(
            CodexUsageFormatting.resetDate(weekly),
            now: now
        )
        planType = response.planType
        allowedText = CodexUsageFormatting.yesNo(response.rateLimit?.allowed)
        limitReachedText = CodexUsageFormatting.yesNo(response.rateLimit?.limitReached)
        resetCreditCount = snapshot.resetCreditList?.availableCount ?? response.resetCredits?.availableCount
        resetCreditError = snapshot.resetCreditError
        checkedAtText = CodexUsageFormatting.formatDate(now, timezone: timezone)

        let credits = snapshot.resetCreditList?.credits ?? []
        creditSummaries = credits
            .sorted { left, right in
                (CodexUsageFormatting.parseISODate(left.expiresAtRaw) ?? .distantFuture)
                    < (CodexUsageFormatting.parseISODate(right.expiresAtRaw) ?? .distantFuture)
            }
            .enumerated()
            .map { index, credit in
                let expiresAt = CodexUsageFormatting.parseISODate(credit.expiresAtRaw)
                return CodexResetCreditDisplay(
                    id: "\(index)-\(credit.title ?? "reset")-\(credit.expiresAtRaw ?? "")",
                    title: credit.title ?? "Codex reset",
                    status: credit.status ?? "unknown",
                    expiresText: CodexUsageFormatting.formatOptionalDate(expiresAt, timezone: timezone),
                    expiresRelativeText: CodexUsageFormatting.formatOptionalRelative(expiresAt, now: now),
                    grantedText: CodexUsageFormatting.formatOptionalDate(
                        CodexUsageFormatting.parseISODate(credit.grantedAtRaw),
                        timezone: timezone
                    )
                )
            }
    }
}

struct CodexResetCreditDisplay: Identifiable {
    let id: String
    let title: String
    let status: String
    let expiresText: String
    let expiresRelativeText: String
    let grantedText: String
}

