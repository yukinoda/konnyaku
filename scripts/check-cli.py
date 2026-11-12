"""Checks konnyaku.py's pure helpers. Needs only the standard library:
konnyaku.py imports its model packages inside main()."""

import types
from pathlib import Path

# Compiled from the source text, not imported: a cached .pyc can outlive an
# edit made within the same second, and this reads or writes no cache.
path = Path(__file__).resolve().parent.parent / "konnyaku.py"
code = compile(path.read_text(encoding="utf-8"), str(path), "exec")
konnyaku = types.ModuleType("konnyaku")
exec(code, konnyaku.__dict__)

assert konnyaku.pick_target("会議は来週です。") == "en"
assert konnyaku.pick_target("ひらがな") == "en"
assert konnyaku.pick_target("カタカナ") == "en"
assert konnyaku.pick_target("漢字") == "en"
assert konnyaku.pick_target("This system is convenient.") == "ja"

glossary = konnyaku.parse_glossary(["Hello=Bonjour", "a=b=c"])
assert glossary == [
    {"source": "Hello", "target": "Bonjour"},
    {"source": "a", "target": "b=c"},
]

try:
    konnyaku.parse_glossary(["missing-target"])
except SystemExit as error:
    assert "source=target" in str(error.code)
else:
    raise AssertionError("an entry without '=' must exit")

print("konnyaku.py helpers OK")
