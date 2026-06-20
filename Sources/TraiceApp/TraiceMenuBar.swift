import Cocoa
import Foundation
import WidgetKit

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

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = CodexUsageClient()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?
    private var lastSuccessfulSnapshot: CodexUsageSnapshot?
    private var lastDisplaySignature: String?
    private var menuBarState = CodexUsageMenuBarState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.title = menuBarState.title
            button.toolTip = "Traice"
        }

        setLoadingMenu()
        refresh(showLoading: true, force: true)

        timer = Timer.scheduledTimer(withTimeInterval: CodexUsageConfig.menuBarRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(showLoading: false, force: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        timer?.invalidate()
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
                let snapshot = try await client.fetchSnapshot(checkedAt: startedAt)
                guard !Task.isCancelled else { return }
                render(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                renderError(error)
            }
        }
    }

    private func render(_ snapshot: CodexUsageSnapshot) {
        let display = CodexUsageDisplay(snapshot: snapshot, now: Date())
        let displaySignature = [
            display.primaryPercent,
            display.weeklyPercent,
            display.primaryResetText,
            display.weeklyResetText,
            display.resetCreditCount.map(String.init) ?? "unknown"
        ].joined(separator: "|")
        let shouldReloadWidgets = displaySignature != lastDisplaySignature

        lastSuccessfulSnapshot = snapshot
        lastDisplaySignature = displaySignature
        try? CodexUsageSnapshotStore.saveSnapshot(snapshot)
        if shouldReloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }

        menuBarState.render(display)
        statusItem.button?.title = menuBarState.title
        statusItem.button?.toolTip = CodexUsageMenuBarPresentation.toolTip(for: display)

        let menu = NSMenu()
        menu.delegate = self
        menu.addView(MenuHeaderView(display: display))
        addFooter(to: menu)
        statusItem.menu = menu
    }

    private func renderError(_ error: Error) {
        menuBarState.renderError()
        statusItem.button?.title = menuBarState.title
        statusItem.button?.toolTip = error.localizedDescription

        let menu = NSMenu()
        menu.delegate = self
        menu.addDisabled("Traice error")
        menu.addDisabled(error.localizedDescription)
        let checkedAt = lastRefreshStartedAt ?? Date()
        menu.addDisabled("Last check: \(CodexUsageFormatting.formatDate(checkedAt, timezone: CodexUsageFormatting.configuredTimeZone()))")
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
        NSWorkspace.shared.open(CodexUsageConfig.usageSettingsURL)
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

private final class MenuHeaderView: NSView {
    private static let menuWidth: CGFloat = 340
    private static let horizontalInset: CGFloat = 18
    private static let contentWidth = menuWidth - horizontalInset * 2
    private static let summaryHeight: CGFloat = 58

    private let display: CodexUsageDisplay
    private var expanded = false

    init(display: CodexUsageDisplay) {
        self.display = display
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let creditHeight = display.creditSummaries.isEmpty ? 18 : CGFloat(display.creditSummaries.count * 58)
        return NSSize(width: Self.menuWidth, height: expanded ? 232 + creditHeight : Self.summaryHeight)
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
        if expanded {
            stack.addArrangedSubview(detailsView())
        }
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
        button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor

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

        let chevronName = expanded ? "chevron.down" : "chevron.right"
        let chevron = NSImageView(image: NSImage(systemSymbolName: chevronName, accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 18),
            chevron.heightAnchor.constraint(equalToConstant: 18)
        ])

        content.addArrangedSubview(icon)
        content.addArrangedSubview(textStack)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.addArrangedSubview(spacer)
        content.addArrangedSubview(chevron)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.menuWidth),
            button.heightAnchor.constraint(equalToConstant: Self.summaryHeight),
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        return button
    }

    @objc private func toggleExpanded() {
        expanded.toggle()
        build()
        invalidateIntrinsicContentSize()
        superview?.layoutSubtreeIfNeeded()
        window?.layoutIfNeeded()
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
