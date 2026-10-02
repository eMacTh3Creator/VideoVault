#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time
from urllib.parse import urlparse

args = sys.argv[1:]
identity = urlparse(args[-1]).path.rsplit("/", 1)[-1]
if "--dump-single-json" in args:
    time.sleep(0.1)
    print(json.dumps({"title": identity, "id": identity, "extractor_key": "Fixture"}))
else:
    directory = Path(args[args.index("-P") + 1])
    directory.mkdir(parents=True, exist_ok=True)
    (directory / (identity + ".started")).write_text(str(os.getpid()))
    for tick in range(int(os.environ.get("VIDEOVAULT_FIXTURE_TICKS", "60"))):
        sys.stdout.write(("__VV_PROGRESS__" + str(tick) + "%\n") * 2000)
        sys.stdout.flush()
        time.sleep(0.04)
    file = directory / (identity + ".mp4")
    file.write_bytes((identity * 100).encode())
    print("__VV_RESULT__" + json.dumps({"filepath": str(file), "id": identity, "extractor_key": "Fixture"}), flush=True)
