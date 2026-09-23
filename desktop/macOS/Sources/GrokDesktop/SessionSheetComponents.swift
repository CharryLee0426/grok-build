import SwiftUI

/// Colours for session and task states, shared by the dashboard, tasks, and workflow sheets.
enum SessionTone: Equatable {
    case accent, green, orange, red, muted

    var color: Color {
        switch self {
        case .accent: return Theme.accent
        case .green: return Theme.green
        case .orange: return .orange
        case .red: return .red
        case .muted: return Theme.muted
        }
    }
}

/// A compact state label: a coloured dot, or a small spinner while work is in flight.
struct SessionStatusPill: View {
    let text: String
    var tone: SessionTone = .muted
    var spinning = false

    var body: some View {
        HStack(spacing: 5) {
            if spinning {
                ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 8, height: 8)
            } else {
                Circle().fill(tone.color).frame(width: 6, height: 6)
            }
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .foregroundStyle(tone == .muted ? Theme.muted : tone.color)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tone.color.opacity(tone == .muted ? 0.1 : 0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The rounded row surface used by the command sheets.
struct SessionCardModifier: ViewModifier {
    var highlighted = false
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content.padding(padding)
            .background(Theme.canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(highlighted ? Theme.accent.opacity(0.7) : Theme.line.opacity(0.3), lineWidth: highlighted ? 1.5 : 0.5))
    }
}

extension View {
    func sessionCard(highlighted: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(SessionCardModifier(highlighted: highlighted, padding: padding))
    }
}

struct SessionSectionTitle: View {
    let title: String
    var count: Int?
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true) }
            Text(title)
            if let count { Text("\(count)").monospacedDigit().opacity(0.75) }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SessionEmptyState: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(title).font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.8)).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity).padding(35)
    }
}

/// The error strip shown under a sheet's header, as in the feature browser.
struct SessionErrorStrip: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry { Button("Retry", action: retry).buttonStyle(SubtleButtonStyle()) }
        }
        .font(.system(size: 13)).padding(.horizontal, 24).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hover.opacity(0.55))
    }
}

enum SessionFormat {
    /// "42s", "3m 5s", "1h 12m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3_600 { return total % 60 == 0 ? "\(total / 60)m" : "\(total / 60)m \(total % 60)s" }
        return total % 3_600 / 60 == 0 ? "\(total / 3_600)h" : "\(total / 3_600)h \(total % 3_600 / 60)m"
    }

    /// "12.4k" style token counts.
    static func tokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fk", Double(count) / 1_000).replacingOccurrences(of: ".0k", with: "k") }
        return String(format: "%.1fM", Double(count) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
    }

    static func abbreviatedPath(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}
