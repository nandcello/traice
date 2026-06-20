import Foundation

enum CodexUsageConfig {
    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    static let usageSettingsURL = URL(string: "https://chatgpt.com/codex/settings/usage")!
    static let defaultAuthPath = "~/.codex/auth.json"
    static let menuBarRefreshInterval: TimeInterval = 30
    static let menuOpenRefreshAge: TimeInterval = 10
    static let widgetRefreshInterval: TimeInterval = 5 * 60
    static let cachedSnapshotMaxAge: TimeInterval = 45
    static let snapshotCachePath = "~/Library/Application Support/Traice/usage-snapshot.json"
}

struct AuthFile: Codable {
    let tokens: Tokens
}

struct Tokens: Codable {
    let accessToken: String
    let accountID: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

struct UsageResponse: Codable {
    let planType: String?
    let rateLimit: RateLimit?
    let resetCredits: ResetCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case resetCredits = "rate_limit_reset_credits"
    }
}

struct RateLimit: Codable {
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

struct UsageWindow: Codable {
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

struct ResetCredits: Codable {
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

struct ResetCreditList: Codable {
    let credits: [ResetCredit]?
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case credits
        case availableCount = "available_count"
    }
}

struct ResetCredit: Codable {
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

struct CodexUsageSnapshot: Codable {
    let usage: UsageResponse
    let resetCreditList: ResetCreditList?
    let resetCreditError: String?
    let checkedAt: Date
}

enum CodexUsageSnapshotStore {
    static func loadCachedSnapshot(from url: URL = snapshotURL()) -> CodexUsageSnapshot? {
        try? loadSnapshot(from: url)
    }

    static func loadFreshSnapshot(
        now: Date = Date(),
        maxAge: TimeInterval = CodexUsageConfig.cachedSnapshotMaxAge,
        from url: URL = snapshotURL()
    ) -> CodexUsageSnapshot? {
        guard let snapshot = loadCachedSnapshot(from: url) else { return nil }
        return isFresh(snapshot, now: now, maxAge: maxAge) ? snapshot : nil
    }

    static func loadSnapshot(from url: URL = snapshotURL()) throws -> CodexUsageSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: CodexUsageSnapshot, to url: URL = snapshotURL()) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    static func isFresh(
        _ snapshot: CodexUsageSnapshot,
        now: Date = Date(),
        maxAge: TimeInterval = CodexUsageConfig.cachedSnapshotMaxAge
    ) -> Bool {
        abs(now.timeIntervalSince(snapshot.checkedAt)) <= maxAge
    }

    static func snapshotURL() -> URL {
        URL(fileURLWithPath: CodexUsageFormatting.expandedPath(CodexUsageConfig.snapshotCachePath))
    }
}

struct CodexUsageDisplay {
    let primaryPercent: String
    let weeklyPercent: String
    let primaryUsageValue: Double
    let weeklyUsageValue: Double
    let primaryResetText: String
    let primaryResetAbsoluteText: String
    let weeklyResetText: String
    let weeklyResetAbsoluteText: String
    let primaryResetRelativeText: String
    let weeklyResetRelativeText: String
    let planType: String?
    let allowedText: String
    let limitReachedText: String
    let resetCreditCount: Int?
    let resetCreditError: String?
    let creditSummaries: [CodexResetCreditDisplay]
    let soonestResetCreditExpirationRelativeText: String?
    let checkedAtText: String
    let checkedAtRelativeText: String

    init(
        snapshot: CodexUsageSnapshot,
        timezone: TimeZone = CodexUsageFormatting.configuredTimeZone(),
        now: Date? = nil
    ) {
        let response = snapshot.usage
        let primary = response.rateLimit?.primaryWindow
        let weekly = response.rateLimit?.secondaryWindow
        let snapshotTime = snapshot.checkedAt
        let displayNow = now ?? snapshotTime
        let primaryResetDate = CodexUsageFormatting.resetDate(primary)
        let weeklyResetDate = CodexUsageFormatting.resetDate(weekly)

        primaryPercent = CodexUsageFormatting.formatPercent(primary?.usedPercent)
        weeklyPercent = CodexUsageFormatting.formatPercent(weekly?.usedPercent)
        primaryUsageValue = CodexUsageFormatting.clampedUnitValue(primary?.usedPercent)
        weeklyUsageValue = CodexUsageFormatting.clampedUnitValue(weekly?.usedPercent)
        primaryResetAbsoluteText = CodexUsageFormatting.formatOptionalDate(primaryResetDate, timezone: timezone)
        weeklyResetAbsoluteText = CodexUsageFormatting.formatOptionalDate(weeklyResetDate, timezone: timezone)
        primaryResetRelativeText = CodexUsageFormatting.formatOptionalRelative(
            primaryResetDate,
            now: displayNow
        )
        weeklyResetRelativeText = CodexUsageFormatting.formatOptionalRelative(
            weeklyResetDate,
            now: displayNow
        )
        primaryResetText = "\(primaryResetAbsoluteText) (\(primaryResetRelativeText))"
        weeklyResetText = "\(weeklyResetAbsoluteText) (\(weeklyResetRelativeText))"
        planType = response.planType
        allowedText = CodexUsageFormatting.yesNo(response.rateLimit?.allowed)
        limitReachedText = CodexUsageFormatting.yesNo(response.rateLimit?.limitReached)
        resetCreditCount = snapshot.resetCreditList?.availableCount ?? response.resetCredits?.availableCount
        resetCreditError = snapshot.resetCreditError
        checkedAtText = CodexUsageFormatting.formatDate(snapshotTime, timezone: timezone)
        checkedAtRelativeText = CodexUsageFormatting.formatRelative(snapshotTime, now: displayNow)

        let credits = snapshot.resetCreditList?.credits ?? []
        creditSummaries = credits
            .sorted { left, right in
                (CodexUsageFormatting.parseISODate(left.expiresAtRaw) ?? .distantFuture)
                    < (CodexUsageFormatting.parseISODate(right.expiresAtRaw) ?? .distantFuture)
            }
            .enumerated()
            .map { index, credit in
                let expiresAt = CodexUsageFormatting.parseISODate(credit.expiresAtRaw)
                let grantedAt = CodexUsageFormatting.parseISODate(credit.grantedAtRaw)
                return CodexResetCreditDisplay(
                    id: "\(index)-\(credit.title ?? "reset")-\(credit.expiresAtRaw ?? "")",
                    title: credit.title ?? "Codex reset",
                    status: credit.status ?? "unknown",
                    expiresText: CodexUsageFormatting.formatOptionalDate(expiresAt, timezone: timezone),
                    expiresRelativeText: CodexUsageFormatting.formatOptionalRelative(expiresAt, now: displayNow),
                    grantedText: CodexUsageFormatting.formatOptionalDate(
                        grantedAt,
                        timezone: timezone
                    ),
                    grantedRelativeText: CodexUsageFormatting.formatOptionalRelative(grantedAt, now: displayNow)
                )
            }
        soonestResetCreditExpirationRelativeText = creditSummaries.first?.expiresRelativeText
    }
}

enum CodexUsageMenuBarPresentation {
    static let placeholderTitle = "5h -- W --"
    static let loadingTitle = "5h ... W ..."
    static let errorTitle = "5h ? W ?"

    static func title(for display: CodexUsageDisplay) -> String {
        "5h \(display.primaryPercent) W \(display.weeklyPercent)"
    }

    static func toolTip(for display: CodexUsageDisplay) -> String {
        "Codex usage: 5h \(display.primaryPercent), weekly \(display.weeklyPercent)"
    }
}

struct CodexUsageMenuBarState {
    private(set) var title: String
    private var hasRenderedSnapshot: Bool

    init(
        title: String = CodexUsageMenuBarPresentation.placeholderTitle,
        hasRenderedSnapshot: Bool = false
    ) {
        self.title = title
        self.hasRenderedSnapshot = hasRenderedSnapshot
    }

    mutating func beginRefresh(showLoading: Bool) {
        guard showLoading, !hasRenderedSnapshot else { return }
        title = CodexUsageMenuBarPresentation.loadingTitle
    }

    mutating func render(_ display: CodexUsageDisplay) {
        title = CodexUsageMenuBarPresentation.title(for: display)
        hasRenderedSnapshot = true
    }

    mutating func renderError() {
        guard !hasRenderedSnapshot else { return }
        title = CodexUsageMenuBarPresentation.errorTitle
    }
}

struct CodexResetCreditDisplay: Identifiable {
    let id: String
    let title: String
    let status: String
    let expiresText: String
    let expiresRelativeText: String
    let grantedText: String
    let grantedRelativeText: String
}
