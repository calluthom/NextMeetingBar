import SwiftUI
import AppKit
import EventKit
import UserNotifications

@MainActor
final class CalendarModel: ObservableObject {
    private let store = EKEventStore()

    @Published var past: [EKEvent] = []
    /// The meeting featured in the "Next meeting" block — only when it's today
    /// (ongoing or starting today). nil once today's meetings are done.
    /// Also drives the menu bar label, which shows the calendar glyph alone
    /// (no title) once today's meetings are done.
    @Published var nextEvent: EKEvent?
    @Published var upcoming: [EKEvent] = []
    @Published var authorized = false

    /// True when the widest connected display is roomy (e.g. the ultrawide),
    /// in which case the menu bar shows the full meeting title instead of truncating.
    /// 2000pt cleanly separates an ultrawide (~3440pt) from the built-in display (~1512–1800pt).
    @Published var allowFullTitle = false

    /// How many minutes before a meeting starts to fire the notification.
    private let notifyLeadMinutes: Double = 5

    private let notificationDelegate = NotificationDelegate()
    private var notifiedEventIDs = Set<String>()
    private var timer: Timer?

    /// Requests calendar + notification access, then does the first load and
    /// starts the once-a-minute refresh. Safe to call repeatedly (.task).
    func start() async {
        // Show banners even when the app is the active/frontmost process.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorized = granted
            guard granted else { return }

            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])

            refresh()
            updateScreen()
            startPolling()
        } catch {
            print("Calendar access error: \(error)")
        }
    }

    /// Finds the soonest non-all-day event starting in the future, across all calendars.
    func refresh() {
        let now = Date()
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 7, to: now) else { return }

        // Look from the start of today so we can also show meetings that already
        // ended earlier today, above the current/next one.
        let predicate = store.predicateForEvents(
            withStart: calendar.startOfDay(for: now), end: end, calendars: nil
        )
        let events = store.events(matching: predicate).filter { !$0.isAllDay }

        // Upcoming / ongoing: a meeting stays current until it actually ends (its
        // real duration); overlapping meetings fall into the Upcoming list.
        let live = events.filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }

        // Feature the next meeting only if it's today (ongoing or starting today).
        // Otherwise today's done — nextEvent is nil and everything future lists
        // under Upcoming, so the panel can show "No more meetings today".
        if let first = live.first,
           calendar.isDateInToday(first.startDate) || first.startDate <= now {
            nextEvent = first
            upcoming = Array(live.dropFirst().prefix(5))
        } else {
            nextEvent = nil
            upcoming = Array(live.prefix(5))
        }

        // Earlier today: meetings that have already ended (most recent few, chronological).
        past = Array(
            events.filter { $0.endDate <= now }
                .sorted { $0.startDate < $1.startDate }
                .suffix(5)
        )

        maybeNotify()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // React immediately to edits made in Calendar.app / Google sync.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // React to docking / undocking so the title expands or truncates live.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }
    }

    private func updateScreen() {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 0
        allowFullTitle = widest >= 2000
    }

    /// Fires a single notification ~5 minutes before a meeting, deduped by event id.
    private func maybeNotify() {
        guard let event = nextEvent,
              let id = event.eventIdentifier,
              !notifiedEventIDs.contains(id) else { return }

        let minutesUntil = event.startDate.timeIntervalSinceNow / 60
        guard minutesUntil <= notifyLeadMinutes, minutesUntil > 0 else { return }

        notifiedEventIDs.insert(id)

        let content = UNMutableNotificationContent()
        content.title = "Starting soon: \(event.title ?? "Meeting")"
        content.body = event.startDate.formatted(date: .omitted, time: .shortened)
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Lets notifications present as banners even when the app is frontmost.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
