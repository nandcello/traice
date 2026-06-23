import AppKit
import XCTest

@MainActor
final class MenuHeaderViewTests: XCTestCase {
    func testActiveUsageProviderMatchesOnlyRelevantApps() {
        XCTAssertEqual(ActiveUsageProvider.current(bundleIdentifier: ActiveUsageProvider.codexBundleIdentifier), .codex)
        XCTAssertEqual(ActiveUsageProvider.current(bundleIdentifier: CursorUsageConfig.bundleIdentifier), .cursor)
        XCTAssertNil(ActiveUsageProvider.current(bundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(ActiveUsageProvider.current(bundleIdentifier: nil))
    }

    func testChevronRotatesFromRightToDownBetweenCollapsedAndExpandedStates() throws {
        let collapsed = MenuHeaderView(display: sampleDisplay(), expanded: false) { _ in }
        collapsed.layoutSubtreeIfNeeded()

        let expanded = MenuHeaderView(display: sampleDisplay(), expanded: true) { _ in }
        expanded.layoutSubtreeIfNeeded()

        XCTAssertEqual(try chevronRotationDegrees(in: collapsed), 0, accuracy: 0.001)
        XCTAssertEqual(try chevronRotationDegrees(in: expanded), -90, accuracy: 0.001)
        XCTAssertGreaterThan(expanded.intrinsicContentSize.height, collapsed.intrinsicContentSize.height)
    }

    func testChevronAnimatesToExpandedAndCollapsedStatesWhenSummaryIsClicked() throws {
        var expansionStates: [Bool] = []
        let header = MenuHeaderView(display: sampleDisplay(), expanded: false) { expansionStates.append($0) }
        header.layoutSubtreeIfNeeded()
        let button = try summaryButton(in: header)
        let collapsedHeight = header.intrinsicContentSize.height

        try click(button)
        runAnimationLoop()

        let expandedHeight = header.intrinsicContentSize.height
        XCTAssertEqual(expansionStates, [true])
        XCTAssertEqual(try chevronRotationDegrees(in: header), -90, accuracy: 0.001)
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)

        try click(button)
        runAnimationLoop()

        XCTAssertEqual(expansionStates, [true, false])
        XCTAssertEqual(try chevronRotationDegrees(in: header), 0, accuracy: 0.001)
        XCTAssertEqual(header.intrinsicContentSize.height, collapsedHeight, accuracy: 0.001)
    }

    func testSummaryButtonBackgroundTracksEffectiveAppearanceChanges() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }

        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        app.appearance = lightAppearance

        let codexHeader = MenuHeaderView(display: sampleDisplay(), expanded: false) { _ in }
        let cursorHeader = CursorMenuHeaderView(display: sampleCursorDisplay(), expanded: false) { _ in }

        try assertSummaryBackground(
            in: codexHeader,
            updatesFrom: lightAppearance,
            to: darkAppearance
        )
        try assertSummaryBackground(
            in: cursorHeader,
            updatesFrom: lightAppearance,
            to: darkAppearance
        )
    }

    private func assertSummaryBackground(
        in header: NSView,
        updatesFrom lightAppearance: NSAppearance,
        to darkAppearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        header.appearance = lightAppearance
        header.viewDidChangeEffectiveAppearance()
        header.layoutSubtreeIfNeeded()
        let button = try summaryButton(in: header, file: file, line: line)
        XCTAssertEqual(
            try backgroundColorComponents(in: button, file: file, line: line),
            summaryBackgroundComponents(for: lightAppearance),
            file: file,
            line: line
        )

        header.appearance = darkAppearance
        header.viewDidChangeEffectiveAppearance()
        header.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            try backgroundColorComponents(in: button, file: file, line: line),
            summaryBackgroundComponents(for: darkAppearance),
            file: file,
            line: line
        )

        header.appearance = lightAppearance
        header.viewDidChangeEffectiveAppearance()
        header.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            try backgroundColorComponents(in: button, file: file, line: line),
            summaryBackgroundComponents(for: lightAppearance),
            file: file,
            line: line
        )
    }

    private func runAnimationLoop() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
    }

    private func click(_ button: NSButton, file: StaticString = #filePath, line: UInt = #line) throws {
        let action = try XCTUnwrap(button.action, file: file, line: line)
        let dispatched = NSApp.sendAction(action, to: button.target, from: button)
        XCTAssertTrue(dispatched, file: file, line: line)
    }

    private func summaryButton(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSButton {
        let matches = root.descendants.compactMap { $0 as? NSButton }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    private func chevronRotationDegrees(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGFloat {
        let chevron = try chevron(in: root, file: file, line: line)
        chevron.layoutSubtreeIfNeeded()
        guard let host = chevron.superview, host.wantsLayer, let transform = host.layer?.affineTransform() else {
            return 0
        }
        return atan2(transform.b, transform.a) * 180 / CGFloat.pi
    }

    private func backgroundColorComponents(
        in view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [CGFloat] {
        let cgColor = try XCTUnwrap(view.layer?.backgroundColor, file: file, line: line)
        let color = try XCTUnwrap(NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB), file: file, line: line)
        return [
            color.redComponent,
            color.greenComponent,
            color.blueComponent,
            color.alphaComponent
        ].map { ($0 * 1_000).rounded() / 1_000 }
    }

    private func summaryBackgroundComponents(for appearance: NSAppearance) -> [CGFloat] {
        var color: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.controlBackgroundColor
                .withAlphaComponent(0.72)
                .usingColorSpace(.deviceRGB)!
        }
        let resolvedColor = color!
        return [
            resolvedColor.redComponent,
            resolvedColor.greenComponent,
            resolvedColor.blueComponent,
            resolvedColor.alphaComponent
        ].map { ($0 * 1_000).rounded() / 1_000 }
    }

    private func chevron(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSImageView {
        let matches = root.descendants.compactMap { view -> NSImageView? in
            guard let imageView = view as? NSImageView,
                  let host = imageView.superview,
                  host.hasConstraint(.width, equalTo: 18),
                  host.hasConstraint(.height, equalTo: 18) else {
                return nil
            }
            return imageView
        }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    private func sampleDisplay() -> CodexUsageDisplay {
        let checkedAt = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = CodexUsageSnapshot(
            usage: UsageResponse(
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

        return CodexUsageDisplay(
            snapshot: snapshot,
            timezone: TimeZone(secondsFromGMT: 0)!,
            now: checkedAt
        )
    }

    private func sampleCursorDisplay() -> CursorUsageDisplay {
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = CursorUsageSnapshot(
            currentPeriodUsage: CursorCurrentPeriodUsageResponse(
                planUsage: nil,
                totalPercentUsed: 48,
                percentUsed: nil,
                hardLimit: nil,
                currentSpend: nil,
                billingCycleEnd: CursorUsageTimestamp(rawValue: "1700004600000")
            ),
            legacyUsage: nil,
            stripe: CursorStripeResponse(
                membershipType: "pro_plus",
                subscriptionStatus: "active",
                planName: nil
            ),
            error: nil,
            checkedAt: checkedAt
        )

        return CursorUsageDisplay(
            snapshot: snapshot,
            timezone: TimeZone(secondsFromGMT: 0)!,
            now: checkedAt
        )
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }

    func hasConstraint(_ attribute: NSLayoutConstraint.Attribute, equalTo constant: CGFloat) -> Bool {
        constraints.contains { constraint in
            constraint.firstItem === self &&
                constraint.secondItem == nil &&
                constraint.firstAttribute == attribute &&
                abs(constraint.constant - constant) < 0.001
        }
    }
}
