# Windows Development Build Verification

Date: 2026-10-07. Environment: Windows 11 ARM64 in Parallels, .NET SDK 10.0.401, Windows Desktop Runtime 10.0.12.

- Solution build: succeeded, zero warnings and zero errors.
- Regression + local-media integration suite: **42 checks passed**.
- Native Home handler preserves queue entries while clearing selection.
- Native Add URLs dialog accepts the selected quality; Settings edits a separate snapshot.
- Settings was tested with the same Fluent light theme as the app: saved default quality, readable heading and wrapping checkbox labels, 440x400 window scrolling, reachable footer, and isolated quality edits all passed.
- The corrected Settings window was visually inspected in the Windows VM; headings, checkbox labels, Browse, and Save/Cancel controls rendered correctly. Window styling is explicitly applied to the other dialogs as well.
- Per-job process-tree cancellation, bounded process timeout, add-while-active queueing, concurrency limit, UI heartbeat during 60,000 progress lines, and final queue persistence passed.
- Thumbnail unusual-extension recovery, normal/Force Retry, independent backup, and restrictions preservation passed.
- URL/media duplicate lookup, content-based duplicate finder and coalescing, and destination-boundary validation passed.
- Actual official yt-dlp/FFmpeg: local clip download, unknown-height 960p-to-720p downscale, MP3 conversion, best-audio extraction, and independent FFmpeg backup passed.
- Official dependency setup installed yt-dlp, FFmpeg/ffprobe, Deno, and Streamlink. Wrong-checksum test preserved the previous dependency.
- x64 and ARM64 self-contained publishes and Velopack installer/portable/update package generation succeeded.
- Window, icon, and Home layout were visually inspected in the running ARM64 app.

Published alongside the Mac installer in GitHub release v1.4 as unsigned Windows development previews. The GitHub Windows validation workflow passed on a Windows Server 2025 x64 runner: 36 regression checks, 42 regression/integration checks, verified dependency setup, and packaging for both architectures. Installed old-to-new application-update validation, physical x64 PC testing, and Windows Authenticode signing remain production release gates.

The macOS application and release files were not changed.
