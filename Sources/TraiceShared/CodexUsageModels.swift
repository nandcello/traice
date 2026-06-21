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

enum CursorUsageConfig {
    static let bundleIdentifier = "com.todesktop.230313mzl4w4u92"
    static let currentPeriodUsageEndpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    static let usageEndpoint = URL(string: "https://cursor.com/api/usage")!
    static let stripeEndpoint = URL(string: "https://cursor.com/api/auth/stripe")!
    static let dashboardURL = URL(string: "https://cursor.com/dashboard")!
    static let defaultAuthDatabasePath = "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
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

struct CursorCurrentPeriodUsageResponse: Codable {
    let planUsage: CursorPlanUsage?
    let totalPercentUsed: Double?
    let percentUsed: Double?
    let hardLimit: Double?
    let currentSpend: Double?

    enum CodingKeys: String, CodingKey {
        case planUsage
        case totalPercentUsed
        case percentUsed
        case hardLimit
        case currentSpend
    }
}

struct CursorPlanUsage: Codable {
    let used: Double?
    let limit: Double?
    let percentUsed: Double?
    let totalPercentUsed: Double?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalSpend: Double?
    let includedSpend: Double?
    let remaining: Double?

    enum CodingKeys: String, CodingKey {
        case used
        case limit
        case percentUsed
        case totalPercentUsed
        case autoPercentUsed
        case apiPercentUsed
        case totalSpend
        case includedSpend
        case remaining
    }
}

struct CursorLegacyUsageResponse: Codable {
    let gpt4: CursorLegacyUsageBucket?
    let usage: CursorLegacyUsageBucket?
    let premium: CursorLegacyUsageBucket?

    enum CodingKeys: String, CodingKey {
        case gpt4 = "gpt-4"
        case usage
        case premium
    }
}

struct CursorLegacyUsageBucket: Codable {
    let numRequests: Int?
    let numRequestsTotal: Int?
    let maxRequestUsage: Int?
    let requests: Int?
    let limit: Int?
}

struct CursorStripeResponse: Codable {
    let membershipType: String?
    let subscriptionStatus: String?
    let planName: String?

    enum CodingKeys: String, CodingKey {
        case membershipType
        case subscriptionStatus
        case planName
    }
}

struct CursorUsageSnapshot: Codable {
    let currentPeriodUsage: CursorCurrentPeriodUsageResponse?
    let legacyUsage: CursorLegacyUsageResponse?
    let stripe: CursorStripeResponse?
    let error: String?
    let checkedAt: Date
}

struct CursorUsageDetailLine: Equatable {
    let label: String
    let value: String
}

struct CursorUsageDisplay {
    let title: String
    let summary: String
    let detailUsageText: String
    let usageDetailLines: [CursorUsageDetailLine]
    let value: Double
    let planText: String
    let statusText: String
    let checkedAtText: String
    let checkedAtRelativeText: String
    let errorText: String?

    init(
        snapshot: CursorUsageSnapshot,
        timezone: TimeZone = CodexUsageFormatting.configuredTimeZone(),
        now: Date? = nil
    ) {
        let displayNow = now ?? snapshot.checkedAt
        checkedAtText = CodexUsageFormatting.formatDate(snapshot.checkedAt, timezone: timezone)
        checkedAtRelativeText = CodexUsageFormatting.formatRelative(snapshot.checkedAt, now: displayNow)
        errorText = snapshot.error
        planText = snapshot.stripe?.planName
            ?? snapshot.stripe?.membershipType
            ?? "Usage"
        statusText = snapshot.stripe?.subscriptionStatus ?? "unknown"

        let currentPeriodUsage = snapshot.currentPeriodUsage
        let planUsage = currentPeriodUsage?.planUsage
        let totalPercent = Self.totalPercent(planUsage: planUsage, currentPeriodUsage: currentPeriodUsage)
        let includedSpendText = Self.includedSpendText(planUsage: planUsage, currentPeriodUsage: currentPeriodUsage)

        if let planUsage,
           planUsage.autoPercentUsed != nil || planUsage.apiPercentUsed != nil {
            let autoPercentText = CodexUsageFormatting.formatPercent(planUsage.autoPercentUsed)
            let apiPercentText = CodexUsageFormatting.formatPercent(planUsage.apiPercentUsed)
            let totalPercentText = CodexUsageFormatting.formatPercent(totalPercent)
            let valuePercent = totalPercent
                ?? [planUsage.autoPercentUsed, planUsage.apiPercentUsed].compactMap { $0 }.max()

            value = CodexUsageFormatting.clampedUnitValue(valuePercent)
            title = "A+C \(autoPercentText) API \(apiPercentText)"
            summary = "Auto + Composer \(autoPercentText) | API \(apiPercentText)"

            var detailParts = [summary]
            if totalPercent != nil {
                detailParts.append("total \(totalPercentText)")
            }
            if let includedSpendText {
                detailParts.append("included spend \(includedSpendText)")
            }
            detailUsageText = detailParts.joined(separator: ", ")

            var usageDetailLines = [
                CursorUsageDetailLine(label: "Auto + Composer", value: autoPercentText),
                CursorUsageDetailLine(label: "API", value: apiPercentText)
            ]
            if totalPercent != nil {
                usageDetailLines.append(CursorUsageDetailLine(label: "Total", value: totalPercentText))
            }
            if let includedSpendText {
                usageDetailLines.append(CursorUsageDetailLine(label: "Included spend", value: includedSpendText))
            }
            self.usageDetailLines = usageDetailLines
        } else if let percent = totalPercent {
            value = CodexUsageFormatting.clampedUnitValue(percent)
            title = "Cursor \(CodexUsageFormatting.formatPercent(percent))"
            summary = CodexUsageFormatting.formatPercent(percent)

            var detailParts = [summary]
            if let includedSpendText {
                detailParts.append("included spend \(includedSpendText)")
            }
            detailUsageText = detailParts.joined(separator: ", ")

            var usageDetailLines = [
                CursorUsageDetailLine(label: "Total", value: summary),
                CursorUsageDetailLine(label: "Pool split", value: "unavailable")
            ]
            if let includedSpendText {
                usageDetailLines.append(CursorUsageDetailLine(label: "Included spend", value: includedSpendText))
            }
            self.usageDetailLines = usageDetailLines
        } else if let legacy = snapshot.legacyUsage?.gpt4 ?? snapshot.legacyUsage?.usage ?? snapshot.legacyUsage?.premium,
                  let used = legacy.numRequests ?? legacy.requests,
                  let limit = legacy.numRequestsTotal ?? legacy.maxRequestUsage ?? legacy.limit,
                  limit > 0 {
            let percent = Double(used) / Double(limit) * 100
            value = CodexUsageFormatting.clampedUnitValue(percent)
            title = "Cursor \(CodexUsageFormatting.formatPercent(percent))"
            summary = "\(used) / \(limit)"
            detailUsageText = "\(summary) requests (\(CodexUsageFormatting.formatPercent(percent)))"
            usageDetailLines = [
                CursorUsageDetailLine(label: "Requests", value: detailUsageText)
            ]
        } else if let error = snapshot.error {
            value = 0
            title = "Cursor ?"
            summary = "unavailable"
            detailUsageText = error
            usageDetailLines = [
                CursorUsageDetailLine(label: "Details", value: error)
            ]
        } else {
            value = 0
            title = "Cursor --"
            summary = "unknown"
            detailUsageText = "No usage returned"
            usageDetailLines = [
                CursorUsageDetailLine(label: "Usage", value: "No usage returned")
            ]
        }
    }

    private static func totalPercent(
        planUsage: CursorPlanUsage?,
        currentPeriodUsage: CursorCurrentPeriodUsageResponse?
    ) -> Double? {
        if let percent = planUsage?.totalPercentUsed
            ?? planUsage?.percentUsed
            ?? currentPeriodUsage?.totalPercentUsed
            ?? currentPeriodUsage?.percentUsed {
            return percent
        }

        guard let usedCents = usedCents(planUsage: planUsage, currentPeriodUsage: currentPeriodUsage),
              let limitCents = limitCents(planUsage: planUsage, currentPeriodUsage: currentPeriodUsage),
              limitCents > 0 else {
            return nil
        }
        return usedCents / limitCents * 100
    }

    private static func includedSpendText(
        planUsage: CursorPlanUsage?,
        currentPeriodUsage: CursorCurrentPeriodUsageResponse?
    ) -> String? {
        guard let usedCents = usedCents(planUsage: planUsage, currentPeriodUsage: currentPeriodUsage),
              let limitCents = limitCents(planUsage: planUsage, currentPeriodUsage: currentPeriodUsage),
              limitCents > 0 else {
            return nil
        }
        return "\(formatCurrencyFromCents(usedCents)) / \(formatCurrencyFromCents(limitCents))"
    }

    private static func usedCents(
        planUsage: CursorPlanUsage?,
        currentPeriodUsage: CursorCurrentPeriodUsageResponse?
    ) -> Double? {
        planUsage?.includedSpend
            ?? planUsage?.used
            ?? planUsage?.totalSpend
            ?? currentPeriodUsage?.currentSpend
    }

    private static func limitCents(
        planUsage: CursorPlanUsage?,
        currentPeriodUsage: CursorCurrentPeriodUsageResponse?
    ) -> Double? {
        planUsage?.limit ?? currentPeriodUsage?.hardLimit
    }

    private static func formatCurrencyFromCents(_ cents: Double) -> String {
        formatCurrency(cents / 100)
    }

    private static func formatCurrency(_ value: Double) -> String {
        if value >= 100 {
            return "$\(Int(value.rounded()))"
        }
        return String(format: "$%.2f", value)
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

enum CursorUsageMenuBarPresentation {
    static let placeholderTitle = "Cursor --"
    static let loadingTitle = "Cursor ..."
    static let errorTitle = "Cursor ?"

    static func title(for display: CursorUsageDisplay) -> String {
        display.title
    }

    static func toolTip(for display: CursorUsageDisplay) -> String {
        "Cursor usage: \(display.detailUsageText)"
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
