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
