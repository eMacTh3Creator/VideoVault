<p align="center">
  <img src="VideoVault/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="VideoVault">
</p>

<h1 align="center">VideoVault</h1>

<p align="center">
  A native macOS app for downloading videos from YouTube, Vimeo, Twitter/X, TikTok, Reddit, and 1000+ other sites.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-native-purple" alt="SwiftUI">
  <img src="https://img.shields.io/github/v/release/eMacTh3Creator/VideoVault?color=green" alt="Latest Release">
  <img src="https://img.shields.io/github/license/eMacTh3Creator/VideoVault" alt="License">
</p>

---

## Overview

VideoVault is a clean, native macOS download manager built on top of [yt-dlp](https://github.com/yt-dlp/yt-dlp). Paste in one URL or hundreds — VideoVault handles fetching, queuing, and downloading in the background while you get on with your day.

Supports YouTube, Vimeo, Twitter/X, TikTok, Instagram, Reddit, Twitch, and [1000+ other sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).

---

## Features

- **Batch downloads** — paste unlimited URLs (one per line), queue them all at once
- **Multiple formats** — MP3 audio, 720p / 1080p / 1440p / 4K video, or best available
- **Background processing** — downloads run off the main thread; the UI never freezes
- **Configurable concurrency** — run 1–8 simultaneous downloads
- **Smart resolution fallback** — if a requested resolution isn't available, falls back to best quality automatically
- **YouTube-ready** — browser cookie support (Safari, Chrome, Firefox, Brave, Edge) and JavaScript runtime detection without forcing obsolete player clients
- **ffmpeg integration** — auto-detected for stream merging and MP3 conversion; one-click install in the app
- **Embed metadata** — optionally embed thumbnails, titles, and uploader info into downloaded files
- **Organize by source** — automatically sort downloads into per-site subdirectories
- **Retry support** — retry individual failed items or all failures at once
- **Persistent queue** — your download history survives app restarts
- **Native macOS UI** — NavigationSplitView layout, live progress, context menus, notifications
- **Automatic updates** — verified yt-dlp updates at launch and every six hours; signed Sparkle app updates with automatic check/install controls
- **Duplicate protection** — destination-specific download index, stable media identities, and exact-content checks; a duplicate finder safely moves selected extra copies to Trash
- **Independent fallback** — Streamlink for supported sites and ffmpeg for direct media links when ordinary yt-dlp attempts fail
- **Menu bar controls** — live active/queued/failed counts, quick paste best video or original-quality audio, retries, and queue controls without raising the window
- **Home navigation** — return to the Add URLs home screen without deleting a download

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| macOS 13.0+ | Operating system | — |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Download engine | Auto-install in app, or `brew install yt-dlp` |
| [ffmpeg](https://ffmpeg.org) | Stream merging + MP3 | Auto-install in app, or `brew install ffmpeg` |
| Deno or Node.js | YouTube JavaScript challenges | Deno installs automatically when a runtime is missing |
| [Streamlink](https://streamlink.github.io/) (optional) | Independent downloader fallback | Install in Settings using Python 3.10+, or `brew install streamlink` |

> Both yt-dlp and ffmpeg can be installed with one click during first launch. Homebrew is not required.

---

## Installation

### Option 1 — Download the release (recommended)

1. Download **[VideoVault-v1.3-macOS.zip](https://github.com/eMacTh3Creator/VideoVault/releases/latest)** from the Releases page
2. Unzip and drag `VideoVault.app` to your `/Applications` folder
3. **First launch:** right-click the app → **Open** (required once to bypass Gatekeeper on unsigned apps)
4. Follow the onboarding to install yt-dlp and ffmpeg

Version 1.2 and older need this one manual install to gain the updater. Version 1.3 checks for signed future releases automatically. Builds are universal (Intel and Apple Silicon); the bundle is ad-hoc signed, not Apple-notarized.

### Option 2 — Build from source

```bash
git clone https://github.com/eMacTh3Creator/VideoVault.git
cd VideoVault
open VideoVault.xcodeproj
```

Select the **VideoVault** scheme, choose your Mac as the destination, and press **⌘R** to build and run.

---

## Usage

### Adding downloads

Click **+** in the toolbar or press **⌘N** to open the Add Downloads sheet.

Paste one URL per line — there's no limit on how many you can add at once:

```
https://www.youtube.com/watch?v=...
https://vimeo.com/...
https://twitter.com/user/status/...
https://www.tiktok.com/@user/video/...
```

Choose your format, then click **Download**.

### Formats

| Format | Description |
|---|---|
| MP3 Audio | Extracts audio and converts to MP3 (requires ffmpeg) |
| Best Audio (Original Quality) | Best available original audio track, without forced lossy conversion |
| 720p Video | HD video, smaller file size |
| 1080p Video | Full HD — recommended for most content |
| 1440p Video | 2K — for high-resolution displays |
| 4K Video | Maximum resolution where available |
| Best Quality Video | Highest available resolution, no cap |

If a requested resolution isn't available for a given video, VideoVault automatically falls back to the best available quality.

Best video uses MKV when streams need merging so high-quality codecs are not discarded solely to fit MP4. Original audio uses the source container when possible.

### Processing the queue

Downloads begin automatically when you add URLs. You can also:

- **⌘R** — manually start processing the queue
- **⌘.** — stop all active downloads
- Click any item in the sidebar to see live progress in the detail panel
- Right-click any item for options: Cancel, Retry, Show in Finder, Copy URL, Delete
- **Home** in the toolbar returns to the native welcome screen while keeping your queue and files
- Click or right-click the menu bar download icon for counts and quick paste actions
- **Find Duplicates** scans the destination recursively and compares bytes, not just filenames

With duplicate skipping enabled, repeats of the same media and format are skipped before downloading when indexed files still exist. Exact duplicate content discovered after downloading is consolidated without losing the existing copy. Different formats are separately indexed; pre-existing unindexed files can only be recognized by their content after the download. The duplicate finder always keeps at least one copy and re-verifies selected files before moving extras to Trash.

---

## Settings

Open Settings with the gear button in the toolbar.

| Setting | Description |
|---|---|
| Download Location | Where files are saved (default: `~/Downloads/VideoVault`) |
| Organize by source | Sort downloads into subfolders per site (e.g. `youtube`, `vimeo`) |
| Default format | Format pre-selected when opening Add Downloads |
| Concurrent downloads | 1–8 simultaneous downloads |
| Auto-retry failed | Automatically retry failed downloads |
| Embed thumbnail | Embed cover art into the downloaded file |
| Embed metadata | Embed title, uploader, and other metadata |
| Launch at login | Start VideoVault when you log in |
| Show notifications | macOS notifications on download completion |
| Use browser cookies | Pass your browser's cookies to yt-dlp (helps with age-restricted or member-only YouTube content) |
| yt-dlp path | Path to the yt-dlp binary |
| ffmpeg path | Path to the ffmpeg binary |
| Automatic yt-dlp updates | Check official releases every six hours, verify SHA-256, then install into an app-owned tools folder when idle |
| App updates | Automatically check/download signed releases; also available from the app and menu bar menus |
| Skip duplicates | Avoid indexed repeats and consolidate exact-content duplicates in the destination |
| Fallback downloader | Allow supported Streamlink or direct-media ffmpeg fallback; configure/install Streamlink in Settings |

---

## YouTube Notes

YouTube changes regularly. Leave automatic yt-dlp updates enabled and use **Settings > Check / Update** when troubleshooting. A missing YouTube JavaScript runtime is installed automatically alongside yt-dlp. Browser cookies are optional and should only be enabled for content you can access with your own account.

Metadata lookup has a timeout and is optional for downloading. Technical failures try alternate format selectors and the independent fallback when supported. Streamlink is primarily a streaming downloader, not a universal replacement for every yt-dlp site. Website safety refusals, removed/private media, DRM, geo-blocks, and account restrictions are explained rather than bypassed. A site asking you to contact its support may need the site's intervention.

---

## Supported Sites

VideoVault supports [all sites that yt-dlp supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md) — over 1000, including:

YouTube · Vimeo · Twitter/X · TikTok · Instagram · Reddit · Twitch · Dailymotion · SoundCloud · Bandcamp · BBC iPlayer · CNN · NBC · ABC · ESPN · Crunchyroll · Nebula · Rumble · Odysee · and many more.

---

## Building a Release

Run the automated tests:

```bash
VIDEOVAULT_TEST_ROOT=/tmp/VideoVault-tests swift test
```

For live official dependency installation checks, also set `VIDEOVAULT_VERIFY_DEPENDENCIES=1`. Download integration tests require yt-dlp and ffmpeg and use locally generated media.

To build the universal bundle, zip it, and generate the signed update feed:

```bash
bash script/package_release.sh /tmp/VideoVault-release-artifacts
```

The Sparkle private signing key is stored in the maintainer's login Keychain under account `videovault`, never in this repository. Packaging requires that key and validates it against the app's public key. Upload the matching zip and checksums to the GitHub release before publishing the generated `docs/appcast.xml`. Do not edit a signed feed manually. See `script/prepare_update_test.sh` for an isolated local installation/relaunch test.

> **Note:** The app is not notarized. Distribute to other Macs as a zip; recipients may need to approve first launch. Notarization requires an Apple Developer account.

---

## Project Structure

```
VideoVault/
├── Models/
│   ├── AppSettings.swift       # UserDefaults-backed settings singleton
│   ├── DownloadItem.swift      # Core data model + DownloadFormat enum
│   └── DownloadQueue.swift     # Observable queue with JSON persistence
├── Services/
│   ├── DownloadManager.swift   # Orchestrates downloads with concurrency control
│   ├── StorageManager.swift    # File system operations
│   └── YTDLPService.swift      # yt-dlp process wrapper (async/await)
├── Views/
│   ├── ContentView.swift       # Root NavigationSplitView
│   ├── SidebarView.swift       # Download list with filters + search
│   ├── DownloadDetailView.swift # Per-item progress and actions
│   ├── AddDownloadsView.swift  # Batch URL input sheet
│   ├── SettingsView.swift      # Settings sheet
│   └── OnboardingView.swift    # First-run dependency setup
└── Utilities/
    └── LaunchAtLogin.swift     # Login item management
```

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with SwiftUI · Powered by <a href="https://github.com/yt-dlp/yt-dlp">yt-dlp</a>
</p>
