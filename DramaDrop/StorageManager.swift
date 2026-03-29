import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

@MainActor
final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    @Published private(set) var selectedAudioURL: URL?
    @Published private(set) var selectedAudioFileName: String?
    @Published private(set) var selectionErrorMessage: String?

    private let bookmarkKey = "selectedAnthemBookmarkData"
    private let logger = Logger(subsystem: "com.samuel.DramaDrop", category: "StorageManager")
    private let userDefaults: UserDefaults
    private var activeSecurityScopedURL: URL?

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        _ = restoreSelectedAudioURL()
    }

    func selectAnthem() async {
        guard let selectedURL = await presentOpenPanel() else {
            logger.info("Audio file selection was cancelled.")
            return
        }

        do {
            try persistSecurityScopedBookmark(for: selectedURL)
            selectionErrorMessage = nil
        } catch {
            selectionErrorMessage = "Could not save access to the selected anthem."
            logger.error("Failed to persist bookmark for selected audio file: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func restoreSelectedAudioURL() -> URL? {
        guard let bookmarkData = userDefaults.data(forKey: bookmarkKey) else {
            clearResolvedSelection()
            return nil
        }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            activateSecurityScope(for: resolvedURL)

            if isStale {
                try updateBookmarkData(for: resolvedURL)
                logger.info("Refreshed stale security-scoped bookmark for \(resolvedURL.lastPathComponent, privacy: .public).")
            } else {
                logger.info("Resolved stored audio bookmark for \(resolvedURL.lastPathComponent, privacy: .public).")
            }

            selectionErrorMessage = nil
            return resolvedURL
        } catch {
            logger.error("Failed to resolve stored audio bookmark: \(error.localizedDescription, privacy: .public)")
            userDefaults.removeObject(forKey: bookmarkKey)
            clearResolvedSelection()
            selectionErrorMessage = "Saved anthem access is no longer valid."
            return nil
        }
    }

    private func presentOpenPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.title = "Select Anthem"
        panel.message = "Choose an audio file to play before meetings."
        panel.prompt = "Select"

        NSApp.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func persistSecurityScopedBookmark(for url: URL) throws {
        let bookmarkData = try createBookmarkData(for: url)
        userDefaults.set(bookmarkData, forKey: bookmarkKey)
        activateSecurityScope(for: url)
        logger.info("Stored security-scoped bookmark for \(url.lastPathComponent, privacy: .public).")
    }

    private func updateBookmarkData(for url: URL) throws {
        let bookmarkData = try createBookmarkData(for: url)
        userDefaults.set(bookmarkData, forKey: bookmarkKey)
    }

    private func createBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func activateSecurityScope(for url: URL) {
        if let activeSecurityScopedURL,
           activeSecurityScopedURL.standardizedFileURL != url.standardizedFileURL {
            activeSecurityScopedURL.stopAccessingSecurityScopedResource()
            self.activeSecurityScopedURL = nil
        }

        if activeSecurityScopedURL?.standardizedFileURL != url.standardizedFileURL {
            let didStartAccess = url.startAccessingSecurityScopedResource()

            if !didStartAccess {
                logger.warning("Failed to start security-scoped access for \(url.lastPathComponent, privacy: .public).")
            }

            activeSecurityScopedURL = didStartAccess ? url : nil
        }

        selectedAudioURL = url
        selectedAudioFileName = url.lastPathComponent
    }

    private func clearResolvedSelection() {
        if let activeSecurityScopedURL {
            activeSecurityScopedURL.stopAccessingSecurityScopedResource()
            self.activeSecurityScopedURL = nil
        }

        selectedAudioURL = nil
        selectedAudioFileName = nil
    }
}
