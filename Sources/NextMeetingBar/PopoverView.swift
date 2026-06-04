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
            if !model.past.isEmpty {
                Text("Earlier")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.past.enumerated()), id: \.offset) { _, event in
                        UpcomingRow(event: event, isPast: true)
                    }
                }
                Divider()
            }

            if model.nextEvent != nil {
                Text("Next meeting")
                    .font(.headline)
            }

            content

            if !model.upcoming.isEmpty {
                Divider()
                Text("Upcoming")
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
        .frame(width: 360)
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
                Text(whenText(for: event))
            }
            .foregroundStyle(.secondary)

            Text(relativeText(to: event.startDate))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let join = event.conferenceURL ?? event.url {
                    Link("Join", destination: join)
                        .buttonStyle(.borderedProminent)
                }
                if let notes = event.notesURL {
                    Link("Notes", destination: notes)
                }
            }
        } else if !model.authorized {
            Text("Calendar access not granted.\nEnable it in System Settings → Privacy & Security → Calendars.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !model.upcoming.isEmpty {
            Text("No more meetings today! :)")
                .font(.headline)
        } else {
            Text("Nothing upcoming in the next 7 days")
                .foregroundStyle(.secondary)
        }
    }

    /// "Today, 3:00 PM to 3:25 PM" / "Tomorrow, …" / "Friday, …".
    /// Drops the full date for today's meetings, where it's just noise.
    private func whenText(for event: EKEvent) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(event.startDate) {
            day = "Tomorrow"
        } else {
            day = event.startDate.formatted(.dateTime.weekday(.wide))
        }
        return "\(day), \(event.timeRangeText)"
    }

    /// "in 3h 19m" — minutes always rounded UP (so 3m01s still reads "in 4m"),
    /// keeping the two most significant units.
    private func relativeText(to date: Date) -> String {
        let totalMinutes = Int(ceil(max(0, date.timeIntervalSinceNow) / 60))
        if totalMinutes <= 0 { return "now" }

        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }

        return "in " + parts.prefix(2).joined(separator: " ")
    }

}

private let conferencingHosts = [
    "meet.google.com", "zoom.us", "teams.microsoft.com",
    "teams.live.com", "webex.com", "whereby.com", "meet.jit.si",
]

extension EKEvent {
    /// "3:00 PM to 3:25 PM" — the meeting's start-to-end time range.
    var timeRangeText: String {
        let start = startDate.formatted(date: .omitted, time: .shortened)
        let end = endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) to \(end)"
    }

    /// The video-conferencing link, if one is present in the URL/location/notes.
    /// Google Calendar dumps several links into the notes (attached docs, maps,
    /// the Meet link), so we scan every candidate and keep only a known
    /// conferencing host — never a random attached doc.
    var conferenceURL: URL? {
        let candidates = [url].compactMap { $0 }
            + Self.links(in: location)
            + Self.links(in: notes)
        return candidates.first { link in
            guard let host = link.host?.lowercased() else { return false }
            return conferencingHosts.contains { host.contains($0) }
        }
    }

    /// A link to the attached agenda/notes doc: the first real web link in the
    /// notes that isn't the conferencing link. http/https only, so detected
    /// email addresses (mailto:) and phone numbers (tel:) are ignored.
    var notesURL: URL? {
        Self.links(in: notes).first { link in
            guard let scheme = link.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = link.host?.lowercased() else { return false }
            return !conferencingHosts.contains { host.contains($0) }
        }
    }

    /// Every URL found in a block of text (notes, location).
    private static func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty else { return [] }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url) ?? []
    }
}

/// One compact line in the "Later" list: a time column + the meeting title.
/// Hovering the row expands it — unwrapping the full title and revealing the
/// Join/Notes links.
struct UpcomingRow: View {
    let event: EKEvent
    var isPast = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .lineLimit(hovering ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(whenLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hovering, event.conferenceURL != nil || event.notesURL != nil {
                HStack(spacing: 12) {
                    if let join = event.conferenceURL {
                        Link("Join", destination: join)
                    }
                    if let notes = event.notesURL {
                        Link("Notes", destination: notes)
                    }
                }
                .font(.caption)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.22)) {
                hovering = isHovering
            }
        }
        .opacity(isPast ? 0.5 : 1)
        .help(event.title ?? "Untitled")
    }

    /// "Today, 3:00 PM to 3:25 PM" / "Tomorrow, …" / "Fri, …".
    private var whenLine: String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(event.startDate) {
            day = "Tomorrow"
        } else {
            day = event.startDate.formatted(.dateTime.weekday(.abbreviated))
        }
        return "\(day), \(event.timeRangeText)"
    }
}
