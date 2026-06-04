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
                Text(whenText(for: event.startDate))
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
/// Hover shows the full title as a tooltip; click expands the row to wrap it.
struct UpcomingRow: View {
    let event: EKEvent
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text(timeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 124, alignment: .leading)
                    Text(event.title ?? "Untitled")
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, event.conferenceURL != nil || event.notesURL != nil {
                HStack(spacing: 12) {
                    if let join = event.conferenceURL {
                        Link("Join", destination: join)
                    }
                    if let notes = event.notesURL {
                        Link("Notes", destination: notes)
                    }
                }
                .font(.caption)
                .padding(.leading, 132) // align under the title column (124 + 8 spacing)
            }
        }
        .help(event.title ?? "Untitled")
    }

    /// "Today 2:30 PM" / "Tomorrow 9:00 AM" / "Fri 2:30 PM".
    private var timeLabel: String {
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(event.startDate) {
            day = "Tomorrow"
        } else {
            day = event.startDate.formatted(.dateTime.weekday(.abbreviated))
        }
        return "\(day) \(time)"
    }
}
