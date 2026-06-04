import SwiftUI
import EventKit
import AppKit

/// The dropdown panel. Full meeting details live here, where there's room —
/// keeping the menu bar itself compact.
struct PopoverView: View {
    @ObservedObject var model: CalendarModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next meeting")
                .font(.headline)

            content

            if !model.upcoming.isEmpty {
                Divider()
                Text("Later")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.upcoming.enumerated()), id: \.offset) { _, event in
                        UpcomingRow(event: event)
                    }
                }
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.callout)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }

            HStack {
                Button("Refresh") { model.refresh() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.callout)
        }
        .padding()
        .frame(width: 280)
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        if let event = model.nextEvent {
            Text(event.title ?? "Untitled")
                .font(.title3.bold())
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(whenText(for: event.startDate))
            }
            .foregroundStyle(.secondary)

            Text(relativeText(to: event.startDate))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = meetingURL(for: event) {
                Link("Join", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        } else if !model.authorized {
            Text("Calendar access not granted.\nEnable it in System Settings → Privacy & Security → Calendars.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("Nothing upcoming in the next 7 days")
                .foregroundStyle(.secondary)
        }
    }

    /// "Today at 2:30 PM" / "Tomorrow at 9:00 AM" / "Friday at 11:00 AM".
    /// Drops the full date for today's meetings, where it's just noise.
    private func whenText(for date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow at \(time)" }
        let weekday = date.formatted(.dateTime.weekday(.wide))
        return "\(weekday) at \(time)"
    }

    /// "in 3h 19m" — keeps hours AND minutes (RelativeDateTimeFormatter rounds
    /// to a single unit and would say just "in 3 hours").
    private func relativeText(to date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let interval = max(0, date.timeIntervalSinceNow)
        return "in " + (formatter.string(from: interval) ?? "0m")
    }

    /// Finds the actual video-conferencing link. Google Calendar dumps several
    /// links into the notes (attached docs, maps, the Meet link), so we can't
    /// just take the first one — we scan every candidate and prefer a known
    /// conferencing host. Falls back to the event's own URL, never a random doc.
    private func meetingURL(for event: EKEvent) -> URL? {
        let candidates = [event.url].compactMap { $0 }
            + links(in: event.location)
            + links(in: event.notes)

        let providers = [
            "meet.google.com", "zoom.us", "teams.microsoft.com",
            "teams.live.com", "webex.com", "whereby.com", "meet.jit.si",
        ]
        let conferencing = candidates.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return providers.contains { host.contains($0) }
        }

        return conferencing ?? event.url
    }

    /// Every URL found in a block of text (notes, location).
    private func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty else { return [] }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url) ?? []
    }
}

/// One compact line in the "Later" list: a time column + the meeting title.
struct UpcomingRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(event.title ?? "Untitled")
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// "2:30 PM" for today, "Fri 2:30 PM" otherwise.
    private var timeLabel: String {
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(event.startDate) { return time }
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) \(time)"
    }
}
