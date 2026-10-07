<p align="center">
  <img src="VideoVault/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="VideoVault">
</p>

<h1 align="center">VideoVault</h1>

<p align="center">
  Native macOS and Windows apps for downloading video and audio with yt-dlp.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Windows-11%20x64%20%2B%20ARM64-blue" alt="Windows 11 x64 and ARM64 preview">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-native-purple" alt="SwiftUI">
  <img src="https://img.shields.io/github/v/release/eMacTh3Creator/VideoVault?color=green" alt="Latest Release">
  <img src="https://img.shields.io/github/license/eMacTh3Creator/VideoVault" alt="License">
</p>

---

## Overview

VideoVault is a clean, native macOS download manager built on top of [yt-dlp](https://github.com/yt-dlp/yt-dlp). Paste in one URL or hundreds — VideoVault handles fetching, queuing, and downloading in the background while you get on with your day.

The native C# / .NET / WPF Windows implementation is now available as an unsigned development preview alongside the Mac release. [Choose a platform on the website](https://emacth3creator.github.io/VideoVault/#downloads), or open the [v1.4 release](https://github.com/eMacTh3Creator/VideoVault/releases/tag/v1.4).

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

### Windows Development Preview

| Computer | Installer | Portable |
|---|---|---|
| Intel / AMD x64 | [Windows x64 Setup](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-x64-Setup.exe) | [x64 ZIP](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-x64-Portable.zip) |
| Snapdragon / Windows ARM64 / Parallels on Apple Silicon | [Windows ARM64 Setup](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-arm64-Setup.exe) | [ARM64 ZIP](https://github.com/eMacTh3Creator/VideoVault/releases/download/v1.4/VideoVault-win-arm64-Portable.zip) |

Run the matching installer, or extract the portable ZIP into its own folder and run `VideoVault.Windows.exe`. The .NET runtime is included. First-run tool installation needs internet access. These Windows 11 builds are unsigned and may trigger SmartScreen; no Windows security protections are disabled.

Windows v1.4.0 includes the corrected Settings display and 42 passing regression/local-media checks in Windows 11 ARM64. Native x64 hardware and installed old-to-new automatic-update validation remain pending. Portable copies do not install application updates. See the [Windows guide](VideoVault-Windows/README.md) and [verification results](VideoVault-Windows/TEST_RESULTS.md).

The remaining usage and settings documentation below describes the Mac app; Windows-specific controls and build instructions are in the Windows guide.

### Option 1 — Download the installer (recommended)

1. Download **[VideoVault-v1.4-macOS.dmg](https://github.com/eMacTh3Creator/VideoVault/raw/refs/heads/main/Releases/VideoVault-v1.4-macOS.dmg)**.
2. Open the disk image and drag **VideoVault** to **Applications**.
3. Eject the disk image, then open **VideoVault** from Applications.
4. Use the built-in buttons to install yt-dlp and ffmpeg during setup.

The app checks for signed updates from its first launch and can download and install future published releases. Users never need a script, signing key, or Keychain setup. Automatic updates can be changed in Settings. Updates wait for active downloads before relaunching.

**Upgrading from 1.3.x:** install 1.4 manually once to join the new signed update channel. Your existing settings and download queue use the same app identifier. Subsequent releases use the updater. The old channel remains available for copies using the original publisher key.

Universal Intel and Apple Silicon build for macOS 13+. The app is ad-hoc signed, not Apple-notarized; first launch may require approval under **System Settings → Privacy & Security**.

### First-start download tool setup

On Intel Macs, choose **Download & Install yt-dlp** and **Download & Install ffmpeg**, then **Re-check Tools**. The **Tool Setup…** guide explains these steps. Homebrew's current macOS installer rejects Intel processors; VideoVault's built-in installers do not require Homebrew. Existing Intel Homebrew installations may still be detected.

On Apple Silicon, **Homebrew Setup…** provides the official installer command, **Open Terminal**, and shell setup instructions. Follow the installer's **Next steps**, then install yt-dlp and ffmpeg. Homebrew remains optional. See [Homebrew's current installation requirements](https://docs.brew.sh/Installation).

VideoVault refreshes tool detection when you return to the app. Installer failures display their error beside the install button.

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

Metadata lookup has a timeout and is optional for downloading. Technical failures try alternate format selectors and the independent fallback when supported. An unusual-extension error from thumbnail processing retries once without the optional image, with yt-dlp's extension validation still enabled. It is not mislabeled as a website refusal.

**Force Retry** is available in failed/cancelled download details and the right-click menu. It skips optional thumbnail/metadata processing and enables supported backup downloaders for that job, without changing your global settings or bypassing duplicate protection. A normal Retry restores your normal settings. Streamlink supports only a subset of sites, not every yt-dlp website. Website refusals, removed/private media, DRM, geo-blocks, and account restrictions remain errors; Force Retry does not bypass them or disable unsafe-file validation.

---

## Supported Sites

VideoVault supports [all sites that yt-dlp supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md) — over 1000, including:

YouTube · Vimeo · Twitter/X · TikTok · Instagram · Reddit · Twitch · Dailymotion · SoundCloud · Bandcamp · BBC iPlayer · CNN · NBC · ABC · ESPN · Crunchyroll · Nebula · Rumble · Odysee · and many more.

---

## Building and publishing a release (maintainers only)

Customers only install the DMG. Signing and publishing happen on a maintainer's Mac.

The current release channel is `docs/appcast-v2.xml`, signed by the `videovault-v2` key in the publisher's login Keychain. Only its public key is embedded in the app. Keep the private key backed up securely when changing publishing Macs. Never commit it or distribute it to users. The original M5 key controls the legacy `docs/appcast.xml` feed only.

Update `CFBundleShortVersionString`, increment `CFBundleVersion`, update the release notes, then run:

```bash
VIDEOVAULT_TEST_ROOT=/tmp/VideoVault-tests swift test
bash script/publish_release.sh
```

The publisher builds both architectures, creates the drag-to-Applications DMG, verifies the bundle and disk image, signs and verifies the update feed, then commits the versioned DMG and matching feed together. It refuses missing/mismatched keys, duplicate release versions, and uncommitted source changes. `git` push access is required on the publishing Mac. The GitHub release workflow verifies the signed DMG using only the public key, then automatically attaches it to a versioned GitHub Release. No private signing key is stored in GitHub Actions.

`VIDEOVAULT_PACKAGES` selects the Xcode package cache; `VIDEOVAULT_BUILD` selects the build folder. `VIDEOVAULT_SIGNING_ACCOUNT` defaults to `videovault-v2`. Packaging uses `dmgbuild` 1.6.5 in an isolated Python environment. `VIDEOVAULT_DMGBUILD` can select an existing installation. For an Apple Developer ID release, set `VIDEOVAULT_SIGN_IDENTITY` and add Apple's notarization before distribution; current releases are ad-hoc signed.

To package without publishing, use `bash script/package_release.sh /tmp/VideoVault-release-artifacts`. To exercise update installation without touching `/Applications`, use `script/prepare_update_test.sh` with a signed app and a new temporary directory, then run Sparkle's test CLI against the isolated copy.

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
  Built with SwiftUI · Powered by <a href="https://github.com/yt-dlp/yt-dlp">yt-dlp</a> · Updates by <a href="https://sparkle-project.org/">Sparkle</a>
</p>

Sparkle and its bundled components retain their upstream notices in [Releases/Sparkle-LICENSE.txt](Releases/Sparkle-LICENSE.txt), also included in the release zip.
