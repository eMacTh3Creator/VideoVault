# VideoVault v1.5 Release Validation

Date: 2026-11-13.

- Mac: 33 tests passed with no skips, including official dependency installation, actual local video/audio downloads, screenshot-diagnostic recovery, multiple forced retries, attempt limits, opt-outs, restriction handling, duplicate protection, and cancellation.
- The final recovery suite was rerun after the missing-backup classification fix: 10 recovery tests passed. Hosted Mac validation also passed.
- Universal Mac binary contains arm64 and x86_64. Developer ID signature, hardened runtime, nested Sparkle signatures, disk-image integrity, and DMG/ZIP checksums passed. Apple subsequently accepted both the app and DMG; the new -notarized downloads have validated stapled tickets and Gatekeeper acceptance. See NOTARIZATION-v1.5.md.
- New appcast-v3 feed and DMG signatures were verified with the public key embedded in the app. The private key was backed up outside Git with owner-only directory/file permissions; the backup public key was independently checked. Older feeds were not modified.
- Existing Mac users must manually install v1.5 once because the previous publisher key could not be recovered. Future updates use the replacement channel.
- Windows: 56 regression checks and 62 regression/integration checks passed on the hosted x64 runner. Self-contained x64 and ARM64 installers, portable archives, and Velopack feeds/packages were built successfully. These remain unsigned previews.
- Windows workflow: https://github.com/eMacTh3Creator/VideoVault/actions/runs/43520035851
- Mac workflow: https://github.com/eMacTh3Creator/VideoVault/actions/runs/43520035996
- Physical Windows PC testing and installed Windows update migration remain separate validation gates. No claim is made that every external website or DRM-protected source is downloadable.
- No computer-control tooling was used. The installed VideoVault application and the user's VM were not opened, controlled, or restarted; work used isolated background builds/tests and hosted Windows CI.
