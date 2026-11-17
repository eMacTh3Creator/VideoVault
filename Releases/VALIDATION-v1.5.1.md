# VideoVault v1.5.1 Release Validation

Verified: 2026-11-17T23:10:35.623826+00:00
Mac build: 10

- 39 Mac tests passed with zero failures and zero skips in an isolated VIDEOVAULT_TEST_ROOT.
- Universal arm64/x86_64 binary verified in the distributed app, extracted ZIP, and mounted DMG.
- Developer ID signature, hardened runtime, Apple acceptance, stapled tickets, and Gatekeeper acceptance verified.
- Final DMG integrity, SHA-256 checksums, signed Sparkle v3 feed, archive signature, version, build, and length verified.
- Private publisher keys and notarization credentials remain outside the repository.
- The user's installed app and VM were not opened, replaced, or restarted. Interactive UI testing is not claimed.
- Windows remains on its existing release; unchanged Windows feeds/packages and checksums are carried forward by the publication workflow.

See NOTARIZATION-v1.5.1.md for Apple submission IDs and download hashes.
