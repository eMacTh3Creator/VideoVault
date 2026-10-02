#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import time

tool = Path(sys.argv[0])
config = json.loads((tool.parent / "config.json").read_text())
args = sys.argv[1:]
with (tool.parent / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": tool.name, "args": args}) + "\n")

unsafe = "ERROR: The extracted extension ('v1692889884') is unusual and will be skipped for safety reasons. If you believe this is an error, please report this issue on https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropriate issue template. Confirm you are on the latest version using yt-dlp -U"
mode = config["mode"]

if tool.name == "yt-dlp":
    if "--dump-single-json" in args:
        if mode == "metadata-unsafe":
            print(unsafe, file=sys.stderr)
            sys.exit(1)
        print(json.dumps({"title": "Recovery Fixture", "id": "recovery", "extractor_key": "Fixture"}))
        sys.exit(0)
    if mode == "real-thumbnail":
        actual = config["real_ytdlp"]
        os.execv(actual, [actual, "--load-info-json", config["info_file"]] + args[:args.index("--")])
    if mode in ("restricted", "mixed-restriction"):
        if mode == "mixed-restriction":
            print(unsafe, file=sys.stderr)
        print("ERROR: This video is DRM-protected", file=sys.stderr)
        sys.exit(1)
    if mode == "cancel":
        (tool.parent / "started").write_text(str(os.getpid()))
        time.sleep(30)
    if mode == "pipe-open":
        subprocess.Popen(["/bin/sleep", "2"])
        sys.exit(1)
    if mode == "invalid-output":
        sys.exit(0)
    if (mode == "thumbnail" and "--embed-thumbnail" in args) or mode in ("unsafe", "metadata-unsafe"):
        print(unsafe, file=sys.stderr)
        sys.exit(1)
    if mode == "force" and "--embed-metadata" in args:
        print("ERROR: optional metadata processing failed", file=sys.stderr)
        sys.exit(1)
    file = Path(args[args.index("-P") + 1]) / "recovered.mp4"
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(b"fixture media")
    print("__VV_RESULT__" + json.dumps({"filepath": str(file), "id": "recovery", "extractor_key": "Fixture"}))
elif tool.name == "streamlink":
    if "--can-handle-url" in args:
        sys.exit(1 if config.get("unsupported") else 0)
    Path(args[args.index("--output") + 1]).write_bytes(b"fixture stream")
elif tool.name == "ffmpeg":
    Path(args[-1]).write_bytes(b"fixture converted media")
