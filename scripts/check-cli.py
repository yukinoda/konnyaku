"""Checks konnyaku.py's pure helpers. Needs only the standard library:
konnyaku.py imports its model packages inside main()."""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# A cached .pyc can outlive an edit made within the same second. Look for
# caches in an empty folder and write none, so konnyaku.py always compiles
# from source.
sys.dont_write_bytecode = True
with tempfile.TemporaryDirectory() as empty_cache:
    sys.pycache_prefix = empty_cache
    import konnyaku

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
