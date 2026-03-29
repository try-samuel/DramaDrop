import Combine
import Foundation
import OSLog
@preconcurrency import EventKit

struct MeetingSummary: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Meeting" : trimmedTitle
    }
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isRequestInFlight = false
    @Published private(set) var isLoadingNextMeeting = false
    @Published private(set) var nextMeeting: MeetingSummary?

    private let eventStoreCoordinator: EventStoreCoordinator
    private let logger = Logger(subsystem: "com.samuel.DramaDrop", category: "CalendarService")
    private let calendar = Calendar.current

    private init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStoreCoordinator = EventStoreCoordinator(eventStore: eventStore)
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        if hasCalendarAccess {
            Task { [weak self] in
                await self?.refreshNextMeetingIfAuthorized()
            }
        }
    }

    var hasCalendarAccess: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    var showsSettingsHint: Bool {
        switch authorizationStatus {
        case .denied, .restricted, .writeOnly:
            return true
        default:
            return false
        }
    }

    var statusMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Calendar access will be requested the first time you open this menu."
        case .restricted:
            return "Calendar access is restricted on this Mac."
        case .denied:
            return "Calendar access was denied."
        case .writeOnly:
            return "Calendar access is limited to write-only."
        case .authorized, .fullAccess:
            return "Calendar access granted."
        @unknown default:
            return "Calendar access status is unavailable."
        }
    }

    @discardableResult
    func requestCalendarAccessIfNeeded() async -> Bool {
        refreshAuthorizationStatus()

        guard !isRequestInFlight else {
            return hasCalendarAccess
        }

        guard authorizationStatus == .notDetermined else {
            if hasCalendarAccess {
                await refreshNextMeetingIfAuthorized()
            } else {
                nextMeeting = nil
            }
            return hasCalendarAccess
        }

        isRequestInFlight = true
        defer { isRequestInFlight = false }

        do {
            _ = try await eventStoreCoordinator.requestFullAccessToEvents()
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            refreshAuthorizationStatus()
            nextMeeting = nil
            return false
        }

        refreshAuthorizationStatus()

        if hasCalendarAccess {
            await refreshNextMeetingIfAuthorized()
        } else {
            nextMeeting = nil
        }

        return hasCalendarAccess
    }

    func fetchEventsForCurrentDay(now: Date = .now) async -> [MeetingSummary] {
        refreshAuthorizationStatus()

        guard hasCalendarAccess else {
            nextMeeting = nil
            logger.info("Skipping calendar fetch because access is unavailable.")
            return []
        }

        let meetings = await eventStoreCoordinator.eventsForCurrentDay(now: now, calendar: calendar)
        logger.info("Fetched \(meetings.count, privacy: .public) meetings for today.")
        return meetings
    }

    @discardableResult
    func refreshNextMeetingIfAuthorized(now: Date = .now) async -> [MeetingSummary] {
        guard !isLoadingNextMeeting else {
            return []
        }

        isLoadingNextMeeting = true
        defer { isLoadingNextMeeting = false }

        let todayMeetings = await fetchEventsForCurrentDay(now: now)
        nextMeeting = todayMeetings.first(where: { $0.startDate > now })

        if let nextMeeting {
            let startTime = nextMeeting.startDate.formatted(date: .omitted, time: .shortened)
            logger.info("Next meeting is \(nextMeeting.displayTitle, privacy: .public) at \(startTime, privacy: .public).")
        } else {
            logger.info("No upcoming meetings remain for today.")
        }

        return todayMeetings
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
}

private actor EventStoreCoordinator {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    func requestFullAccessToEvents() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    // Run the EventKit query off the main actor to keep the menu bar responsive.
    func eventsForCurrentDay(now: Date, calendar: Calendar) -> [MeetingSummary] {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: startOfTomorrow, calendars: nil)

        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                MeetingSummary(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled Meeting",
                    startDate: event.startDate,
                    endDate: event.endDate
                )
            }
    }
}
