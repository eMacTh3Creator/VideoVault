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
