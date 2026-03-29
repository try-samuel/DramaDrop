# Project Specification: BossMusic (macOS Menu Bar Utility)

## 1. Overview
A lightweight macOS menu bar application that monitors the user's local calendar and dramatically plays a user-selected audio file (e.g., MP3/WAV) exactly 2 minutes before a scheduled meeting begins.

## 2. Tech Stack & Environment
* **Target:** macOS 14.0+ 
* **Language:** Swift 5.9+
* **UI Framework:** SwiftUI (Strictly programmatic, NO Storyboards or XIBs)
* **Core Frameworks:** `EventKit` (Calendar), `AVFoundation` (Audio), `AppKit` (File picking)

## 3. Architecture & State Boundaries
The application must strictly separate concerns into the following domains. Do not tightly couple these managers.
* `App.swift`: The main entry point using `MenuBarExtra`. Manages high-level lifecycle.
* `CalendarService`: Singleton or Observable class. Handles `EKEventStore`, permissions, and querying the next upcoming non-all-day event for the current day.
* `AudioEngine`: Handles `AVAudioPlayer` state (play, stop, fade out).
* `StorageManager`: Handles persisting the user's custom audio file URL. **Must use Security-Scoped Bookmarks** to retain access to the file across app restarts due to the macOS App Sandbox.
* `ScheduleEngine`: The background timer that diffs the current time against the `CalendarService`'s next event and triggers the `AudioEngine`.

## 4. Unbreakable Rules for the AI Agent
1.  **Read Before Writing:** Always read this `SPEC.md` document before executing any code generation.
2.  **No Deprecated APIs:** Use modern Swift concurrency (`async/await`) where applicable. 
3.  **App Sandbox Compliance:** macOS sandboxing rules apply. File access outside the app container requires explicit user selection via `NSOpenPanel` and persisting that access via Bookmark Data.
4.  **Zero UI Clutter:** The app lives entirely in the Menu Bar. Do not create a main window (`WindowGroup`).
5.  **File Isolation:** When instructed to modify a specific file, do not modify or hallucinate changes to unreferenced files.
