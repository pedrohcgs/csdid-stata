#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import math
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
dgp = (root / "tools/bench/field/dgp.do").read_text()
expression = re.search(r"local first_g = (.+)", dgp).group(1)
def first(t, expression=expression):
    return eval(expression.replace("`t'", str(t)), {"__builtins__": {}}, {"floor": math.floor, "max": max})

# The promised one-pre-period comparison requires the generated treated group
# to survive mech.do's g==2|g==0 selection. The earlier expression fails here.
assert first(2) == 2, "two-period diagnostic deletes every treated unit"
assert all(first(t) == math.floor(t / 3) + 1 for t in range(3, 101))
old = "floor(`t' / 3) + 1"
assert first(2, old) != 2, "shape witness no longer distinguishes the defect"

eq = (root / "tools/bench/field/eqgate.do").read_text()
def controlled(text):
    return text.count("set seed 7654321") == 2 and len(re.findall(r"set seed 7654321\s+set sortseed 7654321", text)) == 2
assert controlled(eq), "both literal-command paths must control their sort order"
assert not controlled(eq.replace("set sortseed 7654321", "", 1))
mech = (root / "tools/bench/field/mech.do").read_text()
assert 'local out = "`out\'  `pkg\'="' in mech
assert "assert colsof(J) == 1" in mech and "quietly estat event, window(0 0)" in mech
print("Website diagnostic shape and control checks pass (old-shape and missing-sort-control witnesses fail).")
PY
