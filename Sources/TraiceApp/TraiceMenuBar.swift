import Cocoa
import Foundation
import QuartzCore
import WidgetKit

#if !TESTING
@main
private struct CodexUsageApp {
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.run()
    }
}
#endif

#if !TESTING
@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = CodexUsageClient()
    private let cursorClient = CursorUsageClient()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?
    private var lastSuccessfulSnapshot: CodexUsageSnapshot?
    private var lastCursorSnapshot: CursorUsageSnapshot?
    private var lastDisplaySignature: String?
    private var menuBarState = CodexUsageMenuBarState()
    private var activeUsageProvider = ActiveUsageProvider.current()
    private var isCodexHeaderExpanded = false
    private var isCursorHeaderExpanded = false
    private var activationObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.title = menuBarState.title
            button.toolTip = "Traice"
        }

        applyExpansionPolicy()
        setLoadingMenu()
        refresh(showLoading: true, force: true)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateActiveUsageProvider()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: CodexUsageConfig.menuBarRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(showLoading: false, force: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        timer?.invalidate()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func refresh(showLoading: Bool, force: Bool) {
        if refreshTask != nil && !force {
            return
        }

        let startedAt = Date()
        lastRefreshStartedAt = startedAt
        menuBarState.beginRefresh(showLoading: showLoading)
        statusItem.button?.title = menuBarState.title
        refreshTask?.cancel()

        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                refreshTask = nil
            }

            do {
                async let codexSnapshot = client.fetchSnapshot(checkedAt: startedAt)
                async let cursorSnapshot = cursorClient.fetchSnapshot(checkedAt: startedAt)
                let snapshot = try await codexSnapshot
                let cursor = await cursorSnapshot
                guard !Task.isCancelled else { return }
                render(snapshot, cursor: cursor)
            } catch {
                guard !Task.isCancelled else { return }
                renderError(error)
            }
        }
    }

    private func render(_ snapshot: CodexUsageSnapshot, cursor: CursorUsageSnapshot?) {
        let display = CodexUsageDisplay(snapshot: snapshot, now: Date())
        let cursorDisplay = cursor.map { CursorUsageDisplay(snapshot: $0, now: Date()) }
        let displaySignature = [
            display.primaryPercent,
            display.weeklyPercent,
            display.primaryResetText,
            display.weeklyResetText,
            display.resetCreditCount.map(String.init) ?? "unknown",
            cursorDisplay?.title ?? "cursor-none",
            cursorDisplay?.detailUsageText ?? "cursor-none",
            cursorDisplay?.resetText ?? "cursor-none"
        ].joined(separator: "|")
        let shouldReloadWidgets = displaySignature != lastDisplaySignature

        lastSuccessfulSnapshot = snapshot
        lastCursorSnapshot = cursor
        lastDisplaySignature = displaySignature
        try? TraiceUsageSnapshotStore.saveSnapshot(TraiceUsageSnapshot(codex: snapshot, cursor: cursor))
        if shouldReloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }

        menuBarState.render(display)
        renderCurrentTitle()
        rebuildMenu()
    }

    private func updateActiveUsageProvider() {
        activeUsageProvider = ActiveUsageProvider.current()
        applyExpansionPolicy()
        renderCurrentTitle()
        rebuildMenu()
    }

    private func applyExpansionPolicy() {
        switch activeUsageProvider {
        case .codex:
            isCodexHeaderExpanded = true
            isCursorHeaderExpanded = false
        case .cursor:
            isCodexHeaderExpanded = false
            isCursorHeaderExpanded = true
        case nil:
            isCodexHeaderExpanded = false
            isCursorHeaderExpanded = false
        }
    }

    private func renderError(_ error: Error) {
        menuBarState.renderError()
        renderCurrentTitle(error: error.localizedDescription)

        let menu = NSMenu()
        menu.delegate = self
        menu.addDisabled("Traice error")
        menu.addDisabled(error.localizedDescription)
        let checkedAt = lastRefreshStartedAt ?? Date()
        menu.addDisabled("Last check: \(CodexUsageFormatting.formatDate(checkedAt, timezone: CodexUsageFormatting.configuredTimeZone()))")
        addFooter(to: menu)
        statusItem.menu = menu
    }

    private func renderCurrentTitle(error: String? = nil) {
        let codexDisplay = lastSuccessfulSnapshot.map { CodexUsageDisplay(snapshot: $0, now: Date()) }
        let cursorDisplay = lastCursorSnapshot.map { CursorUsageDisplay(snapshot: $0, now: Date()) }

        switch activeUsageProvider {
        case .cursor?:
            if let cursorDisplay {
                statusItem.button?.title = CursorUsageMenuBarPresentation.title(for: cursorDisplay)
                statusItem.button?.toolTip = CursorUsageMenuBarPresentation.toolTip(for: cursorDisplay)
            } else {
                statusItem.button?.title = CursorUsageMenuBarPresentation.placeholderTitle
                statusItem.button?.toolTip = error ?? "Cursor usage unavailable"
            }
        case .codex?, nil:
            statusItem.button?.title = codexDisplay.map(CodexUsageMenuBarPresentation.title) ?? menuBarState.title
            statusItem.button?.toolTip = codexDisplay.map(CodexUsageMenuBarPresentation.toolTip) ?? error ?? "Codex usage unavailable"
        }
    }

    private func rebuildMenu() {
        guard let snapshot = lastSuccessfulSnapshot else { return }

        let codexDisplay = CodexUsageDisplay(snapshot: snapshot, now: Date())
        let cursorDisplay = lastCursorSnapshot.map { CursorUsageDisplay(snapshot: $0, now: Date()) }
        let menu = NSMenu()
        menu.delegate = self

        func addCodexHeader() {
            menu.addView(MenuHeaderView(display: codexDisplay, expanded: isCodexHeaderExpanded) { [weak self] expanded in
                self?.isCodexHeaderExpanded = expanded
            })
        }

        func addCursorHeader() {
            if let cursorDisplay {
                menu.addView(CursorMenuHeaderView(display: cursorDisplay, expanded: isCursorHeaderExpanded) { [weak self] expanded in
                    self?.isCursorHeaderExpanded = expanded
                })
            } else {
                menu.addDisabled("Cursor unavailable")
            }
        }

        switch activeUsageProvider {
        case .cursor?:
            addCursorHeader()
            menu.addSeparator()
            addCodexHeader()
        case .codex?, nil:
            addCodexHeader()
            menu.addSeparator()
            addCursorHeader()
        }

        addFooter(to: menu)
        statusItem.menu = menu
    }

    private func setLoadingMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addDisabled("Loading Traice...")
        menu.addDisabled("Last check: \(CodexUsageFormatting.formatDate(Date(), timezone: CodexUsageFormatting.configuredTimeZone()))")
        addFooter(to: menu)
        statusItem.menu = menu
    }

    private func addFooter(to menu: NSMenu) {
        menu.addSeparator()
        menu.addAction("Refresh", target: self, action: #selector(refreshFromMenu))
        menu.addAction("Open usage settings", target: self, action: #selector(openUsageSettings))
        menu.addAction("Open auth folder", target: self, action: #selector(openAuthFolder))
        menu.addSeparator()
        menu.addAction("Quit Traice", target: self, action: #selector(quit))
    }

    @objc private func refreshFromMenu() {
        refresh(showLoading: false, force: true)
    }

    @objc private func openUsageSettings() {
        switch activeUsageProvider {
        case .cursor?:
            NSWorkspace.shared.open(CursorUsageConfig.dashboardURL)
        case .codex?, nil:
            NSWorkspace.shared.open(CodexUsageConfig.usageSettingsURL)
        }
    }

    @objc private func openAuthFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: CodexUsageFormatting.authPath()).deletingLastPathComponent())
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard refreshTask == nil else { return }
        guard let lastSuccessfulSnapshot else {
            refresh(showLoading: false, force: false)
            return
        }

        let age = Date().timeIntervalSince(lastSuccessfulSnapshot.checkedAt)
        if age > CodexUsageConfig.menuOpenRefreshAge {
            refresh(showLoading: false, force: false)
        }
    }
}
#endif

enum ActiveUsageProvider {
    case codex
    case cursor

    static let codexBundleIdentifier = "com.openai.codex"

    static func current(
        runningApplication: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> ActiveUsageProvider? {
        current(bundleIdentifier: runningApplication?.bundleIdentifier)
    }

    static func current(bundleIdentifier: String?) -> ActiveUsageProvider? {
        switch bundleIdentifier {
        case codexBundleIdentifier:
            return .codex
        case CursorUsageConfig.bundleIdentifier:
            return .cursor
        default:
            return nil
        }
    }
}

private extension NSMenu {
    func addView(_ view: NSView) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        addItem(item)
    }

    func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addAction(_ title: String, target: AnyObject, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
    }

    func addSeparator() {
        addItem(NSMenuItem.separator())
    }
}

private enum MenuHeaderColors {
    static func summaryBackgroundColor(for appearance: NSAppearance) -> CGColor {
        var color = NSColor.controlBackgroundColor.withAlphaComponent(0.72)
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.controlBackgroundColor
                .withAlphaComponent(0.72)
                .usingColorSpace(.deviceRGB) ?? color
        }
        return color.cgColor
    }
}

final class MenuHeaderView: NSView {
    private static let menuWidth: CGFloat = 340
    private static let horizontalInset: CGFloat = 18
    private static let contentWidth = menuWidth - horizontalInset * 2
    private static let summaryHeight: CGFloat = 58
    private static let animationDuration: TimeInterval = 0.22

    private let display: CodexUsageDisplay
    private let onExpansionChange: (Bool) -> Void
    private var expanded: Bool
    private var currentHeight: CGFloat
    private var rootHeightConstraint: NSLayoutConstraint?
    private var detailHeightConstraint: NSLayoutConstraint?
    private var animationTimer: Timer?
    private weak var summaryButtonView: NSButton?
    private weak var detailClipView: NSView?
    private weak var chevronView: NSImageView?
    private weak var chevronHostView: NSView?
    private var chevronRotation: CGFloat

    init(display: CodexUsageDisplay, expanded: Bool, onExpansionChange: @escaping (Bool) -> Void) {
        self.display = display
        self.expanded = expanded
        self.onExpansionChange = onExpansionChange
        chevronRotation = Self.chevronRotation(for: expanded)
        currentHeight = Self.summaryHeight
        super.init(frame: .zero)
        build()
        applyExpansionState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.menuWidth, height: currentHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
        applyChevronRotation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func layout() {
        super.layout()
        applyChevronRotation()
    }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stack.addArrangedSubview(summaryButton())
        let detailClip = clippedDetailsView()
        stack.addArrangedSubview(detailClip)
        detailClipView = detailClip

        let rootHeightConstraint = heightAnchor.constraint(equalToConstant: Self.summaryHeight)
        let detailHeightConstraint = detailClip.heightAnchor.constraint(equalToConstant: 0)
        self.rootHeightConstraint = rootHeightConstraint
        self.detailHeightConstraint = detailHeightConstraint
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.menuWidth),
            rootHeightConstraint,
            detailHeightConstraint
        ])
    }

    private func summaryButton() -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.target = self
        button.action = #selector(toggleExpanded)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        summaryButtonView = button
        applyAppearance()

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(content)

        let icon = NSImageView(image: NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32)
        ])

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let title = label("Codex", font: .systemFont(ofSize: 16, weight: .semibold), color: .labelColor)
        let subtitle = label(menuSubtitle, font: .systemFont(ofSize: 13, weight: .semibold), color: .secondaryLabelColor)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(subtitle)

        let chevronHost = NSView()
        chevronHost.translatesAutoresizingMaskIntoConstraints = false
        chevronHost.wantsLayer = true
        chevronHost.layer?.masksToBounds = true

        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.imageAlignment = .alignCenter
        chevron.imageScaling = .scaleProportionallyDown
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentHuggingPriority(.required, for: .vertical)
        chevronHost.addSubview(chevron)
        chevronView = chevron
        chevronHostView = chevronHost
        NSLayoutConstraint.activate([
            chevronHost.widthAnchor.constraint(equalToConstant: 18),
            chevronHost.heightAnchor.constraint(equalToConstant: 18),
            chevron.centerXAnchor.constraint(equalTo: chevronHost.centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: chevronHost.centerYAnchor),
            chevron.widthAnchor.constraint(lessThanOrEqualTo: chevronHost.widthAnchor),
            chevron.heightAnchor.constraint(lessThanOrEqualTo: chevronHost.heightAnchor)
        ])

        content.addArrangedSubview(icon)
        content.addArrangedSubview(textStack)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.addArrangedSubview(spacer)
        content.addArrangedSubview(chevronHost)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.menuWidth),
            button.heightAnchor.constraint(equalToConstant: Self.summaryHeight),
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        return button
    }

    private func applyAppearance() {
        summaryButtonView?.layer?.backgroundColor = MenuHeaderColors.summaryBackgroundColor(for: effectiveAppearance)
        summaryButtonView?.needsDisplay = true
    }

    @objc private func toggleExpanded() {
        expanded.toggle()
        onExpansionChange(expanded)
        applyExpansionState(animated: true)
    }

    private func applyExpansionState(animated: Bool) {
        let detailHeight = measuredDetailHeight()
        let targetDetailHeight = expanded ? detailHeight : 0
        let targetHeight = expanded ? Self.summaryHeight + detailHeight : Self.summaryHeight
        let targetAlpha: CGFloat = expanded ? 1 : 0
        let targetRotation = Self.chevronRotation(for: expanded)

        if !animated {
            currentHeight = targetHeight
            rootHeightConstraint?.constant = targetHeight
            detailHeightConstraint?.constant = targetDetailHeight
            detailClipView?.alphaValue = targetAlpha
            chevronRotation = targetRotation
            applyChevronRotation()
            invalidateIntrinsicContentSize()
            layoutSubtreeIfNeeded()
            return
        }

        animationTimer?.invalidate()
        let startTime = CACurrentMediaTime()
        let startHeight = currentHeight
        let startDetailHeight = detailHeightConstraint?.constant ?? 0
        let startAlpha = detailClipView?.alphaValue ?? 0
        let startRotation = chevronRotation

        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(max(elapsed / Self.animationDuration, 0), 1)
            let easedProgress = 0.5 - 0.5 * cos(progress * Double.pi)
            let eased = CGFloat(easedProgress)

            currentHeight = startHeight + (targetHeight - startHeight) * eased
            rootHeightConstraint?.constant = currentHeight
            detailHeightConstraint?.constant = startDetailHeight + (targetDetailHeight - startDetailHeight) * eased
            detailClipView?.alphaValue = startAlpha + (targetAlpha - startAlpha) * eased
            chevronRotation = startRotation + (targetRotation - startRotation) * eased
            invalidateIntrinsicContentSize()
            superview?.layoutSubtreeIfNeeded()
            window?.layoutIfNeeded()
            applyChevronRotation()

            if progress >= 1 {
                timer.invalidate()
                animationTimer = nil
                currentHeight = targetHeight
                rootHeightConstraint?.constant = targetHeight
                detailHeightConstraint?.constant = targetDetailHeight
                detailClipView?.alphaValue = targetAlpha
                chevronRotation = targetRotation
                invalidateIntrinsicContentSize()
                superview?.layoutSubtreeIfNeeded()
                window?.layoutIfNeeded()
                applyChevronRotation()
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func chevronRotation(for expanded: Bool) -> CGFloat {
        expanded ? -CGFloat.pi / 2 : 0
    }

    private static func rotationTransform(for bounds: NSRect, angle: CGFloat) -> CGAffineTransform {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: angle)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return transform
    }

    private func applyChevronRotation() {
        guard let chevronHostView else { return }

        chevronHostView.wantsLayer = true
        chevronView?.layer?.setAffineTransform(.identity)
        if abs(chevronView?.frameCenterRotation ?? 0) > 0.001 {
            chevronView?.frameCenterRotation = 0
        }
        if abs(chevronView?.boundsRotation ?? 0) > 0.001 {
            chevronView?.boundsRotation = 0
        }

        let bounds = chevronHostView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let transform = Self.rotationTransform(for: bounds, angle: chevronRotation)
        chevronHostView.layer?.setAffineTransform(transform)
    }

    private func clippedDetailsView() -> NSView {
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.alphaValue = 0
        clip.translatesAutoresizingMaskIntoConstraints = false

        let details = detailsView()
        clip.addSubview(details)
        NSLayoutConstraint.activate([
            details.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            details.topAnchor.constraint(equalTo: clip.topAnchor)
        ])

        return clip
    }

    private func measuredDetailHeight() -> CGFloat {
        guard let detailClipView,
              let details = detailClipView.subviews.first else {
            return 0
        }

        detailClipView.layoutSubtreeIfNeeded()
        details.layoutSubtreeIfNeeded()
        return ceil(details.fittingSize.height)
    }

    private var menuSubtitle: String {
        let resetText: String
        if let relativeText = display.soonestResetCreditExpirationRelativeText {
            resetText = relativeText
        } else if display.resetCreditError != nil {
            resetText = "unavailable"
        } else {
            resetText = "none"
        }

        return "5h \(display.primaryPercent)  Weekly \(display.weeklyPercent)  Reset \(resetText)"
    }

    private func detailsView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 12, left: Self.horizontalInset, bottom: 12, right: Self.horizontalInset)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.menuWidth)
        ])

        container.addArrangedSubview(sectionTitle("Usage resets"))
        container.addArrangedSubview(detailLine("5h", display.primaryResetText))
        container.addArrangedSubview(detailLine("Weekly", display.weeklyResetText))
        container.addArrangedSubview(separator())

        container.addArrangedSubview(sectionTitle("Resets available"))
        container.addArrangedSubview(detailLine("Count", display.resetCreditCount.map(String.init) ?? "unknown"))
        if let resetCreditError = display.resetCreditError {
            container.addArrangedSubview(detailLine("Details", resetCreditError))
        } else if display.creditSummaries.isEmpty {
            container.addArrangedSubview(detailLine("Details", "No reset credit details returned"))
        } else {
            for credit in display.creditSummaries {
                container.addArrangedSubview(creditView(credit))
            }
        }
        container.addArrangedSubview(separator())

        container.addArrangedSubview(sectionTitle("Last check"))
        container.addArrangedSubview(detailLine(display.checkedAtText, display.checkedAtRelativeText))
        return container
    }

    private func creditView(_ credit: CodexResetCreditDisplay) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.addArrangedSubview(label(credit.title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor))
        stack.addArrangedSubview(detailLine("Expires", "\(credit.expiresText) (\(credit.expiresRelativeText))"))
        stack.addArrangedSubview(detailLine("Granted", "\(credit.grantedText) (\(credit.grantedRelativeText))"))
        return stack
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 13, weight: .bold), color: .secondaryLabelColor)
    }

    private func detailLine(_ labelText: String, _ valueText: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let name = label(labelText, font: .systemFont(ofSize: 13, weight: .regular), color: .secondaryLabelColor)
        let value = label(valueText, font: .systemFont(ofSize: 13, weight: .medium), color: .labelColor)
        value.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(value)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            name.widthAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        ])
        return line
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

final class CursorMenuHeaderView: NSView {
    private static let menuWidth: CGFloat = 340
    private static let horizontalInset: CGFloat = 18
    private static let contentWidth = menuWidth - horizontalInset * 2
    private static let summaryHeight: CGFloat = 58

    private let display: CursorUsageDisplay
    private let onExpansionChange: (Bool) -> Void
    private var expanded: Bool
    private var rootHeightConstraint: NSLayoutConstraint?
    private var detailHeightConstraint: NSLayoutConstraint?
    private weak var summaryButtonView: NSButton?
    private weak var detailClipView: NSView?
    private weak var chevronView: NSImageView?
    private weak var chevronHostView: NSView?

    init(display: CursorUsageDisplay, expanded: Bool, onExpansionChange: @escaping (Bool) -> Void) {
        self.display = display
        self.expanded = expanded
        self.onExpansionChange = onExpansionChange
        super.init(frame: .zero)
        build()
        applyExpansionState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.menuWidth, height: rootHeightConstraint?.constant ?? Self.summaryHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
        applyChevronRotation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func layout() {
        super.layout()
        applyChevronRotation()
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stack.addArrangedSubview(summaryButton())
        let detailClip = clippedDetailsView()
        stack.addArrangedSubview(detailClip)
        detailClipView = detailClip

        let rootHeightConstraint = heightAnchor.constraint(equalToConstant: Self.summaryHeight)
        let detailHeightConstraint = detailClip.heightAnchor.constraint(equalToConstant: 0)
        self.rootHeightConstraint = rootHeightConstraint
        self.detailHeightConstraint = detailHeightConstraint
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.menuWidth),
            rootHeightConstraint,
            detailHeightConstraint
        ])
    }

    private func summaryButton() -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.target = self
        button.action = #selector(toggleExpanded)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        summaryButtonView = button
        applyAppearance()

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(content)

        let icon = NSImageView(image: NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .systemMint
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32)
        ])

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.addArrangedSubview(label("Cursor", font: .systemFont(ofSize: 16, weight: .semibold), color: .labelColor))
        textStack.addArrangedSubview(label(menuSubtitle, font: .systemFont(ofSize: 13, weight: .semibold), color: .secondaryLabelColor))

        let chevronHost = NSView()
        chevronHost.translatesAutoresizingMaskIntoConstraints = false
        chevronHost.wantsLayer = true
        chevronHost.layer?.masksToBounds = true
        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevronHost.addSubview(chevron)
        chevronView = chevron
        chevronHostView = chevronHost
        NSLayoutConstraint.activate([
            chevronHost.widthAnchor.constraint(equalToConstant: 18),
            chevronHost.heightAnchor.constraint(equalToConstant: 18),
            chevron.centerXAnchor.constraint(equalTo: chevronHost.centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: chevronHost.centerYAnchor)
        ])

        content.addArrangedSubview(icon)
        content.addArrangedSubview(textStack)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.addArrangedSubview(spacer)
        content.addArrangedSubview(chevronHost)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.menuWidth),
            button.heightAnchor.constraint(equalToConstant: Self.summaryHeight),
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        return button
    }

    private func applyAppearance() {
        summaryButtonView?.layer?.backgroundColor = MenuHeaderColors.summaryBackgroundColor(for: effectiveAppearance)
        summaryButtonView?.needsDisplay = true
    }

    @objc private func toggleExpanded() {
        expanded.toggle()
        onExpansionChange(expanded)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyExpansionState(animated: true)
        }
    }

    private func applyExpansionState(animated: Bool = false) {
        let detailHeight = measuredDetailHeight()
        let targetDetailHeight = expanded ? detailHeight : 0
        let targetHeight = Self.summaryHeight + targetDetailHeight
        let animator = animated ? detailClipView?.animator() : detailClipView

        rootHeightConstraint?.constant = targetHeight
        detailHeightConstraint?.constant = targetDetailHeight
        animator?.alphaValue = expanded ? 1 : 0
        invalidateIntrinsicContentSize()
        superview?.layoutSubtreeIfNeeded()
        window?.layoutIfNeeded()
        applyChevronRotation()
    }

    private func applyChevronRotation() {
        guard let chevronHostView else { return }
        chevronView?.layer?.setAffineTransform(.identity)
        let bounds = chevronHostView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let angle = expanded ? -CGFloat.pi / 2 : 0
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: angle)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        chevronHostView.layer?.setAffineTransform(transform)
    }

    private func clippedDetailsView() -> NSView {
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.alphaValue = 0
        clip.translatesAutoresizingMaskIntoConstraints = false

        let details = detailsView()
        clip.addSubview(details)
        NSLayoutConstraint.activate([
            details.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            details.topAnchor.constraint(equalTo: clip.topAnchor)
        ])
        return clip
    }

    private func measuredDetailHeight() -> CGFloat {
        guard let detailClipView,
              let details = detailClipView.subviews.first else {
            return 0
        }
        detailClipView.layoutSubtreeIfNeeded()
        details.layoutSubtreeIfNeeded()
        return ceil(details.fittingSize.height)
    }

    private var menuSubtitle: String {
        guard display.resetRelativeText != "unknown" else {
            return display.summary
        }
        return "\(display.summary)  Reset \(display.resetRelativeText)"
    }

    private func detailsView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 12, left: Self.horizontalInset, bottom: 12, right: Self.horizontalInset)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.menuWidth)
        ])

        container.addArrangedSubview(sectionTitle("Cursor usage"))
        for line in display.usageDetailLines {
            container.addArrangedSubview(detailLine(line.label, line.value))
        }
        container.addArrangedSubview(detailLine("Reset", display.resetText))
        container.addArrangedSubview(detailLine("Plan", display.planText))
        container.addArrangedSubview(detailLine("Status", display.statusText))
        if let errorText = display.errorText,
           !display.usageDetailLines.contains(where: { $0.value == errorText }) {
            container.addArrangedSubview(detailLine("Details", errorText))
        }
        container.addArrangedSubview(separator())
        container.addArrangedSubview(sectionTitle("Last check"))
        container.addArrangedSubview(detailLine(display.checkedAtText, display.checkedAtRelativeText))
        return container
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 13, weight: .bold), color: .secondaryLabelColor)
    }

    private func detailLine(_ labelText: String, _ valueText: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let name = label(labelText, font: .systemFont(ofSize: 13, weight: .regular), color: .secondaryLabelColor)
        let value = label(valueText, font: .systemFont(ofSize: 13, weight: .medium), color: .labelColor)
        value.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(value)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            name.widthAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        ])
        return line
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}
