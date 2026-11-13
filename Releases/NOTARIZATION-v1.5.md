# VideoVault v1.5 Mac Notarization

Date: 2026-11-13. App version 1.5, build 9; universal Intel and Apple Silicon.

- App submission: `2736d3ed-e118-4076-852c-5dd212569171`. Apple status: **Accepted**, ready for distribution, no warnings or errors.
- Disk-image submission: `dfdf7380-33d2-4861-85fb-e01974d7a9d1`. Apple status: **Accepted**, ready for distribution, no warnings or errors.
- App and disk image are signed with Developer ID for team `TS7Y9PMXV4`. App hardened runtime and existing code signatures were preserved.
- Apple submission logs were checked against the exact submitted archive SHA-256 digests.
- App and DMG tickets were stapled and validated. Gatekeeper reported `accepted` and `source=Notarized Developer ID` for the app and DMG.
- The app extracted from the final ZIP retained its ticket and passed Gatekeeper. The app inside the final mounted DMG also passed ticket and signature validation.
- New downloads: `VideoVault-v1.5-macOS-notarized.dmg` and `VideoVault-v1.5-macOS-notarized.zip`. Matching digests: `SHA256SUMS-v1.5-notarized.txt`.
- The v3 update feed was re-signed for the final stapled DMG. Original release archives and their checksums remain unchanged so cached older signed feeds still work. Windows release files are unchanged.
- The app was not opened or run. Work used background signing/notarization tools, static validation, and read-only disk-image inspection. No installed copy or VM was controlled or restarted.
- Notarization credentials are stored in the local Keychain profile `VideoVaultNotary`; no password, API private key, or signing private key is in the repository or release assets.
