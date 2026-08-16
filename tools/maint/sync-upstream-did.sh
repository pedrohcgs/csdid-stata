#!/usr/bin/env bash
# Keep csdid aligned with the reference implementation as it releases.
#
# The problem this solves is a slow one. `did` releases, nobody notices, and the
# oracles in this repository quietly become a record of what an old version did.
# Every parity claim stays green while measuring the wrong thing. That is not
# hypothetical: a local install once reported version 2.5.1 while running 2.5.0
# arithmetic, and the gate at the time checked packageVersion() rather than the
# code, so it passed and produced a convincing false divergence.
#
#   sync-upstream-did.sh --check     read-only. Is the installed reference behind
#                                    upstream, and has the pinned test inventory
#                                    drifted? Changes nothing.
#
#   sync-upstream-did.sh --upgrade   reinstall from upstream, regenerate every
#                                    oracle, and report exactly which fixtures
#                                    moved and which upstream tests are new.
#
# --upgrade does NOT commit anything and does NOT decide whether a moved fixture
# is acceptable. That is the reviewer's job: a fixture that moves is either a
# real upstream behaviour change to mirror, or a divergence to record and
# justify. A regeneration that changes nothing is the expected outcome.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MODE="${1:---check}"
UPSTREAM_URL="https://github.com/bcallaway11/did.git"
CHECKOUT="${CSDID_DID_UPSTREAM:-}"
INVENTORY="inst/spec/upstream-did-tests.csv"

have() { command -v "$1" >/dev/null 2>&1; }
have Rscript || { echo "Rscript is not on PATH" >&2; exit 1; }

# ---------------------------------------------------------------- installed
installed_version() { Rscript -e 'cat(as.character(packageVersion("did")))' 2>/dev/null; }

# A version string is not proof of content: see check-r-oracles.sh.
installed_fingerprint() {
  Rscript -e '
    src <- deparse(did:::compute.att_gt)
    cat(substr(digest::digest(paste(src, collapse = "\n"), algo = "sha256"), 1, 12))
  ' 2>/dev/null || Rscript -e '
    src <- paste(deparse(did:::compute.att_gt), collapse = "\n")
    cat(substr(tools::md5sum(textConnection(src)), 1, 12))
  ' 2>/dev/null || echo "unavailable"
}

# ---------------------------------------------------------------- upstream
resolve_checkout() {
  # -e, not -d: in a linked git worktree .git is a FILE holding a gitdir
  # pointer, so -d rejected every worktree. A rejected checkout fell through to
  # the clone below and the run then compared the pinned inventory against
  # upstream's DEVELOPMENT head while still printing "upstream", which reads as
  # drift in the pin rather than what it was -- a different oracle. Whoever
  # supplies a pinned checkout must get that checkout or a loud failure.
  if [ -n "$CHECKOUT" ] && [ -e "$CHECKOUT/.git" ]; then
    # A detached HEAD is the normal shape here (a release tag), where pull is a
    # no-op; on a branch this keeps a supplied checkout current.
    git -C "$CHECKOUT" fetch --quiet origin 2>/dev/null || true
    git -C "$CHECKOUT" pull --quiet --ff-only 2>/dev/null || true
    echo "$CHECKOUT"; return
  fi
  if [ -n "$CHECKOUT" ]; then
    echo "CSDID_DID_UPSTREAM=$CHECKOUT is not a git checkout" >&2
    return 1
  fi
  echo "   note: no pinned checkout supplied; cloning $UPSTREAM_URL at its" >&2
  echo "         development head, which is NOT the released parity target" >&2
  local tmp; tmp="$(mktemp -d)"
  git clone --quiet --depth 50 "$UPSTREAM_URL" "$tmp/did" || return 1
  echo "$tmp/did"
}

echo "== reference implementation =="
INST_V="$(installed_version)"
echo "   installed        : ${INST_V:-not installed}"

UP="$(resolve_checkout)" || { echo "could not obtain upstream" >&2; exit 1; }
UP_V="$(sed -n 's/^Version:[[:space:]]*//p' "$UP/DESCRIPTION" | head -1)"
UP_SHA="$(git -C "$UP" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "   upstream         : $UP_V ($UP_SHA)"
echo "   pinned inventory : $(head -1 "$INVENTORY" | sed 's/^# *//')"

BEHIND=0
[ "$INST_V" != "$UP_V" ] && BEHIND=1

echo
echo "== pinned test inventory vs upstream =="
python3 tools/spec/check-upstream-coverage.py --upstream "$UP" || true

if [ "$MODE" = "--check" ]; then
  echo
  if [ "$BEHIND" = "1" ]; then
    echo "ACTION NEEDED: installed did ($INST_V) differs from upstream ($UP_V)."
    echo "Run: bash tools/maint/sync-upstream-did.sh --upgrade"
    exit 1
  fi
  echo "installed reference matches upstream; inventory checked above."
  exit 0
fi

if [ "$MODE" != "--upgrade" ]; then
  echo "usage: sync-upstream-did.sh [--check|--upgrade]" >&2
  exit 2
fi

# ---------------------------------------------------------------- upgrade
echo
echo "== reinstalling did from upstream =="
BEFORE_FP="$(installed_fingerprint)"
Rscript -e 'if (!requireNamespace("remotes", quietly=TRUE)) install.packages("remotes", repos="https://cloud.r-project.org")
            remotes::install_github("bcallaway11/did", force = TRUE, upgrade = "never")' \
  || { echo "reinstall failed" >&2; exit 1; }
AFTER_V="$(installed_version)"
AFTER_FP="$(installed_fingerprint)"
echo "   version    : $INST_V -> $AFTER_V"
echo "   fingerprint: $BEFORE_FP -> $AFTER_FP"
if [ "$BEFORE_FP" = "$AFTER_FP" ] && [ "$INST_V" != "$AFTER_V" ]; then
  echo "   WARNING: the version changed but compute.att_gt did not. Verify the"
  echo "   install actually replaced the old build before trusting any oracle."
fi

echo
echo "== regenerating every oracle =="
SNAP="$(mktemp -d)"
for d in tests/fixtures/parity/*/expected/r; do
  [ -d "$d" ] || continue
  id="$(echo "$d" | cut -d/ -f4)"
  mkdir -p "$SNAP/$id" && cp -R "$d/." "$SNAP/$id/"
done

failed=0
for g in tools/parity/generators/*/generate.R; do
  id="$(basename "$(dirname "$g")")"
  Rscript "$g" >/dev/null 2>&1 || { echo "   generator FAILED: $id"; failed=$((failed+1)); }
done

echo
echo "== what moved =="
moved=0
for d in "$SNAP"/*/; do
  id="$(basename "$d")"
  if ! diff -rq "$d" "tests/fixtures/parity/$id/expected/r" >/dev/null 2>&1; then
    echo "   CHANGED: $id"
    moved=$((moved+1))
  fi
done
[ "$moved" = "0" ] && echo "   nothing moved -- the expected outcome"

echo
echo "== refreshing the pinned inventory =="
python3 - "$UP" <<'PY'
import csv, glob, hashlib, os, re, subprocess, sys
up = sys.argv[1]
TT = re.compile(r'test_that\(\s*(["\'])(.+?)\1\s*,', re.S)
rows = []
for f in sorted(glob.glob(os.path.join(up, "tests/testthat/*.R"))):
    raw = open(f, "rb").read()
    sha = hashlib.sha256(raw).hexdigest()
    name = "tests/testthat/" + os.path.basename(f)
    for m in TT.finditer(raw.decode("utf-8", "replace")):
        rows.append([name, sha, m.group(2).strip()])
ver = re.search(r"^Version:\s*(\S+)", open(os.path.join(up, "DESCRIPTION")).read(), re.M).group(1)
head = subprocess.run(["git", "-C", up, "rev-parse", "HEAD"],
                      capture_output=True, text=True).stdout.strip()
with open("inst/spec/upstream-did-tests.csv", "w", newline="") as fh:
    fh.write(f"# did {ver} @ {head}\n")
    w = csv.writer(fh)
    w.writerow(["source_file", "source_sha256", "source_test"])
    w.writerows(rows)
print(f"   pinned {len(rows)} tests from did {ver}")
PY

echo
echo "== coverage against the refreshed pin =="
python3 tools/spec/check-upstream-coverage.py --upstream "$UP" || true

cat <<EOF

== next steps, none of them automatic ==
  1. Inherit any test reported UNCOVERED above: add a map row, and a Stata
     assertion if the behaviour is observable.
  2. For each fixture reported CHANGED, decide what it is. A real upstream
     behaviour change gets mirrored in the engine. Anything else is a
     divergence, and needs an approved row in inst/spec/feature-matrix.csv
     with a decision reference.
  3. Read NEWS.md in the upstream checkout: $UP/NEWS.md
  4. bash tools/release/preflight.sh  -- must be fully green before merge.

  generators that failed: $failed
  fixtures that moved   : $moved
EOF
