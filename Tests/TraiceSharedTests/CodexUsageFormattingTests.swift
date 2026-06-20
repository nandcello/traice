import XCTest

final class CodexUsageFormattingTests: XCTestCase {
    private func sampleSnapshot(
        checkedAt: Date,
        primaryPercent: Double = 6.4,
        weeklyPercent: Double = 8.2
    ) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            usage: UsageResponse(
                planType: "pro",
                rateLimit: RateLimit(
                    allowed: true,
                    limitReached: false,
                    primaryWindow: UsageWindow(
                        usedPercent: primaryPercent,
                        limitWindowSeconds: 18_000,
                        resetAfterSeconds: 3_600,
                        resetAt: 1_004_600
                    ),
                    secondaryWindow: UsageWindow(
                        usedPercent: weeklyPercent,
                        limitWindowSeconds: 604_800,
                        resetAfterSeconds: 86_400,
                        resetAt: 1_087_000
                    )
                ),
                resetCredits: ResetCredits(availableCount: 1)
            ),
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
            checkedAt: checkedAt
        )
    }

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
        let snapshot = sampleSnapshot(checkedAt: Date(timeIntervalSince1970: 1_000_000))

        let display = CodexUsageDisplay(
            snapshot: snapshot,
            timezone: TimeZone(secondsFromGMT: 0)!,
            now: snapshot.checkedAt
        )

        XCTAssertEqual(display.primaryPercent, "6%")
        XCTAssertEqual(display.weeklyPercent, "8%")
        XCTAssertEqual(display.primaryResetAbsoluteText, "Jan 12, 15:03")
        XCTAssertEqual(display.primaryResetRelativeText, "in 1h 16m")
        XCTAssertEqual(display.planType, "pro")
        XCTAssertEqual(display.allowedText, "yes")
        XCTAssertEqual(display.limitReachedText, "no")
        XCTAssertEqual(display.resetCreditCount, 1)
        XCTAssertEqual(display.creditSummaries.count, 1)
        XCTAssertEqual(display.creditSummaries[0].status, "available")
        XCTAssertEqual(display.creditSummaries[0].expiresText, "Sep 9, 02:46")
        XCTAssertEqual(display.creditSummaries[0].expiresRelativeText, "in 11562d 13h")
        XCTAssertEqual(display.creditSummaries[0].grantedText, "Sep 9, 01:46")
        XCTAssertEqual(display.creditSummaries[0].grantedRelativeText, "in 11562d 12h")
        XCTAssertEqual(display.soonestResetCreditExpirationRelativeText, "in 11562d 13h")
        XCTAssertEqual(display.checkedAtText, "Jan 12, 13:46")
        XCTAssertEqual(display.checkedAtRelativeText, "in 0m")
    }

    func testDisplaySortsSoonestExpiringResetCreditFirst() {
        let snapshot = CodexUsageSnapshot(
            usage: sampleSnapshot(checkedAt: Date(timeIntervalSince1970: 1_000_000)).usage,
            resetCreditList: ResetCreditList(
                credits: [
                    ResetCredit(
                        title: "Later reset",
                        status: "available",
                        expiresAtRaw: "2001-09-09T04:46:40Z",
                        grantedAtRaw: "2001-09-09T01:46:40Z"
                    ),
                    ResetCredit(
                        title: "Sooner reset",
                        status: "available",
                        expiresAtRaw: "2001-09-09T02:46:40Z",
                        grantedAtRaw: "2001-09-09T01:46:40Z"
                    )
                ],
                availableCount: 2
            ),
            resetCreditError: nil,
            checkedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        let display = CodexUsageDisplay(
            snapshot: snapshot,
            timezone: TimeZone(secondsFromGMT: 0)!,
            now: snapshot.checkedAt
        )

        XCTAssertEqual(display.creditSummaries.first?.title, "Sooner reset")
        XCTAssertEqual(display.soonestResetCreditExpirationRelativeText, "in 11562d 13h")
    }

    func testMenuBarStatePreservesUsageTitleUntilUpdatedSnapshotRenders() {
        var state = CodexUsageMenuBarState()
        let initialDisplay = CodexUsageDisplay(
            snapshot: sampleSnapshot(
                checkedAt: Date(timeIntervalSince1970: 1_000_000),
                primaryPercent: 6.4,
                weeklyPercent: 8.2
            ),
            timezone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 1_000_000)
        )
        let updatedDisplay = CodexUsageDisplay(
            snapshot: sampleSnapshot(
                checkedAt: Date(timeIntervalSince1970: 1_000_030),
                primaryPercent: 12.4,
                weeklyPercent: 18.5
            ),
            timezone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 1_000_030)
        )

        state.render(initialDisplay)
        XCTAssertEqual(state.title, "5h 6% W 8%")

        state.beginRefresh(showLoading: true)
        XCTAssertEqual(state.title, "5h 6% W 8%")

        state.renderError()
        XCTAssertEqual(state.title, "5h 6% W 8%")

        state.render(updatedDisplay)
        XCTAssertEqual(state.title, "5h 12% W 19%")
    }

    func testSnapshotStoreRoundTripsSnapshot() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("usage-snapshot.json")
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let snapshot = sampleSnapshot(checkedAt: Date(timeIntervalSince1970: 1_000_000))

        try CodexUsageSnapshotStore.saveSnapshot(snapshot, to: url)
        let loaded = try CodexUsageSnapshotStore.loadSnapshot(from: url)

        XCTAssertEqual(loaded.checkedAt, snapshot.checkedAt)
        XCTAssertEqual(loaded.usage.planType, "pro")
        XCTAssertEqual(loaded.usage.rateLimit?.primaryWindow?.usedPercent, 6.4)
        XCTAssertEqual(loaded.resetCreditList?.availableCount, 1)
        XCTAssertEqual(loaded.resetCreditList?.credits?.first?.status, "available")
    }

    func testSnapshotFreshnessUsesMaxAge() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = sampleSnapshot(checkedAt: Date(timeIntervalSince1970: 970))
        let stale = sampleSnapshot(checkedAt: Date(timeIntervalSince1970: 900))

        XCTAssertTrue(CodexUsageSnapshotStore.isFresh(fresh, now: now, maxAge: 45))
        XCTAssertFalse(CodexUsageSnapshotStore.isFresh(stale, now: now, maxAge: 45))
    }

    func testLoadCachedSnapshotReturnsStaleSnapshots() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("usage-snapshot.json")
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let snapshot = sampleSnapshot(checkedAt: Date(timeIntervalSince1970: 900))

        try CodexUsageSnapshotStore.saveSnapshot(snapshot, to: url)

        XCTAssertNil(
            CodexUsageSnapshotStore.loadFreshSnapshot(
                now: Date(timeIntervalSince1970: 1_000),
                maxAge: 45,
                from: url
            )
        )
        XCTAssertEqual(CodexUsageSnapshotStore.loadCachedSnapshot(from: url)?.checkedAt, snapshot.checkedAt)
    }
}
