# VideoVault Release Requirements

- Feature and fix delivery includes a new GitHub release and the GitHub Pages website update, not just a local build.
- Always Developer ID-sign and Apple-notarize public Mac releases. Staple and verify both app and DMG tickets; verify the app extracted from the ZIP and the app mounted from the DMG. Never publish an ad-hoc or unsigned Mac installer.
- Increment the Mac version and build number. Publish the app ZIP, DMG, checksums, release notes, validation evidence, and signed Sparkle v3 feed. Include the updated app bundle under Releases in git.
- Use the existing VideoVaultNotary Keychain profile and videovault-v3 Sparkle signing account. Never print, commit, or upload private keys or credentials.
- Keep existing downloads and older signed feeds intact. Verify the public release assets, signed feed, and deployed website, not only the upload commands.
- For Mac-only updates, retain the current Windows installers and updater assets without claiming a new Windows build. The GitHub latest release must include both Windows architecture feeds and their referenced packages.
- Run isolated tests using VIDEOVAULT_TEST_ROOT and build universal arm64/x86_64 binaries. State any remaining interactive or hardware validation gaps.
- Work in the background. Do not open, replace, restart, or control the user's running VideoVault app or VM unless explicitly asked.
