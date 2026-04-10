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
- **YouTube-ready** — browser cookie support (Safari, Chrome, Firefox, Brave, Edge), custom user-agent, and extractor args to work around bot detection
- **ffmpeg integration** — auto-detected for stream merging and MP3 conversion; one-click install in the app
- **Embed metadata** — optionally embed thumbnails, titles, and uploader info into downloaded files
- **Organize by source** — automatically sort downloads into per-site subdirectories
- **Retry support** — retry individual failed items or all failures at once
- **Persistent queue** — your download history survives app restarts
- **Native macOS UI** — NavigationSplitView layout, live progress, context menus, notifications

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| macOS 13.0+ | Operating system | — |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Download engine | Auto-install in app, or `brew install yt-dlp` |
| [ffmpeg](https://ffmpeg.org) | Stream merging + MP3 | Auto-install in app, or `brew install ffmpeg` |

> Both yt-dlp and ffmpeg can be installed with one click during first launch. Homebrew is not required.

---

## Installation

### Option 1 — Download the release (recommended)

1. Download **[VideoVault-v1.0-macOS.zip](https://github.com/eMacTh3Creator/VideoVault/releases/latest)** from the Releases page
2. Unzip and drag `VideoVault.app` to your `/Applications` folder
3. **First launch:** right-click the app → **Open** (required once to bypass Gatekeeper on unsigned apps)
4. Follow the onboarding to install yt-dlp and ffmpeg

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
| Best Audio (M4A) | Best quality audio in M4A format |
| 720p Video | HD video, smaller file size |
| 1080p Video | Full HD — recommended for most content |
| 1440p Video | 2K — for high-resolution displays |
| 4K Video | Maximum resolution where available |
| Best Quality Video | Highest available resolution, no cap |

If a requested resolution isn't available for a given video, VideoVault automatically falls back to the best available quality.

### Processing the queue

Downloads begin automatically when you add URLs. You can also:

- **⌘R** — manually start processing the queue
- **⌘.** — stop all active downloads
- Click any item in the sidebar to see live progress in the detail panel
- Right-click any item for options: Cancel, Retry, Show in Finder, Copy URL, Delete

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

---

## YouTube Notes

YouTube actively tries to block automated downloaders. VideoVault includes several workarounds:

- **Browser cookies** — enable "Use browser cookies" in Settings and select your browser. yt-dlp will read your logged-in session, making YouTube treat the request as a normal browser visit.
- **User-agent spoofing** — VideoVault sends a realistic Chrome user-agent string.
- **Extractor args** — forces YouTube's web player client with English language settings.

If downloads still fail, try updating yt-dlp: `brew upgrade yt-dlp` or re-run the in-app installer.

---

## Supported Sites

VideoVault supports [all sites that yt-dlp supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md) — over 1000, including:

YouTube · Vimeo · Twitter/X · TikTok · Instagram · Reddit · Twitch · Dailymotion · SoundCloud · Bandcamp · BBC iPlayer · CNN · NBC · ABC · ESPN · Crunchyroll · Nebula · Rumble · Odysee · and many more.

---

## Building a Release

To create a distributable `.zip`:

```bash
xcodebuild -project VideoVault.xcodeproj \
  -scheme VideoVault \
  -configuration Release \
  -archivePath /tmp/VideoVault.xcarchive \
  archive

ditto -c -k --sequesterRsrc --keepParent \
  /tmp/VideoVault.xcarchive/Products/Applications/VideoVault.app \
  VideoVault-macOS.zip
```

> **Note:** The app is not notarized. Distribute to other Macs as a zip; recipients will need to right-click → Open on first launch. Notarization requires an Apple Developer account.

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
