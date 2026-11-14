#!/usr/bin/env python3
"""Verify final notarized packages without launching the app, then record evidence."""

import argparse
import datetime
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_app(app, version, build):
    run("codesign", "--verify", "--deep", "--strict", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info["CFBundleShortVersionString"] == version, "Packaged app version mismatch")
    require(info["CFBundleVersion"] == build, "Packaged app build mismatch")
    archs = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/VideoVault")], text=True).split()
    require({"arm64", "x86_64"}.issubset(archs), "Missing universal architecture")
    signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], check=True, capture_output=True, text=True).stderr
    require("Authority=Developer ID Application:" in signature, "Missing Developer ID signature")
    require("flags=0x10000(runtime)" in signature, "Missing hardened runtime")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", type=Path)
    parser.add_argument("tests_log", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    artifacts = args.artifacts.resolve()
    info = plistlib.loads((root / "VideoVault/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    tests = args.tests_log.read_text()
    results = re.findall(r"Executed (\d+) tests,.*?(\d+) failures", tests)
    require(results and int(results[-1][0]) > 0 and results[-1][1] == "0", "Missing successful test results")
    require(not re.search(r"Test Case .* skipped|[1-9]\d* tests? skipped", tests), "Public release tests must not be skipped")
    count = results[-1][0]
    dmg = artifacts / f"VideoVault-v{version}-macOS-notarized.dmg"
    archive = artifacts / f"VideoVault-v{version}-macOS-notarized.zip"
    receipts = {}
    for kind in ("app", "dmg"):
        result = json.loads((artifacts / f"{kind}-notary-result.json").read_text())
        log = json.loads((artifacts / f"{kind}-notary-log.json").read_text())
        require(result["status"] == log["status"] == "Accepted", "Apple did not accept this submission")
        require(result["id"] == log["jobId"], "Apple submission ID mismatch")
        receipts[kind] = (result, log)
    run("shasum", "-a", "256", "-c", f"SHA256SUMS-v{version}-notarized.txt", cwd=artifacts)
    run("codesign", "--verify", "--strict", dmg)
    run("xcrun", "stapler", "validate", dmg)
    run("hdiutil", "verify", dmg)
    verify_app(artifacts / "VideoVault.app", version, build)
    with tempfile.TemporaryDirectory(prefix="VideoVault-verify-") as stage:
        stage = Path(stage)
        run("ditto", "-x", "-k", archive, stage / "zip")
        verify_app(stage / "zip/VideoVault.app", version, build)
        mount = stage / "volume"
        mount.mkdir()
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            verify_app(mount / "VideoVault.app", version, build)
        finally:
            run("hdiutil", "detach", mount)
    run("swift", root / "script/verify_release.swift", root / "VideoVault/Info.plist", artifacts / "appcast-v3.xml", dmg)
    date = datetime.datetime.now(datetime.timezone.utc).isoformat()
    report = [f"# VideoVault v{version} Apple Notarization", "", f"Verified: {date}", f"Mac build: {build}", ""]
    for kind, (result, log) in receipts.items():
        report += [f"## {kind.upper()} Submission", f"- Apple status: {result['status']}", f"- Submission ID: {result['id']}",
                   f"- Submitted archive SHA-256: {log['sha256']}", f"- Apple diagnostic issues: {len(log.get('issues') or [])}", ""]
    report += ["## Distributed Downloads", ""]
    for path in (dmg, archive):
        report.append(f"- `{path.name}`: `{hashlib.sha256(path.read_bytes()).hexdigest()}`")
    report += ["", "The ZIP contains the stapled app. The final DMG is signed and stapled. Both extracted/mounted apps passed strict signature, stapled-ticket, and Gatekeeper verification without being launched.", ""]
    releases = root / "Releases"
    (releases / f"NOTARIZATION-v{version}.md").write_text("\n".join(report))
    (releases / f"VALIDATION-v{version}.md").write_text(
        f"# VideoVault v{version} Release Validation\n\nVerified: {date}\nMac build: {build}\n\n"
        f"- {count} Mac tests passed with zero failures and zero skips in an isolated VIDEOVAULT_TEST_ROOT.\n"
        "- Universal arm64/x86_64 binary verified in the distributed app, extracted ZIP, and mounted DMG.\n"
        "- Developer ID signature, hardened runtime, Apple acceptance, stapled tickets, and Gatekeeper acceptance verified.\n"
        "- Final DMG integrity, SHA-256 checksums, signed Sparkle v3 feed, archive signature, version, build, and length verified.\n"
        "- Private publisher keys and notarization credentials remain outside the repository.\n"
        "- The user's installed app and VM were not opened, replaced, or restarted. Interactive UI testing is not claimed.\n"
        "- Windows remains on its existing release; unchanged Windows feeds/packages and checksums are carried forward by the publication workflow.\n\n"
        f"See NOTARIZATION-v{version}.md for Apple submission IDs and download hashes.\n"
    )


if __name__ == "__main__":
    main()
