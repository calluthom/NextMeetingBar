import SwiftUI
import EventKit

@main
struct NextMeetingBarApp: App {
    @StateObject private var model = CalendarModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The view rendered into the menu bar status item.
/// A glyph plus the next meeting's title. On a roomy display (ultrawide) the
/// full title shows, prefixed with the time until it starts; on the built-in
/// display it's hard-capped to 10 characters with no countdown.
struct MenuBarLabel: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        if let event: EKEvent = model.nextEvent {
            Label(labelText(for: event), systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "calendar")
        }
    }

    private func labelText(for event: EKEvent) -> String {
        let trimmed: String = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = trimmed.isEmpty ? "Meeting" : trimmed
        if model.allowFullTitle {
            // Roomy display: full title, prefixed with the countdown when the
            // meeting hasn't started yet (e.g. "15m · Standup").
            if let countdown = timeUntil(event.startDate) {
                return "\(countdown) · \(title)"
            }
            return title
        }
        // Built-in display: at most 10 chars total (9 + "…" when truncated).
        return title.count <= 10 ? title : title.prefix(9) + "…"
    }

    /// A short countdown until `start` ("15m", "2h 5m"), or nil if it's not in
    /// the future (the meeting is already ongoing).
    private func timeUntil(_ start: Date) -> String? {
        let seconds = start.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}
