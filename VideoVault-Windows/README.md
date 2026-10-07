# VideoVault for Windows

Native C# / .NET 10 / WPF implementation of VideoVault. Windows 11-style layout, native dialogs, Explorer integration, and a live system-tray menu. Supports self-contained x64 and ARM64 releases without requiring users to install .NET.

## Open in Visual Studio

Open `VideoVault.Windows.sln` with Visual Studio 2026 and the **.NET desktop development** workload. Install a stable .NET 10 SDK. `global.json` selects .NET 10 even when a .NET 11 preview is also installed.

For reliable builds in a VM, keep the build checkout on the Windows disk, such as `C:\Dev\VideoVault-Windows`, rather than compiling across a Mac shared-folder network path.

## Features

- Independent asynchronous download workers, configurable concurrency from 1 to 8, per-job cancellation, queue pause/resume, retry, and cancellation on shutdown.
- Best video, best audio, MP3, 720p, 1080p, 1440p, and 4K. Unknown-resolution direct media is probed and downscaled if needed; selecting 720p never silently switches to unrestricted best quality.
- Bounded metadata/process timeouts, bounded output logs, coalesced UI progress every 200 ms, and asynchronous atomic queue/settings persistence.
- Automatic yt-dlp checks on launch with SHA-256-verified official downloads, per-version installation paths, and an executable version check. Existing workers keep their original tool version.
- Verified first-run installation/repair of yt-dlp, FFmpeg/ffprobe, Deno, and Streamlink. Tools live under `%LOCALAPPDATA%\VideoVault\tools`. Streamlink's upstream Windows distribution is currently x64 and uses Windows emulation on ARM64; the app, yt-dlp, and FFmpeg have native ARM64 builds.
- Duplicate skips using a destination-side URL/media-ID index, destination filename checks, and SHA-256 content coalescing. The duplicate finder skips reparse points and verifies content before moving a selected redundant copy to the Recycle Bin.
- Automatic thumbnail-free recovery for the unusual-extension error. Force Retry skips optional metadata and thumbnail work and enables the independent backup for that job.
- Streamlink for supported pages and FFmpeg for direct media. Recovery is not universal and never bypasses DRM, login, or website access restrictions.
- Home navigation preserves the queue. Search, status filters, drag-and-drop URLs, and native folder selection.
- Tray counts for active, queued, and failed jobs; quick-paste best video/audio without opening the window; pause/resume/retry/quit actions; completion notifications.
- Close-to-tray, optional Windows sign-in startup, and browser-cookie selection. Settings Cancel leaves the active configuration unchanged.
- Velopack app-update integration: architecture-specific channels, background checks and download, and user-confirmed restart. Updating stops processes and saves the queue first. Development builds report that installation is required rather than pretending that update installation succeeded.

## Build and Test

Run in PowerShell from this directory:

```powershell
dotnet build VideoVault.Windows.sln
dotnet run --project VideoVault.Windows.Tests -c Release
dotnet run --project VideoVault.Windows.Tests -c Release -- --install-tools
dotnet run --project VideoVault.Windows.Tests -c Release -- --integration
```

Tests use isolated temporary queue/settings directories. Synthetic subprocess tests cover cancellation, recovery, restrictions, concurrency, progress flooding, duplicates, persistence, and native UI controls. Integration tests generate a local test clip, download it with actual yt-dlp/FFmpeg, and convert it to MP3. No private or adult-content example URLs are needed.

`Ctrl+N` adds URLs, `Ctrl+V` quick-pastes the default format when not editing a text field, and `Ctrl+H` returns Home.

## Package

```powershell
./scripts/build-release.ps1 -Runtime win-x64 -Version 1.4.0
./scripts/build-release.ps1 -Runtime win-arm64 -Version 1.4.0
```

Packages appear in `artifacts\win-x64` and `artifacts\win-arm64`, with installers, portable archives, update packages/feeds, and SHA-256 checksums. The app runtime is self-contained; downloader tools are installed with checksum verification on first launch. Internet access is needed for tool setup and updates.

For GitHub releases, upload **all** architecture-specific Velopack `.exe`, `.zip`, `.nupkg`, and feed `.json` files; installers alone are insufficient for automatic updates. Keep the `win-x64` and `win-arm64` channels unchanged between versions. Validate an installed old-to-new update before marking a release production-ready.

Unsigned installers can trigger Windows SmartScreen. Production Authenticode signing requires a Windows code-signing certificate; this project does not disable Windows security checks or claim unsigned builds are trusted/signed.

## Verification Status

The implementation has been built and tested in Windows 11 ARM64 under Parallels with 42 passing regression/local-media integration checks. GitHub validation also passed on a Windows Server 2025 x64 runner, including the 42-check integration suite and packaging for both architectures. The unsigned development previews are included in GitHub release v1.4. Physical x64 PC testing and installed old-to-new automatic-update validation remain production release gates.

Application source is covered by the repository's root `LICENSE`. Download dependencies retain their upstream licenses and are fetched separately from official releases. FFmpeg GPL build license/source information is preserved in its extracted dependency directory.
