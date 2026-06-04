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
/// full title shows; on the built-in display it's hard-capped to 10 characters.
struct MenuBarLabel: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        if let event = model.menuBarEvent {
            // .titleAndIcon forces the text to show — a Label in a status item
            // defaults to icon-only otherwise.
            Label(labelText(for: event), systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "calendar")
        }
    }

    private func labelText(for event: EKEvent) -> String {
        let trimmed = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Meeting" }
        if model.allowFullTitle { return trimmed }
        // Built-in display: at most 10 chars total (9 + "…" when truncated).
        return trimmed.count <= 10 ? trimmed : trimmed.prefix(9) + "…"
    }
}
