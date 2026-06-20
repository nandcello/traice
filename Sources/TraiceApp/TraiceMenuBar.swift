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
        let display = CodexUsageDisplay(snapshot: snapshot)
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
        menu.addDisabled("Traice")
        if let planType = display.planType {
            menu.addDisabled("Plan: \(planType)")
        }

        menu.addSeparator()
        menu.addDisabled("5h usage: \(display.primaryPercent)")
        menu.addDisabled("5h resets: \(display.primaryResetText)")

        menu.addSeparator()
        menu.addDisabled("Weekly usage: \(display.weeklyPercent)")
        menu.addDisabled("Weekly resets: \(display.weeklyResetText)")

        menu.addSeparator()
        menu.addDisabled("Allowed: \(display.allowedText)")
        menu.addDisabled("Limit reached: \(display.limitReachedText)")
        if let resetCreditCount = display.resetCreditCount {
            menu.addDisabled("Reset credits: \(resetCreditCount)")
        }

        menu.addSeparator()
        menu.addDisabled("Rate-limit reset credits")
        if let resetCreditError = display.resetCreditError {
            menu.addDisabled("Details unavailable: \(resetCreditError)")
        } else if !display.creditSummaries.isEmpty {
            for (index, credit) in display.creditSummaries.enumerated() {
                menu.addSeparator()
                menu.addDisabled("\(index + 1). \(credit.title)")
                menu.addDisabled("Status: \(credit.status)")
                menu.addDisabled("Expires: \(credit.expiresText) (\(credit.expiresRelativeText))")
                menu.addDisabled("Granted: \(credit.grantedText)")
            }
        } else {
            menu.addDisabled("No reset credit details returned")
        }

        addFooter(to: menu, checkedAt: snapshot.checkedAt, timezone: CodexUsageFormatting.configuredTimeZone())
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
        addFooter(to: menu, checkedAt: lastRefreshStartedAt ?? Date(), timezone: CodexUsageFormatting.configuredTimeZone())
        statusItem.menu = menu
    }

    private func setLoadingMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addDisabled("Loading Traice...")
        addFooter(to: menu, checkedAt: Date(), timezone: CodexUsageFormatting.configuredTimeZone())
        statusItem.menu = menu
    }

    private func addFooter(to menu: NSMenu, checkedAt: Date, timezone: TimeZone) {
        menu.addSeparator()
        menu.addDisabled("Last checked: \(CodexUsageFormatting.formatDate(checkedAt, timezone: timezone))")
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
