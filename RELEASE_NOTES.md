# VideoVault v1.4

- Drag-to-Applications DMG with a custom installer background and an Applications shortcut.
- A new signed update channel, with automatic checks beginning on first launch. Customers do not need scripts or signing keys.
- Release packaging now produces and verifies the DMG and matching signed feed together. Publisher tooling prevents reusing a released version.
- Keeps Intel and Apple Silicon support, direct tool installers, Homebrew guidance on Apple Silicon, and existing queue/settings compatibility.

Install 1.4 manually once when upgrading from 1.3.x. This switches to the new publisher key; future updates are delivered through the app. The legacy feed is preserved. The installer is ad-hoc signed and not Apple-notarized.

Verification: universal build, mounted-DMG bundle signatures, disk-image integrity, and public-key verification of the feed and DMG passed. Isolated Sparkle updates from build 7 to build 8 passed through both ZIP and DMG downloads; installed signatures were verified.

## Windows v1.4.0 Development Preview

The first native C# / .NET 10 / WPF Windows builds are available alongside the existing Mac installer. The Mac assets and signed update channel are unchanged.

| Platform | Installer | Portable |
|---|---|---|
| Windows x64 (Intel / AMD) | [x64 Setup](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-x64-Setup.exe) | [x64 ZIP](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-x64-Portable.zip) |
| Windows ARM64 (Snapdragon / Parallels on Apple Silicon) | [ARM64 Setup](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-arm64-Setup.exe) | [ARM64 ZIP](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-arm64-Portable.zip) |

- Self-contained runtime: Windows users do not need to install .NET separately. Run the installer, or extract the portable ZIP and run `VideoVault.Windows.exe`.
- Independent asynchronous downloads, bounded metadata timeouts, responsive progress updates, queue persistence, and 1-8 simultaneous jobs.
- Verified setup of yt-dlp, FFmpeg/ffprobe, Deno, and Streamlink, with automatic yt-dlp checks on launch.
- Duplicate protection and content-based duplicate finding with safe Recycle Bin handling.
- Home navigation and tray active/queued/failed statistics, quick-paste best video/audio, and queue controls.
- Fixed Settings rendering: readable labels and buttons, wrapping options, small-screen scrolling, and saved-quality selection.
- Force Retry and supported backup paths preserve DRM, login, and website access restrictions.

**Verification:** 42 regression/local-media integration checks passed in Windows 11 ARM64 under Parallels, including actual downloads and audio conversion. ARM64 and x64 self-contained builds and packaging succeeded. Settings was visually checked in the VM.

**Development preview limitations:** Windows builds are unsigned and may trigger SmartScreen. Native x64 hardware and installed old-to-new application-update validation remain pending. Portable builds do not install app updates. Architecture-specific Velopack update packages and feeds are included for installed builds; this is not a claim that an end-to-end installed update has been tested.

Download checksum files are provided separately for x64 and ARM64. See the [Windows guide](https://github.com/eMacTh3Creator/VideoVault/blob/main/VideoVault-Windows/README.md) for details.

---

# VideoVault v1.3.4

Correct first-start setup guidance on Intel Macs.

- The current Homebrew macOS installer rejects Intel processors. Intel users now see a **Tool Setup…** guide with the built-in yt-dlp and ffmpeg installers.
- Hide Homebrew commands on Intel unless an existing Homebrew installation is detected. Keep Homebrew installation instructions on Apple Silicon.
- Show direct-installer errors alongside their buttons, so failures are actionable.
- Keep the universal Intel/Apple Silicon app and automatic tool re-checking.

Install the universal `Releases/VideoVault-v1.3.4-macOS.zip` manually. The signed updater feed is retained. The bundle is ad-hoc signed, not notarized. Homebrew installation instructions were checked against the current official installer and documentation; Homebrew was not installed on this Mac.

---

# VideoVault v1.3.3

First-start setup guidance for macOS 13 and later, on Intel and Apple Silicon.

- Add **Homebrew Setup…** to the welcome screen with the official installer command and copy buttons.
- Explain Terminal installation prompts and the installer's **Next steps** for shell setup.
- Offer **Open Terminal**, architecture-appropriate tool installation commands, and **Re-check Tools**.
- Refresh tool detection when returning to the app; keep Homebrew optional alongside the existing direct installers.

## Verification

- Core test suite: 31 tests executed, 3 skipped, 0 failures. Live dependency installation and real download tests were skipped because the optional tools were unavailable on this Mac.
- Universal release build and recursive bundle signature verification are checked during packaging.
- Homebrew commands were checked against its official installation documentation. The Homebrew installer was not run on the maintainer's Mac.

## Install

Download `Releases/VideoVault-v1.3.3-macOS.zip`, unzip, and move **VideoVault.app** to `/Applications`. This universal build supports Intel and Apple Silicon. It is ad-hoc signed, not Apple-notarized. This release requires manual installation; the existing signed updater feed is retained.

---

# VideoVault v1.3.2

Backup recovery and Force Retry patch for macOS 13 and later, on Intel and Apple Silicon.

## Fixes

- Fix incorrect classification of yt-dlp's unusual-extension diagnostic as a website safety refusal. This distinction allows recovery and backup downloaders to run.
- If optional thumbnail embedding triggers that error, retry once without writing/embedding the thumbnail. Unsafe-extension validation stays enabled; no unsafe-extension compatibility override is used.
- Subprocess failures and invalid/missing output files now reach the supported backup downloader, not just nonzero exit codes. Original and backup errors remain available if recovery fails.
- Add **Force Retry** to failed/cancelled download details and the right-click menu. It skips optional thumbnail/metadata processing and enables supported backup downloaders for that job, preserving global settings, requested format, and duplicate protection. The per-job choice survives queue persistence; normal Retry clears it.
- Genuine site restrictions, DRM/login requirements, and cancellation still prevent recovery attempts, including in Force Retry mode.

## Verification

- Eight new regressions cover the exact screenshot diagnostic, bounded thumbnail retry, independent backup routing, unsupported backup error reporting, real restrictions/cancellation, per-job overrides, queue compatibility, and manager-driven Force Retry.
- All 31 automated tests passed, including live official tool installation, real local video/audio downloads, fallback downloads, and the previous menu responsiveness regressions.
- Universal build and signed archive/bundle verification passed. Native click-testing of the new button was blocked by the locked Mac; its manager actions and per-job behavior were tested automatically.
- The real yt-dlp regression uses locally generated media and a malformed thumbnail filename ending in `.jpg.v1692889884`. It reproduces the extension error, then saves the video after the automatic thumbnail-free retry.
- The original tester's private video URL was not supplied. This verifies the reported error and recovery path, not that specific remote video. Streamlink still supports only a subset of websites.

## Install

Use **Check for Updates** in v1.3 or newer, or download **VideoVault-v1.3.2-macOS.zip** and move the included **VideoVault.app** to `/Applications`. The full universal `.app` is also tracked under `Releases/`. The app is ad-hoc signed, not Apple-notarized. No Windows binary is included.

---

# VideoVault v1.3.1

Menu bar responsiveness patch for macOS 13 and later, on Intel and Apple Silicon.

## Fixes

- Metadata fetching, download setup, file validation, and retry work run in independent background workers with immutable per-download settings.
- Progress output is coalesced into bounded UI updates, including while native menus are tracking. Queue JSON encoding and disk writes run on a separate serial background queue.
- Opening the menu no longer requests clipboard contents. Quick-paste and other commands execute after the menu closes, and live counts update without rebuilding the tracked menu.
- Cancelling one download does not interrupt other downloads. Cancelled jobs retain their slot until their subprocess has stopped. App shutdown waits asynchronously for workers and pending queue saves, with a bounded exit deadline.
- Both subprocess pipes drain without blocking reads. An exited downloader that leaves an inherited pipe open now produces a bounded error instead of hanging indefinitely.

## Install

Download **VideoVault-v1.3.1-macOS.zip**, unzip it, and move **VideoVault.app** to `/Applications`. The full universal `.app` is also tracked under `Releases/`. Existing v1.3 installations can use **Check for Updates**.

## Verification

- Five new responsiveness regressions cover 100,000 concurrent mailbox updates, slow queue storage, menu-close action ordering, inherited-pipe shutdown, and adding/cancelling downloads during 240,000+ progress lines.
- The concurrency stress test starts a second download during the first, queues a third, cancels only the first, and checks both remaining downloads complete. It checks the cancelled process exits and the UI heartbeat remains below 250 ms.
- All 23 automated tests passed, including real local video/audio downloads, fallback downloads, duplicate handling, official tool installation, and existing menu/clipboard behavior. The measured main-thread heartbeat peaked at 22 ms during the concurrency stress test, with 29 UI publications for 240,000+ progress lines.
- Native UI checks added a second URL during an active download and opened the Downloads menu during concurrent work. Signed Sparkle discovery, download, installation, and relaunch were exercised with test copies; the installed version was verified as 1.3.1/build 4.
- Universal release build, archive signature verification, and recursive bundle signature validation passed. The repository bundle was also validated outside the cloud-synced checkout.

Website access restrictions and fallback limitations from v1.3 still apply. This patch does not include a Windows binary.

---

# VideoVault v1.3

Native macOS release for Intel and Apple Silicon, requiring macOS 13 or later.

## What's New

- Automatic official yt-dlp checks at launch and every six hours, checksum-verified installation into an app-owned folder, and a manual Check / Update control. Updates wait for downloads to finish.
- Signed Sparkle app updates, automatic check/download controls, and Check for Updates in the application and menu bar menus. Update installation waits for active downloads.
- Destination-specific duplicate skipping with media identities, format-aware indexing, and exact-content consolidation. The new duplicate finder scans nested folders and safely selects extra copies for Trash while retaining at least one copy per group.
- Bounded metadata fetching, concurrent pipe draining, reliable cancellation of child processes, guarded progress updates, transient retries, and validated final output paths.
- Independent Streamlink fallback for supported sites and ffmpeg fallback for direct media links. Streamlink can be installed into a private Python environment from Settings, or detected from Homebrew.
- A Home button and Home menu command return to the native Add URLs screen without deleting downloads.
- A native menu bar icon shows active, queued, and failed counts. Quick Paste Best Video Quality and Quick Paste Best Audio Quality add clipboard links without raising the window. Additional commands open the home screen, add URLs, manage the queue, find duplicates, and check updates.
- Best audio keeps the original audio codec instead of forcing M4A conversion. Best video merging supports MKV to preserve available codecs. Existing saved audio selections migrate automatically.

## Install

Download **VideoVault-v1.3-macOS.zip**, unzip it, and move **VideoVault.app** to `/Applications`. The zip contains the full app, icon resources, and updater framework. The built `.app` is also tracked under `Releases/` in the repository.

Version 1.2 and older require this manual installation once to gain automatic updates. The app is ad-hoc signed, not Apple-notarized; first launch may require macOS approval.

yt-dlp and ffmpeg are required for full-quality downloads and audio extraction. Streamlink is optional and its in-app installer requires Python 3.10 or newer. A missing YouTube JavaScript runtime is installed during yt-dlp setup.

## Verification

- 18 automated tests passed, including live official yt-dlp and Streamlink installation, corrupt-update rejection, real local video/audio downloads, direct-media fallback, duplicate indexing/scanning, concurrent duplicate consolidation, subprocess timeout/cancellation, live menu counts, and both quick-paste formats.
- The final source was re-tested with the CI-style command: 17 passed, one optional live dependency-installation test skipped, no failures.
- Universal release build and strict recursive bundle signature validation passed. The release archive and update feed signatures were independently verified.
- Sparkle discovery, download, installation, and relaunch were exercised twice against a signed local feed with isolated test copies; the final installed build was verified as version 1.3/build 3.
- Native UI checks confirmed completed downloads, duplicate skipping, Home without deletion, and exact-content duplicate scan results.
- The originally reported YouTube URL exposes a valid 720p video/audio selection with the updated yt-dlp engine.

## Limits

Independent fallback is not a universal replacement for every yt-dlp extractor. Website safety refusals, private/removed videos, DRM, geography, and account restrictions are explained rather than bypassed. The tester's specific safety-refused URL was not provided, so that individual failure could not be reproduced.

Existing unindexed destination files can be identified as exact-content duplicates after downloading; indexed repeats are skipped before downloading. Metadata differences can prevent byte-for-byte matches. The duplicate finder does not use filename similarity as proof that files are identical.

This release does not include a Windows binary.
