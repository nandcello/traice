import AppKit
import SwiftUI
import WidgetKit

struct CodexResetsEntry: TimelineEntry {
    let date: Date
    let state: CodexResetsWidgetState
}

enum CodexResetsWidgetState {
    case placeholder
    case success(CodexUsageSnapshot)
    case failure(String, Date)
}

struct CodexResetsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexResetsEntry {
        CodexResetsEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexResetsEntry) -> Void) {
        if context.isPreview {
            completion(CodexResetsEntry(date: Date(), state: .placeholder))
            return
        }

        Task {
            completion(await loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexResetsEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let nextRefresh = Calendar.current.date(
                byAdding: .second,
                value: Int(CodexUsageConfig.widgetRefreshInterval),
                to: Date()
            ) ?? Date().addingTimeInterval(CodexUsageConfig.widgetRefreshInterval)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func loadEntry() async -> CodexResetsEntry {
        let checkedAt = Date()
        if let cachedSnapshot = CodexUsageSnapshotStore.loadFreshSnapshot(now: checkedAt) {
            return CodexResetsEntry(date: cachedSnapshot.checkedAt, state: .success(cachedSnapshot))
        }

        do {
            let snapshot = try await CodexUsageClient().fetchSnapshot(checkedAt: checkedAt)
            return CodexResetsEntry(date: checkedAt, state: .success(snapshot))
        } catch {
            return CodexResetsEntry(date: checkedAt, state: .failure(error.localizedDescription, checkedAt))
        }
    }
}

struct CodexResetsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexResetsEntry

    var body: some View {
        Group {
            switch entry.state {
            case .placeholder:
                placeholderView
            case .success(let snapshot):
                contentView(CodexUsageDisplay(snapshot: snapshot))
            case .failure(let message, let checkedAt):
                errorView(message: message, checkedAt: checkedAt)
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .widgetURL(CodexUsageConfig.usageSettingsURL)
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Codex", subtitle: "Usage")
            UsageMeter(label: "5h", percentText: "--%", value: 0.38, tint: .cyan)
            UsageMeter(label: "Weekly", percentText: "--%", value: 0.22, tint: .orange)
            Spacer(minLength: 0)
            Text("Checking usage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private func contentView(_ display: CodexUsageDisplay) -> some View {
        switch family {
        case .systemSmall:
            smallContent(display)
        case .systemLarge:
            largeContent(display)
        default:
            mediumContent(display)
        }
    }

    private func smallContent(_ display: CodexUsageDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Codex", subtitle: "Usage")
            UsageMeter(label: "5h", percentText: display.primaryPercent, value: display.primaryUsageValue, tint: .cyan)
            UsageMeter(label: "Weekly", percentText: display.weeklyPercent, value: display.weeklyUsageValue, tint: .orange)
            Spacer(minLength: 0)
            ResetLine(label: "Next", value: display.primaryResetRelativeText)
        }
        .padding()
    }

    private func mediumContent(_ display: CodexUsageDisplay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Codex", subtitle: "Usage")
            HStack(spacing: 16) {
                UsageMeter(label: "5h", percentText: display.primaryPercent, value: display.primaryUsageValue, tint: .cyan)
                UsageMeter(label: "Weekly", percentText: display.weeklyPercent, value: display.weeklyUsageValue, tint: .orange)
            }
            VStack(alignment: .leading, spacing: 6) {
                ResetLine(label: "5h reset", value: display.primaryResetRelativeText)
                ResetLine(label: "Weekly reset", value: display.weeklyResetRelativeText)
                ResetLine(label: "Credits", value: display.resetCreditCount.map(String.init) ?? "unknown")
            }
            Spacer(minLength: 0)
            footer(display.checkedAtText)
        }
        .padding()
    }

    private func largeContent(_ display: CodexUsageDisplay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            mediumHeader(display)
            VStack(alignment: .leading, spacing: 6) {
                ResetLine(label: "5h reset", value: display.primaryResetText)
                ResetLine(label: "Weekly reset", value: display.weeklyResetText)
                ResetLine(label: "Allowed", value: display.allowedText)
                ResetLine(label: "Limited", value: display.limitReachedText)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Reset credits")
                    .font(.caption.weight(.semibold))
                if let resetCreditError = display.resetCreditError {
                    Text(resetCreditError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if display.creditSummaries.isEmpty {
                    Text("No reset credit details returned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(display.creditSummaries.prefix(2)) { credit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text("\(credit.status) - expires \(credit.expiresRelativeText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            footer(display.checkedAtText)
        }
        .padding()
    }

    private func mediumHeader(_ display: CodexUsageDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                header(title: "Codex", subtitle: display.planType ?? "Usage")
                Spacer()
                Text(display.resetCreditCount.map { "\($0) credits" } ?? "credits --")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                UsageMeter(label: "5h", percentText: display.primaryPercent, value: display.primaryUsageValue, tint: .cyan)
                UsageMeter(label: "Weekly", percentText: display.weeklyPercent, value: display.weeklyUsageValue, tint: .orange)
            }
        }
    }

    private func errorView(message: String, checkedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            Text("Codex usage unavailable")
                .font(.headline)
                .lineLimit(2)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 3 : 5)
            Spacer(minLength: 0)
            footer(CodexUsageFormatting.formatDate(checkedAt, timezone: CodexUsageFormatting.configuredTimeZone()))
        }
        .padding()
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func footer(_ text: String) -> some View {
        Text("Checked \(text)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct UsageMeter: View {
    let label: String
    let percentText: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(percentText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * value, value > 0 ? 4 : 0))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct ResetLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct CodexResetsWidget: Widget {
    let kind = "CodexResetsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexResetsProvider()) { entry in
            CodexResetsWidgetView(entry: entry)
        }
        .configurationDisplayName("Traice")
        .description("Shows Codex 5-hour and weekly usage, reset times, and reset credits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CodexResetsWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexResetsWidget()
    }
}
