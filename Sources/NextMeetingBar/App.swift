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
            // Roomy display: full title, prefixed with the countdown until it
            // starts ("15m · Standup") or "Now" once it's ongoing.
            let countdown = event.startCountdown ?? "Now"
            return "\(countdown) · \(title)"
        }
        // Built-in display: at most 10 chars total (9 + "…" when truncated).
        return title.count <= 10 ? title : title.prefix(9) + "…"
    }
}
