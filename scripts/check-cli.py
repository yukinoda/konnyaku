"""Checks konnyaku.py's pure helpers. Needs only the standard library:
konnyaku.py imports its model packages inside main()."""

import json
import re
import runpy
import types
from pathlib import Path

# Run from source, not imported: a cached .pyc can outlive an edit made
# within the same second, and runpy reads and writes no cache.
script = Path(__file__).resolve().parent.parent / "konnyaku.py"
konnyaku = types.SimpleNamespace(**runpy.run_path(str(script), run_name="konnyaku"))

# The app's testAutoTarget runs the same cases against the Swift rule.
cases_path = script.parent / "Tests" / "auto-target-cases.json"
cases = json.loads(cases_path.read_text(encoding="utf-8"))
assert cases
for case in cases:
    actual = konnyaku.pick_target(case["text"])
    label = case.get("note", case["text"])
    assert actual == case["target"], (label, actual)

# The app keeps its own copy of the ranges; both must list the same ones.
swift_path = script.parent / "Sources" / "Konnyaku" / "PFML3.swift"
swift_source = swift_path.read_text(encoding="utf-8")
table_start = swift_source.index("static let japaneseRanges")
table_end = swift_source.index("\n    ]", table_start)
swift_table = swift_source[table_start:table_end]
swift_bounds = re.findall(r"0x([0-9A-F]+)\.\.\.0x([0-9A-F]+)", swift_table)
swift_ranges = [(int(start, 16), int(end, 16)) for start, end in swift_bounds]
assert swift_ranges == konnyaku.JAPANESE_RANGES, swift_ranges

glossary = konnyaku.parse_glossary(["Hello=Bonjour", "a=b=c"])
assert glossary == [
    {"source": "Hello", "target": "Bonjour"},
    {"source": "a", "target": "b=c"},
]

bad_entries = {
    "missing-target": "an entry without '=' must exit",
    "empty-target=": "an empty target must exit",
    "=Bonjour": "an empty source must exit",
    "=": "an entry with no source and no target must exit",
    " =Bonjour": "a whitespace-only source must exit",
    "Hello= ": "a whitespace-only target must exit",
}
for entry, message in bad_entries.items():
    try:
        konnyaku.parse_glossary([entry])
    except SystemExit as error:
        assert "source=target" in str(error.code)
        assert repr(entry) in str(error.code)
    else:
        raise AssertionError(message)

print("konnyaku.py helpers OK")
