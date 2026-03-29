# DramaDrop

DramaDrop is a macOS menu bar utility that watches your local calendar and plays a user-selected audio file two minutes before the next meeting starts.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools
- Calendar access for the app

## Install Options

### Option 1: CLI install from GitHub Releases

```bash
curl -fsSL https://raw.githubusercontent.com/try-samuel/DramaDrop/main/install.sh | bash
```

This installs `DramaDrop.app` into `/Applications` and adds a `dramadrop` launcher into `~/.local/bin`.
If you publish the project under a different GitHub repo, override the target with `DRAMADROP_REPO=owner/repo`.

### Option 2: Build locally

This is the most reliable path for anyone on a Mac who wants to run the app from source.

1. Clone the repository.
2. Build the app bundle:

```bash
mkdir -p build/DramaDrop.app/Contents/MacOS
cp DramaDrop/Info.plist build/DramaDrop.app/Contents/Info.plist

CLANG_MODULE_CACHE_PATH="$PWD/.module-cache" swiftc \
  -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  DramaDrop/App.swift \
  DramaDrop/CalendarService.swift \
  DramaDrop/StorageManager.swift \
  DramaDrop/AudioEngine.swift \
  DramaDrop/ScheduleEngine.swift \
  -o build/DramaDrop.app/Contents/MacOS/DramaDrop \
  -framework SwiftUI \
  -framework EventKit \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -framework AVFoundation

codesign --force --sign - build/DramaDrop.app
open build/DramaDrop.app
```

### Option 3: Download the CI build artifact

1. Open the latest successful GitHub Actions run for `Build DramaDrop`.
2. Download the artifact that matches your Mac: `DramaDrop-arm64` for Apple Silicon or `DramaDrop-x64` for Intel.
3. Unzip the downloaded archive.
4. Move `DramaDrop.app` into `Applications` or another local folder.
5. Launch it with Finder. If macOS blocks the first launch because the app is not notarized, right-click the app, choose `Open`, and confirm.

## Using The App

1. Launch `DramaDrop.app`.
2. Click the menu bar icon once to trigger the calendar permission prompt.
3. In the dropdown, choose `Select Anthem...` and pick an MP3 or WAV file.
4. Create a calendar event a few minutes in the future.
5. Leave DramaDrop running in the menu bar and wait for the two-minute trigger window.

## First-Time Setup

- Calendar access is required before DramaDrop can read upcoming meetings.
- The anthem file is stored using a security-scoped bookmark so it remains accessible after restart.
- The app must stay running in the menu bar for the trigger timer to fire.

## What To Expect

- The menu bar label switches to `<meeting name> is live!` when the tracked meeting reaches its start time.
- The pre-meeting anthem starts roughly two minutes before the meeting.
- The anthem stops when the meeting begins.

## Continuous Integration

This repo includes a GitHub Actions workflow at `.github/workflows/build.yml` that:

- builds signed app bundles for Apple Silicon and Intel macOS
- packages each `.app` into a zip file
- uploads build artifacts on every push and pull request
- attaches release zips when a tag is pushed

## Project Layout

- `DramaDrop/App.swift`: menu bar app entry point and UI
- `DramaDrop/CalendarService.swift`: EventKit permissions and meeting queries
- `DramaDrop/StorageManager.swift`: security-scoped bookmark persistence
- `DramaDrop/AudioEngine.swift`: audio playback lifecycle
- `DramaDrop/ScheduleEngine.swift`: background trigger logic
