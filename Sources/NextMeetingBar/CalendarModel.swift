import SwiftUI
import AppKit
import EventKit
import UserNotifications

@MainActor
final class CalendarModel: ObservableObject {
    private let store = EKEventStore()

    @Published var nextEvent: EKEvent?
    @Published var upcoming: [EKEvent] = []
    @Published var authorized = false

    /// True when the widest connected display is roomy (e.g. the ultrawide),
    /// in which case the menu bar shows the full meeting title instead of truncating.
    /// 2000pt cleanly separates an ultrawide (~3440pt) from the built-in display (~1512–1800pt).
    @Published var allowFullTitle = false

    private var notifiedEventIDs = Set<String>()
    private var timer: Timer?

    /// Requests calendar + notification access, then does the first load and
    /// starts the once-a-minute refresh. Safe to call repeatedly (.task).
    func start() async {
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
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let sorted = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        nextEvent = sorted.first
        upcoming = Array(sorted.dropFirst().prefix(5))

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
        guard minutesUntil <= 5, minutesUntil > 0 else { return }

        notifiedEventIDs.insert(id)

        let content = UNMutableNotificationContent()
        content.title = "Starting soon: \(event.title ?? "Meeting")"
        content.body = event.startDate.formatted(date: .omitted, time: .shortened)
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
