import Foundation
import Darwin

enum CodexUsageFormatting {
    static func expandedPath(_ path: String) -> String {
        if path == "~" {
            return realHomeDirectory()
        }

        if path.hasPrefix("~/") {
            let relativePath = String(path.dropFirst(2))
            return URL(fileURLWithPath: realHomeDirectory()).appendingPathComponent(relativePath).path
        }

        return path
    }

    static func authPath() -> String {
        expandedPath(ProcessInfo.processInfo.environment["CODEX_AUTH_PATH"] ?? CodexUsageConfig.defaultAuthPath)
    }

    static func timeoutSeconds() -> TimeInterval {
        let raw = ProcessInfo.processInfo.environment["CODEX_USAGE_TIMEOUT"] ?? "60"
        return Double(raw) ?? 60
    }

    static func configuredTimeZone() -> TimeZone {
        if let identifier = ProcessInfo.processInfo.environment["CODEX_USAGE_TIMEZONE"],
           let timezone = TimeZone(identifier: identifier) {
            return timezone
        }
        return .current
    }

    private static func realHomeDirectory() -> String {
        if let passwordEntry = getpwuid(getuid()),
           let homeDirectory = passwordEntry.pointee.pw_dir {
            return String(cString: homeDirectory)
        }

        return NSHomeDirectory()
    }

    static func formatPercent(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    static func clampedUnitValue(_ percent: Double?) -> Double {
        guard let percent else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    static func yesNo(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "yes" : "no"
    }

    static func resetDate(_ window: UsageWindow?) -> Date? {
        guard let resetAt = window?.resetAt else { return nil }
        return Date(timeIntervalSince1970: resetAt)
    }

    static func formatReset(_ window: UsageWindow?, timezone: TimeZone, now: Date) -> String {
        guard let date = resetDate(window) else { return "unknown" }
        return "\(formatDate(date, timezone: timezone)) (\(formatRelative(date, now: now)))"
    }

    static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    static func formatOptionalDate(_ date: Date?, timezone: TimeZone) -> String {
        guard let date else { return "unknown" }
        return formatDate(date, timezone: timezone)
    }

    static func formatOptionalRelative(_ date: Date?, now: Date) -> String {
        guard let date else { return "unknown" }
        return formatRelative(date, now: now)
    }

    static func formatDate(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "MMM d, h:mm a zzz"
        return formatter.string(from: date)
    }

    static func formatRelative(_ date: Date, now: Date) -> String {
        var seconds = Int(date.timeIntervalSince(now))
        let expired = seconds < 0
        seconds = abs(seconds)

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        let text: String
        if days > 0 {
            text = "\(days)d \(hours)h"
        } else if hours > 0 {
            text = "\(hours)h \(minutes)m"
        } else {
            text = "\(minutes)m"
        }

        return expired ? "\(text) ago" : "in \(text)"
    }
}
