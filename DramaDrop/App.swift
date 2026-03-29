import AppKit
import SwiftUI

@main
struct DramaDropApp: App {
    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var storageManager = StorageManager.shared
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var scheduleEngine = ScheduleEngine.shared
    @State private var hasAttemptedPermissionRequest = false

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
            MenuBarContentView(
                calendarService: calendarService,
                storageManager: storageManager,
                audioEngine: audioEngine,
                scheduleEngine: scheduleEngine
            )
        } label: {
            MenuBarLabelView(liveMeetingTitle: scheduleEngine.liveMeeting?.displayTitle)
                .accessibilityLabel(scheduleEngine.liveMeeting.map { "\($0.displayTitle) is live!" } ?? "DramaDrop")
                .simultaneousGesture(TapGesture().onEnded {
                    requestCalendarAccessOnFirstClick()
                })
        }
        .menuBarExtraStyle(.window)
    }

    private func requestCalendarAccessOnFirstClick() {
        guard !hasAttemptedPermissionRequest else {
            return
        }

        hasAttemptedPermissionRequest = true

        Task {
            await calendarService.requestCalendarAccessIfNeeded()
        }
    }
}

private struct MenuBarLabelView: View {
    let liveMeetingTitle: String?

    var body: some View {
        if let liveMeetingTitle {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                PulsingStatusDot()
                Text("\(liveMeetingTitle) is live!")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize()
        } else {
            Image(systemName: "calendar.badge.clock")
        }
    }
}

private struct PulsingStatusDot: View {
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .opacity(isDimmed ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDimmed)
            .onAppear {
                isDimmed = true
            }
    }
}

private struct MenuBarContentView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var storageManager: StorageManager
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var scheduleEngine: ScheduleEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            meetingSection
            Divider()
            audioSection
            Divider()
            footerSection
        }
        .padding(14)
        .frame(width: 280)
        .task {
            await calendarService.refreshNextMeetingIfAuthorized()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DramaDrop")
                .font(.headline)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if let liveMeeting = scheduleEngine.liveMeeting {
            return "\(liveMeeting.displayTitle) is live right now."
        }

        if audioEngine.isPlaying {
            return "Playing your pre-meeting anthem."
        }

        return "Your meeting cue is armed."
    }

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Meeting")
                .font(.subheadline.weight(.semibold))

            if calendarService.hasCalendarAccess {
                if let nextMeeting = calendarService.nextMeeting {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(nextMeeting.displayTitle)
                                .font(.headline)
                                .lineLimit(2)

                            Text(nextMeeting.startDate.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(calendarService.isLoadingNextMeeting ? "Checking today's meetings…" : "No upcoming meetings are left for today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                calendarAccessPrompt
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anthem")
                .font(.subheadline.weight(.semibold))

            if let selectedAudioFileName = storageManager.selectedAudioFileName {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)

                    Text(selectedAudioFileName)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            } else {
                Text("Choose the audio file that should fire before meetings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(storageManager.selectedAudioURL == nil ? "Select Anthem..." : "Change Anthem...") {
                Task {
                    await storageManager.selectAnthem()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if storageManager.selectionErrorMessage != nil || audioEngine.playbackErrorMessage != nil {
                Text("Audio setup needs attention. Re-select the anthem if playback stops working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calendarAccessPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar access is required before DramaDrop can watch for meetings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Enable Calendar Access") {
                Task {
                    await calendarService.requestCalendarAccessIfNeeded()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(calendarService.isRequestInFlight)

            if calendarService.showsSettingsHint {
                Text("Use System Settings > Privacy & Security > Calendars if access was previously denied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Spacer()

            Button("Quit DramaDrop") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
