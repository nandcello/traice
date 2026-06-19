import XCTest

final class CodexUsageFormattingTests: XCTestCase {
    func testPercentFormatting() {
        XCTAssertEqual(CodexUsageFormatting.formatPercent(nil), "--%")
        XCTAssertEqual(CodexUsageFormatting.formatPercent(6.4), "6%")
        XCTAssertEqual(CodexUsageFormatting.formatPercent(6.5), "7%")
    }

    func testClampedUnitValue() {
        XCTAssertEqual(CodexUsageFormatting.clampedUnitValue(nil), 0)
        XCTAssertEqual(CodexUsageFormatting.clampedUnitValue(-10), 0)
        XCTAssertEqual(CodexUsageFormatting.clampedUnitValue(42), 0.42)
        XCTAssertEqual(CodexUsageFormatting.clampedUnitValue(250), 1)
    }

    func testRelativeFormatting() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(CodexUsageFormatting.formatRelative(Date(timeIntervalSince1970: 1_070), now: now), "in 1m")
        XCTAssertEqual(CodexUsageFormatting.formatRelative(Date(timeIntervalSince1970: 8_500), now: now), "in 2h 5m")
        XCTAssertEqual(CodexUsageFormatting.formatRelative(Date(timeIntervalSince1970: 176_800), now: now), "in 2d 0h")
        XCTAssertEqual(CodexUsageFormatting.formatRelative(Date(timeIntervalSince1970: 940), now: now), "1m ago")
    }

    func testISODateParsing() {
        XCTAssertNotNil(CodexUsageFormatting.parseISODate("2026-06-19T03:04:05Z"))
        XCTAssertNotNil(CodexUsageFormatting.parseISODate("2026-06-19T03:04:05.123Z"))
        XCTAssertNil(CodexUsageFormatting.parseISODate(nil))
        XCTAssertNil(CodexUsageFormatting.parseISODate("not-a-date"))
    }

    func testDisplayBuildsCreditSummaries() {
        let usage = UsageResponse(
            planType: "pro",
            rateLimit: RateLimit(
                allowed: true,
                limitReached: false,
                primaryWindow: UsageWindow(
                    usedPercent: 6.4,
                    limitWindowSeconds: 18_000,
                    resetAfterSeconds: 3_600,
                    resetAt: 1_004_600
                ),
                secondaryWindow: UsageWindow(
                    usedPercent: 8.2,
                    limitWindowSeconds: 604_800,
                    resetAfterSeconds: 86_400,
                    resetAt: 1_087_000
                )
            ),
            resetCredits: ResetCredits(availableCount: 1)
        )
        let snapshot = CodexUsageSnapshot(
            usage: usage,
            resetCreditList: ResetCreditList(
                credits: [
                    ResetCredit(
                        title: "Codex reset",
                        status: "available",
                        expiresAtRaw: "2001-09-09T02:46:40Z",
                        grantedAtRaw: "2001-09-09T01:46:40Z"
                    )
                ],
                availableCount: 1
            ),
            resetCreditError: nil,
            checkedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        let display = CodexUsageDisplay(
            snapshot: snapshot,
            timezone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(display.primaryPercent, "6%")
        XCTAssertEqual(display.weeklyPercent, "8%")
        XCTAssertEqual(display.planType, "pro")
        XCTAssertEqual(display.allowedText, "yes")
        XCTAssertEqual(display.limitReachedText, "no")
        XCTAssertEqual(display.resetCreditCount, 1)
        XCTAssertEqual(display.creditSummaries.count, 1)
        XCTAssertEqual(display.creditSummaries[0].status, "available")
    }
}
