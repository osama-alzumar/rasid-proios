#!/usr/bin/env bash
# Prints the UDID of the newest available simulator whose name matches $1
# (e.g. "iPhone.*Pro Max", "iPad Pro.*13"), so CI does not hard-code a model
# that a future Xcode image no longer ships.
set -euo pipefail
pattern="$1"
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
pattern = re.compile(sys.argv[1])
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(p) for p in re.findall(r"\d+", runtime.split("iOS")[-1]))
    for d in items:
        if pattern.search(d["name"]):
            key = (version, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"], d["name"])
if not best:
    sys.exit("no simulator matches " + sys.argv[1])
print(best[1])
print(f"picked {best[2]} {best[0][0]}", file=sys.stderr)
' "$pattern"
