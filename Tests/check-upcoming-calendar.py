#!/usr/bin/env python3
"""Run the real upcoming-event selector without launching the app or requesting access."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manager = (root / "boringNotch/managers/CalendarManager.swift").read_text()
selector = manager[manager.index("    static func nextEvents("):manager.index("    func openCalendarPrivacySettings()")]
harness = """
import Cocoa

enum Selection {
SELECTOR
}

let now = Date(timeIntervalSince1970: 1_000)
let end = Date(timeIntervalSince1970: 2_000)
let calendar = CalendarModel(id: "personal", account: "Google", title: "Personal",
    color: .blue, isSubscribed: false, isReminder: false)
let other = CalendarModel(id: "other", account: "Other", title: "Other",
    color: .gray, isSubscribed: false, isReminder: false)

func event(_ id: String, _ start: Double, _ finish: Double,
           type: EventType = .event(.accepted), calendar: CalendarModel = calendar,
           allDay: Bool = false) -> EventModel {
    EventModel(id: id, start: Date(timeIntervalSince1970: start),
        end: Date(timeIntervalSince1970: finish), title: id, location: nil, notes: nil,
        url: nil, isAllDay: allDay, type: type, calendar: calendar, participants: [],
        timeZone: nil, hasRecurrenceRules: false, priority: nil)
}

func select(_ events: [EventModel], ids: Set<String> = ["personal"]) -> [String] {
    Selection.nextEvents(from: events, now: now, until: end, calendarIDs: ids).map(\\.id)
}

let ongoing = event("ongoing", 900, 1_100)
let next = event("next", 1_200, 1_300)
let later = event("later", 1_400, 1_500)
assert(select([later, next, ongoing]) == ["ongoing", "next"], "Sort by start and cap at two")
assert(select([
    event("ended", 800, 1_000),
    event("outside", 2_000, 2_100),
    event("reminder", 700, 1_500, type: .reminder(completed: false)),
    event("unselected", 600, 1_500, calendar: other), ongoing
]) == ["ongoing"], "Exclude ended, out-of-window, reminder and unselected items")
assert(select([ongoing], ids: []).isEmpty, "An empty selection must never mean all calendars")
assert(select([]).isEmpty)
assert(select([event("all-day", 0, 1_800, allDay: true)]) == ["all-day"], "Keep ongoing all-day events")
assert(select([event("birthday", 900, 1_800, type: .birthday)]) == ["birthday"])
assert(select([event("b", 1_200, 1_300), event("a", 1_200, 1_300)]) == ["a", "b"], "Stable ordering for ties")
let boundary = Selection.nextRefreshDate(from: [ongoing, next], now: now)
assert(boundary == ongoing.end, "Refresh when an ongoing event ends")
assert(Selection.nextRefreshDate(from: [next], now: now) == next.start, "Refresh when the next event starts")
assert(Selection.nextRefreshDate(from: [event("ended", 800, 900)], now: now) > now,
       "Ended events cannot create a busy refresh loop")
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!
let midnight = utc.dateInterval(of: .day, for: now)!.end
assert(Selection.nextRefreshDate(from: [], now: now, calendar: utc) == midnight,
       "An empty agenda refreshes at midnight without polling")
assert(Selection.nextRefreshDate(from: [event("later-day", 100_000, 100_100)], now: now, calendar: utc) == midnight,
       "Refresh the date before a later day's event")
print("Upcoming calendar checks passed: ongoing, next two, ordering, bounds, selections, reminders, all-day and refresh boundaries.")
""".replace("SELECTOR", selector)

with tempfile.TemporaryDirectory(prefix="notch-calendar-check-") as directory:
    directory = Path(directory)
    source = directory / "main.swift"
    source.write_text(harness)
    binary = directory / "calendar-check"
    subprocess.run([
        "xcrun", "swiftc", str(root / "boringNotch/models/CalendarModel.swift"),
        str(root / "boringNotch/models/EventModel.swift"), str(source), "-o", str(binary)
    ], check=True)
    subprocess.run([str(binary)], check=True)
