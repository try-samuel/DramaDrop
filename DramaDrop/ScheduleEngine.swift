import Combine
import Foundation
import OSLog

@MainActor
final class ScheduleEngine: ObservableObject {
    static let shared = ScheduleEngine()

    @Published private(set) var lastPlayedMeetingID: String?
    @Published private(set) var liveMeeting: MeetingSummary?

    private let logger = Logger(subsystem: "com.samuel.DramaDrop", category: "ScheduleEngine")
    private let timerPublisher = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    private var timerCancellable: AnyCancellable?
    private var meetingStartTimer: Timer?
    private var meetingEndTimer: Timer?
    private var armedMeeting: MeetingSummary?

    private init() {
        timerCancellable = timerPublisher.sink { [weak self] currentDate in
            guard let self else {
                return
            }

            Task { @MainActor in
                await self.handleTimerTick(now: currentDate)
            }
        }

        Task { [weak self] in
            await self?.handleTimerTick(now: .now)
        }
    }

    private func handleTimerTick(now: Date) async {
        let meetings = await CalendarService.shared.refreshNextMeetingIfAuthorized(now: now)
        synchronizeLiveMeeting(now: now, meetings: meetings)

        guard let nextMeeting = CalendarService.shared.nextMeeting else {
            return
        }

        let secondsUntilMeeting = nextMeeting.startDate.timeIntervalSince(now)
        let triggerWindow = 100.0 ... 120.0

        guard triggerWindow.contains(secondsUntilMeeting) else {
            return
        }

        guard lastPlayedMeetingID != nextMeeting.id else {
            logger.info("Skipping duplicate trigger for meeting \(nextMeeting.displayTitle, privacy: .public).")
            return
        }

        armMeetingStartTimer(for: nextMeeting, now: now)

        guard let selectedAudioURL = StorageManager.shared.selectedAudioURL else {
            logger.warning("Skipping trigger for meeting \(nextMeeting.displayTitle, privacy: .public) because no anthem is selected.")
            return
        }

        lastPlayedMeetingID = nextMeeting.id
        logger.info("Triggering anthem for meeting \(nextMeeting.displayTitle, privacy: .public) with \(Int(secondsUntilMeeting), privacy: .public) seconds remaining.")
        AudioEngine.shared.play(url: selectedAudioURL)
    }

    private func synchronizeLiveMeeting(now: Date, meetings: [MeetingSummary]) {
        if let currentMeeting = trackedLiveMeeting(from: meetings, now: now) {
            if liveMeeting?.id != currentMeeting.id {
                liveMeeting = currentMeeting
                logger.info("Meeting \(currentMeeting.displayTitle, privacy: .public) is now live.")
                armMeetingEndTimer(for: currentMeeting, now: now)
            }

            if lastPlayedMeetingID == currentMeeting.id, AudioEngine.shared.isPlaying {
                logger.info("Stopping anthem because meeting \(currentMeeting.displayTitle, privacy: .public) has started.")
                AudioEngine.shared.stopPlayback()
            }
        } else if let liveMeeting {
            let matchingMeeting = meeting(matching: liveMeeting.id, in: meetings)
            if matchingMeeting == nil || now >= liveMeeting.endDate {
                logger.info("Meeting \(liveMeeting.displayTitle, privacy: .public) has ended.")
                self.liveMeeting = nil
                meetingEndTimer?.invalidate()
                meetingEndTimer = nil
            }
        }
    }

    private func trackedLiveMeeting(from meetings: [MeetingSummary], now: Date) -> MeetingSummary? {
        if let armedMeeting = meeting(matching: armedMeeting?.id, in: meetings),
           armedMeeting.startDate <= now,
           now < armedMeeting.endDate {
            return armedMeeting
        }

        if let lastPlayedMeeting = meeting(matching: lastPlayedMeetingID, in: meetings),
           lastPlayedMeeting.startDate <= now,
           now < lastPlayedMeeting.endDate {
            return lastPlayedMeeting
        }

        if let liveMeeting = meeting(matching: liveMeeting?.id, in: meetings),
           liveMeeting.startDate <= now,
           now < liveMeeting.endDate {
            return liveMeeting
        }

        return nil
    }

    private func meeting(matching meetingID: String?, in meetings: [MeetingSummary]) -> MeetingSummary? {
        guard let meetingID else {
            return nil
        }

        return meetings.first(where: { $0.id == meetingID })
    }

    private func armMeetingStartTimer(for meeting: MeetingSummary, now: Date) {
        guard armedMeeting?.id != meeting.id else {
            return
        }

        armedMeeting = meeting
        meetingStartTimer?.invalidate()

        let timeUntilStart = max(meeting.startDate.timeIntervalSince(now), 0)
        meetingStartTimer = Timer.scheduledTimer(withTimeInterval: timeUntilStart, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.liveMeeting = meeting
                self.armedMeeting = nil
                self.logger.info("Meeting \(meeting.displayTitle, privacy: .public) hit its start time.")

                if AudioEngine.shared.isPlaying {
                    self.logger.info("Stopping anthem because meeting \(meeting.displayTitle, privacy: .public) reached its scheduled start.")
                    AudioEngine.shared.stopPlayback()
                }

                self.armMeetingEndTimer(for: meeting, now: .now)
            }
        }
    }

    private func armMeetingEndTimer(for meeting: MeetingSummary, now: Date) {
        meetingEndTimer?.invalidate()

        let timeUntilEnd = max(meeting.endDate.timeIntervalSince(now), 0)
        meetingEndTimer = Timer.scheduledTimer(withTimeInterval: timeUntilEnd, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                if self.liveMeeting?.id == meeting.id {
                    self.logger.info("Meeting \(meeting.displayTitle, privacy: .public) reached its end time.")
                    self.liveMeeting = nil
                }
            }
        }
    }
}
