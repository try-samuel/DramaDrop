@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
final class AudioEngine: NSObject, ObservableObject {
    static let shared = AudioEngine()

    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingFileName: String?
    @Published private(set) var playbackErrorMessage: String?

    private let logger = Logger(subsystem: "com.samuel.DramaDrop", category: "AudioEngine")
    private var audioPlayer: AVAudioPlayer?
    private var activePlaybackURL: URL?

    private override init() {
        super.init()
    }

    func play(url: URL) {
        stopPlayback()
        playbackErrorMessage = nil

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        guard didStartAccessing else {
            playbackErrorMessage = "Could not access the selected anthem."
            logger.error("Failed to start security-scoped access for \(url.lastPathComponent, privacy: .public).")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            guard player.play() else {
                url.stopAccessingSecurityScopedResource()
                playbackErrorMessage = "Audio playback could not be started."
                logger.error("AVAudioPlayer reported a failed play() for \(url.lastPathComponent, privacy: .public).")
                return
            }

            audioPlayer = player
            activePlaybackURL = url
            nowPlayingFileName = url.lastPathComponent
            isPlaying = true
            logger.info("Started playback for \(url.lastPathComponent, privacy: .public).")
        } catch {
            url.stopAccessingSecurityScopedResource()
            playbackErrorMessage = "Could not load the selected anthem."
            logger.error("Failed to initialize AVAudioPlayer for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        finishPlayback(clearError: false)
    }

    private func finishPlayback(clearError: Bool) {
        audioPlayer?.delegate = nil
        audioPlayer = nil
        isPlaying = false
        nowPlayingFileName = nil

        if clearError {
            playbackErrorMessage = nil
        }

        if let activePlaybackURL {
            activePlaybackURL.stopAccessingSecurityScopedResource()
            logger.info("Stopped security-scoped access for \(activePlaybackURL.lastPathComponent, privacy: .public).")
            self.activePlaybackURL = nil
        }
    }
}

@MainActor
extension AudioEngine: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logger.info("Finished playback for \(self.nowPlayingFileName ?? "unknown", privacy: .public); success=\(flag, privacy: .public).")
        finishPlayback(clearError: false)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        if let error {
            playbackErrorMessage = "The selected anthem could not be decoded."
            logger.error("Audio decode error: \(error.localizedDescription, privacy: .public)")
        }

        finishPlayback(clearError: false)
    }
}
