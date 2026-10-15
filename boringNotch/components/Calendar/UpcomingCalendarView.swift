import Defaults
import EventKit
import SwiftUI

struct UpcomingCalendarView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.calendarSelectionState) private var calendarSelection
    @Environment(\.openURL) private var openURL
    @State private var today = Date()
    @State private var requestingAccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(today.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(today.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.effectiveAccent)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button(action: openCalendar) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Open Calendar")
                .help("Open macOS Calendar. Add your Google account in Calendar > Add Account.")
            }

            if calendarManager.calendarAuthorizationStatus == .fullAccess {
                if calendarManager.upcomingEvents.isEmpty {
                    Text(calendarManager.eventCalendars.isEmpty
                         ? "Add your Google account in macOS Calendar."
                         : calendarManager.eventCalendars.allSatisfy { !calendarManager.selectedCalendarIDs.contains($0.id) }
                         ? "Choose a calendar in Calendar settings."
                         : "No upcoming events in the next 7 days.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(3)
                    if !calendarManager.eventCalendars.isEmpty {
                        Text("Google calendars sync through macOS Calendar.")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calendarManager.upcomingEvents.indices, id: \.self) { index in
                            eventButton(calendarManager.upcomingEvents[index])
                        }
                    }
                }
            } else if calendarManager.calendarAuthorizationStatus == .notDetermined
                        || calendarManager.calendarAuthorizationStatus == .writeOnly {
                Text("Show events from macOS Calendar, including Google calendars.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                Button(requestingAccess ? "Connecting…" : "Connect Calendar") {
                    requestingAccess = true
                    Task {
                        await calendarManager.checkCalendarAuthorization()
                        requestingAccess = false
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .disabled(requestingAccess)
                .help("Add your Google account in macOS Calendar > Add Account.")
            } else {
                Text("Calendar access is off. Allow access in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                Button("Calendar Settings") {
                    calendarManager.openCalendarPrivacySettings()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .frame(width: 205, height: 140, alignment: .topLeading)
        .task(id: vm.notchState == .open) {
            guard vm.notchState == .open else { return }
            await refresh()
        }
        .task(id: nextRefreshDate) {
            guard vm.notchState == .open else { return }
            do {
                try await Task.sleep(for: .seconds(max(0.05, nextRefreshDate.timeIntervalSinceNow)))
                try Task.checkCancellation()
                guard vm.notchState == .open else { return }
                await refresh()
            } catch is CancellationError {
                // Closing the island cancels its only scheduled wake-up.
            } catch {}
        }
        .onChange(of: selectionIDs) { _, _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await refresh() }
        }
    }

    private var nextRefreshDate: Date {
        CalendarManager.nextRefreshDate(from: calendarManager.upcomingEvents, now: today)
    }

    private var selectionIDs: Set<String>? {
        switch calendarSelection {
        case .all: return nil
        case .selected(let ids): return ids
        }
    }

    private func eventButton(_ event: EventModel) -> some View {
        let title = event.title.isEmpty ? "Untitled event" : event.title
        let timing = eventTime(event)
        return Button {
            if let url = event.calendarAppURL() { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Text(timing)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(title), \(timing), \(event.calendar.title)")
        .accessibilityHint("Open event in Calendar")
        .help("\(title)\n\(timing)\n\(event.calendar.title)")
    }

    private func eventTime(_ event: EventModel) -> String {
        let day = Calendar.current.isDateInToday(event.start) ? "Today"
            : Calendar.current.isDateInTomorrow(event.start) ? "Tomorrow"
            : event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if event.isAllDay {
            return "\(event.start <= today && event.end > today ? "Today" : day) · All day"
        }
        if event.start <= today && event.end > today {
            let end = event.end.formatted(
                date: Calendar.current.isDateInToday(event.end) ? .omitted : .abbreviated,
                time: .shortened
            )
            return "Now · until \(end)"
        }
        return "\(day) · \(event.start.formatted(date: .omitted, time: .shortened))"
    }

    private func refresh() async {
        today = Date()
        await calendarManager.refreshUpcomingEvents()
    }

    private func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open(url)
        }
    }
}
