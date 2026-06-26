import Foundation
import EventKit
import Contacts

/// Reads Apple Calendar/Reminders to plan around real commitments, and writes the app's
/// sessions, events and reminders into a dedicated "Win the Day" calendar + list.
@MainActor
final class CalendarManager: ObservableObject {
    private let store = EKEventStore()
    private let contactStore = CNContactStore()

    @Published var calAuthorized = false
    @Published var remindersAuthorized = false
    @Published var contactsAuthorized = false
    @Published var statusNote = ""

    private let appCalendarName = "Win the Day"

    init() { refreshAuthStatus() }

    private func refreshAuthStatus() {
        let cal = EKEventStore.authorizationStatus(for: .event)
        let rem = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) {
            calAuthorized = (cal == .fullAccess)
            remindersAuthorized = (rem == .fullAccess)
        } else {
            calAuthorized = (cal == .authorized)
            remindersAuthorized = (rem == .authorized)
        }
        contactsAuthorized = CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    // MARK: - Authorization

    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                calAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
                remindersAuthorized = (try? await store.requestFullAccessToReminders()) ?? false
            } else {
                calAuthorized = (try? await store.requestAccess(to: .event)) ?? false
                remindersAuthorized = (try? await store.requestAccess(to: .reminder)) ?? false
            }
            contactsAuthorized = (try? await contactStore.requestAccess(for: .contacts)) ?? false
        }
        if !calAuthorized { statusNote = "Calendar access is off — enable it in Settings to plan around your events." }
    }

    // MARK: - Reading

    /// Upcoming non-app events over the next `days`, soonest first.
    func upcomingEvents(days: Int = 7) -> [EKEvent] {
        guard calAuthorized else { return [] }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay || $0.calendar.title.lowercased().contains("birthday") }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
    }

    func eventsOn(_ date: Date) -> [EKEvent] {
        guard calAuthorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
    }

    // MARK: - The app's calendar / list

    private func appCalendar() -> EKCalendar? {
        if let existing = store.calendars(for: .event).first(where: { $0.title == appCalendarName }) {
            return existing
        }
        guard let source = defaultSource(for: .event) else { return nil }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = appCalendarName
        cal.source = source
        try? store.saveCalendar(cal, commit: true)
        return cal
    }

    private func appReminderList() -> EKCalendar? {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == appCalendarName }) {
            return existing
        }
        guard let source = defaultSource(for: .reminder) else { return nil }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = appCalendarName
        cal.source = source
        try? store.saveCalendar(cal, commit: true)
        return cal
    }

    private func defaultSource(for type: EKEntityType) -> EKSource? {
        if type == .event, let d = store.defaultCalendarForNewEvents?.source { return d }
        if type == .reminder, let d = store.defaultCalendarForNewReminders()?.source { return d }
        // Fall back to a local/iCloud source.
        return store.sources.first { $0.sourceType == .local } ?? store.sources.first
    }

    // MARK: - Writing

    /// Create a calendar event; returns its identifier so the caller can update/remove later.
    @discardableResult
    func addEvent(title: String, start: Date, durationMin: Int, notes: String = "") -> String? {
        guard calAuthorized, let cal = appCalendar() else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(max(5, durationMin)) * 60)
        event.notes = notes
        event.calendar = cal
        do { try store.save(event, span: .thisEvent, commit: true); return event.eventIdentifier }
        catch { return nil }
    }

    func removeEvent(id: String) {
        guard let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    func addReminder(title: String, due: Date?, notes: String = "") {
        guard remindersAuthorized, let list = appReminderList() else { return }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.notes = notes
        r.calendar = list
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        try? store.save(r, commit: true)
    }

    // MARK: - Importing occasions

    /// Birthdays (and any stored anniversaries) from Contacts.
    func importContactBirthdays() -> [Occasion] {
        guard contactsAuthorized else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactBirthdayKey, CNContactDatesKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var out: [Occasion] = []
        let cal = Calendar(identifier: .gregorian)
        try? contactStore.enumerateContacts(with: request) { c, _ in
            let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            if let b = c.birthday, let m = b.month, let d = b.day {
                var comps = DateComponents(); comps.year = b.year ?? 2000; comps.month = m; comps.day = d
                if let date = cal.date(from: comps) {
                    out.append(Occasion(title: name.isEmpty ? "Birthday" : "\(name)'s birthday",
                                        type: "birthday", dateEpoch: date.timeIntervalSince1970,
                                        recurringAnnual: true, person: name, source: "contacts"))
                }
            }
            for labeled in c.dates {
                let label = (labeled.label ?? "").lowercased()
                guard label.contains("anniversary") else { continue }
                let v = labeled.value as DateComponents
                if let m = v.month, let d = v.day {
                    var comps = DateComponents(); comps.year = v.year ?? 2000; comps.month = m; comps.day = d
                    if let date = cal.date(from: comps) {
                        out.append(Occasion(title: name.isEmpty ? "Anniversary" : "\(name) anniversary",
                                            type: "anniversary", dateEpoch: date.timeIntervalSince1970,
                                            recurringAnnual: true, person: name, source: "contacts"))
                    }
                }
            }
        }
        return out
    }

    /// All-day occasions from the system Birthdays calendar / events over the next year.
    func occasionsFromCalendar() -> [Occasion] {
        guard calAuthorized else { return [] }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .year, value: 1, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { ev -> Occasion? in
            let title = ev.title ?? ""
            let lower = title.lowercased()
            let isBirthday = ev.calendar.title.lowercased().contains("birthday") || lower.contains("birthday")
            let isAnniv = lower.contains("anniversary")
            guard isBirthday || isAnniv, let start = ev.startDate else { return nil }
            return Occasion(title: title, type: isBirthday ? "birthday" : "anniversary",
                            dateEpoch: start.timeIntervalSince1970, recurringAnnual: true, source: "calendar")
        }
    }
}
