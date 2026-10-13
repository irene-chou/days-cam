#!/usr/bin/env python3
"""Print the `-only-testing:` arguments for one CI shard of the UI tests.

Usage: ui-test-shard.py <shard index, 0-based> <shard count>

Classes are found by scanning DaysCamUITests/ for XCTestCase subclasses and
packed into shards by their last measured duration (scripts/ui-test-timings.json),
longest first onto the lightest shard. A class missing from the timings file
(e.g. newly added) counts as the median, so it still lands somewhere.
Refresh the timings file when shards drift apart (see the Swift workflow).
"""

import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLASS_PATTERN = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b", re.MULTILINE)


def main() -> None:
    index, count = int(sys.argv[1]), int(sys.argv[2])
    classes = sorted(
        {name for path in (ROOT / "DaysCamUITests").glob("*.swift")
         for name in CLASS_PATTERN.findall(path.read_text(encoding="utf-8"))}
    )
    if not classes:
        sys.exit("No UI test classes found")
    timings = json.loads((ROOT / "scripts" / "ui-test-timings.json").read_text(encoding="utf-8"))
    fallback = statistics.median(timings.values()) if timings else 1

    loads = [0.0] * count
    shards: list[list[str]] = [[] for _ in range(count)]
    for name in sorted(classes, key=lambda c: (-timings.get(c, fallback), c)):
        lightest = loads.index(min(loads))
        shards[lightest].append(name)
        loads[lightest] += timings.get(name, fallback)

    print(f"Shard {index + 1}/{count}: ~{loads[index]:.0f}s, {len(shards[index])} classes", file=sys.stderr)
    print(" ".join(f"-only-testing:DaysCamUITests/{name}" for name in shards[index]))


if __name__ == "__main__":
    main()
