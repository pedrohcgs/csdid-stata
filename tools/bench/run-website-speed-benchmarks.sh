#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Re-measure every speed number the website publishes, in one command.
#
# The scripts are extracted from website/code-appendix.md rather than read from
# the tree, so what runs here is exactly what a reader running the published
# appendix would run. A gate (tests/meta/test-code-appendix-sync.sh) keeps the
# appendix and the tree identical, so this is not a second copy -- it is the
# published copy, exercised.
#
# Produces:
#   tools/bench/field/results/scalebench-results.csv   the results of record
#   tools/bench/field/results/metadata.json            what produced them
# and then refreshes the article tables from that CSV and checks them.
#
# Every tier runs in its own Stata process. Nothing else must be running: these
# are wall-clock measurements and a second Stata process changes them.
#
# Usage:
#   bash tools/bench/run-website-speed-benchmarks.sh            # everything
#   bash tools/bench/run-website-speed-benchmarks.sh --smoke    # wiring only
#   TIERS="E G" bash tools/bench/run-website-speed-benchmarks.sh
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---- parameters -----------------------------------------------------------
STATA="${STATA:-/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp}"
LEGACY="${CSDID_LEGACY_ROOT:-$HOME/Documents/GitHub/csdid-stata-legacy}"
# ${TIERS-...} not ${TIERS:-...}: an explicitly empty TIERS means "measure no
# field tiers", and the colon form would silently substitute the full default.
TIERS="${TIERS-E G A B C D}"
RUN_F="${RUN_F-1}"
# Partial exploratory runs may seed an earlier CSV. Promotion requires every
# published cell to have been measured in this invocation, without a seed.
SEED_CSV="${SEED_CSV-}"
WORK="${WORK:-$ROOT/build/website-speed-benchmarks}"
RESULTS="$ROOT/tools/bench/field/results"
SMOKE=0
[ "${1:-}" = "--smoke" ] && SMOKE=1

# Scripts the speed tiers need. Extracted from the appendix, never copied from
# the tree, so a drifted appendix shows up here as a failed run rather than as
# a silently different measurement.
NEEDS="dgp.do validate.do time.do runners.do scalebench.do scalebench_f_cell.do scalebench_f.sh"

# ---- preconditions --------------------------------------------------------
[ -x "$STATA" ] || { echo "no Stata at $STATA (set STATA=)" >&2; exit 1; }
[ -f "$LEGACY/codes/csdid.ado" ] || {
  echo "no Version 1.82 checkout at $LEGACY (set CSDID_LEGACY_ROOT=)" >&2; exit 1; }
[ "$(git -C "$LEGACY" rev-parse HEAD)" = "fdbae25521a941314af8d84ec0c93fb0596daa8e" ] && \
  [ -z "$(git -C "$LEGACY" status --porcelain)" ] || {
  echo "the Version 1.82 baseline must be the clean pinned fdbae255 checkout" >&2; exit 1; }

echo "== appendix and tree must agree before anything is measured"
python3 "$ROOT/tools/release/sync-code-appendix.py" >/dev/null || {
  echo "the code appendix has drifted from the tree; fix that first" >&2; exit 1; }

# ---- workspace ------------------------------------------------------------
# Rebuilt from scratch every run. A workspace carried over between runs is how
# a stale results file gets appended to and read as one session's numbers.
rm -rf "$WORK"
mkdir -p "$WORK/bench"
for f in $NEEDS; do
  python3 "$ROOT/tools/bench/extract-appendix-script.py" --name "$f" --out "$WORK/bench" >/dev/null
done
ln -sfn "$ROOT/src" "$WORK/src"
ln -sfn "$LEGACY" "$WORK/csdid-182"
ln -sfn "$ROOT/pkg/lcsdid_v2.mlib" "$WORK/bench/lcsdid_v2.mlib"
python3 - "$ROOT" "$WORK/source-fingerprint.json" <<'PY'
import hashlib, json, pathlib, sys
root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
paths = [p for p in (root / "src").rglob("*") if p.is_file() and p.suffix != ".plugin"]
paths += [root / "pkg/lcsdid_v2.mlib"]
paths += sorted((root / "pkg").glob("*.ado")) + sorted((root / "pkg").glob("*.mata"))
plugins = sorted((root / "pkg").glob("csdid_bootstrap_*.plugin"))
for plugin in plugins:
    alias = root / "src/ado" / plugin.name
    if alias.is_file() and alias.read_bytes() != plugin.read_bytes():
        sys.exit(f"source plugin differs from the install payload: {plugin.name}")
paths += plugins
for source in (root / "src/ado").glob("*.ado"):
    payload = root / "pkg" / source.name
    if payload.is_file() and source.read_bytes() != payload.read_bytes():
        sys.exit(f"measured ado differs from the install payload: {source.name}")
if (root / "src/mata/csdid.mata").read_bytes() != (root / "pkg/csdid.mata").read_bytes():
    sys.exit("measured engine source differs from the install payload")
paths += [root / "tools/bench/field" / name for name in
          "dgp.do validate.do time.do runners.do scalebench.do scalebench_f_cell.do scalebench_f.sh".split()]
output.write_text(json.dumps({str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sorted(paths)}, indent=2) + "\n")
PY

# The published launcher hardcodes an interpreter path. Make it honour $STATA
# so this driver decides which Stata is measured, and record that it did.
python3 - "$WORK/bench/scalebench_f.sh" "$STATA" <<'PY'
import sys
p, stata = sys.argv[1], sys.argv[2]
s = open(p).read()
import re
s2, n = re.subn(r'^STATA=.*$', f'STATA="{stata}"', s, count=1, flags=re.M)
if n != 1:
    sys.exit("could not find the STATA= line in the published launcher")
open(p, "w").write(s2)
PY

cd "$WORK/bench"
# scalebench.do sends a smoke run to its own file so smoke data can never be
# mistaken for the results of record. This has to follow it: counting the
# record file during a smoke run reports "rows so far: 0" after every tier and
# then "no rows were measured", which reads as a broken harness when the run
# in fact measured every cell it was asked for.
CSV="$WORK/bench/scalebench-results.csv"
[ "$SMOKE" = "1" ] && CSV="$WORK/bench/scalebench-smoke.csv"
rm -f "$CSV"
if [ -n "$SEED_CSV" ]; then
  [ -f "$SEED_CSV" ] || { echo "SEED_CSV=$SEED_CSV does not exist" >&2; exit 1; }
  cp "$SEED_CSV" "$CSV"
  echo "== seeded with $(( $(wc -l < "$CSV") - 1 )) rows from $SEED_CSV"
fi

# Row count that reports 0 for a file that does not exist yet, rather than
# letting a failed redirect print a shell error in the middle of a run.
rows_so_far () {
  if [ -f "$CSV" ]; then echo $(( $(wc -l < "$CSV") - 1 )); else echo 0; fi
}

# ---- which Stata is this, according to Stata ------------------------------
# Asked rather than assumed. The provenance line under every published table
# names the release, and a hand-written release string is how the article came
# to claim numbers from an interpreter they were not measured on.
cat > "$WORK/bench/_whichstata.do" <<'DO'
adopath ++ "../src/ado"
adopath ++ "../src/mata"
quietly _csdid_engine_load
mata: st_local("measured_engine_stamp", csdid_mlib_version())
file open vh using "_whichstata.txt", write replace text
file write vh "`c(stata_version)'|`c(edition_real)'|`c(os)'|`c(machine_type)'|`c(born_date)'|`c(processors)'" _n
file write vh "engine_stamp|`measured_engine_stamp'" _n
file write vh "engine_library|$CSDID_ENGINE_LIBRARY" _n
foreach cmd in jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn flexdid hdidregress xthdidregress drdid reghdfe ftools {
    findfile `cmd'.ado
    file write vh "package|`cmd'|`r(fn)'" _n
}
capture findfile lmoremata.mlib
if _rc file write vh "package|lmoremata|MISSING" _n
else file write vh "package|lmoremata|`r(fn)'" _n
file close vh
DO
"$STATA" -b do _whichstata.do >/dev/null 2>&1
STATA_ID="$(head -n 1 "$WORK/bench/_whichstata.txt")"
bash "$ROOT/tools/release/check-stata-log-tail.sh" "$WORK/bench/_whichstata.log"
[ -n "$STATA_ID" ] || { echo "could not ask Stata for its version" >&2; exit 1; }
echo "== interpreter reports: $STATA_ID"
python3 - "$WORK/bench/_whichstata.txt" "$WORK/package-fingerprint.json" "$ROOT" <<'PY'
import hashlib, json, pathlib, re, sys, math
identity = pathlib.Path(sys.argv[1])
records = identity.read_text().splitlines()
root = pathlib.Path(sys.argv[3])
version, edition, os_name, machine_type, born, processors = records[0].split("|")
engine = dict(line.split("|",1) for line in records[1:] if line.startswith("engine_"))
library = pathlib.Path(engine["engine_library"])
if not library.is_absolute():
    library = identity.parent/library
expected = root/"pkg/lcsdid_v2.mlib"
candidate_version = re.search(r"^\*! csdid ([0-9.]+) ", (root/"src/ado/csdid.ado").read_text()).group(1)
stamp = engine["engine_stamp"].split("|")
if library.resolve() != expected.resolve() or len(stamp) != 2 or stamp[0] != candidate_version:
    sys.exit("timing runtime did not load the explicitly pinned candidate library")
try:
    compiler = float(stamp[1])
    if not math.isfinite(compiler) or compiler <= 0 or compiler > float(version) or int(processors) <= 0:
        raise ValueError()
except ValueError:
    sys.exit("timing runtime did not accept the pinned compiled library or processor setting")
packages = {}
for record in records[1:]:
    if record.startswith("engine_"):
        continue
    kind, name, filename = record.split("|", 2)
    path = pathlib.Path(filename)
    if kind != "package" or name in packages:
        sys.exit(f"invalid installed-package identity: {record}")
    if name == "lmoremata" and filename == "MISSING":
        packages[name] = {"status": "not installed"}
        continue
    if not path.is_file() or (name == "lmoremata" and path.name != "lmoremata.mlib"):
        sys.exit(f"invalid installed-package identity: {record}")
    data = path.read_bytes()
    packages[name] = {"file": path.name, "sha256": hashlib.sha256(data).hexdigest(),
                      "version_headers": [line.strip() for line in data.decode(errors="replace").splitlines()[:50]
                                          if re.match(r"^\s*\*!", line)]}
if set(packages) != set("jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn flexdid hdidregress xthdidregress drdid reghdfe ftools lmoremata".split()):
    sys.exit("incomplete installed-package identities")
snapshot = dict(packages=packages, engine_stamp=engine["engine_stamp"],
                engine_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(), processors=int(processors))
pathlib.Path(sys.argv[2]).write_text(json.dumps(snapshot, indent=2) + "\n")
PY

# ---- the field tiers ------------------------------------------------------
started="$(date +%H:%M)"
for tier in $TIERS; do
  echo "== field tier $tier  $(date +%H:%M)"
  rm -f "$WORK/bench/scalebench.log"
  if [ "$SMOKE" = "1" ]; then
    "$STATA" -b do scalebench.do "$tier" 1 >/dev/null 2>&1
  else
    "$STATA" -b do scalebench.do "$tier" >/dev/null 2>&1
  fi
  bash "$ROOT/tools/release/check-stata-log-tail.sh" "$WORK/bench/scalebench.log"
  grep -q "^SB DONE tier=$tier smoke=$SMOKE$" "$WORK/bench/scalebench.log" || { echo "tier $tier has no completion marker" >&2; exit 1; }
  cp "$WORK/bench/scalebench.log" "$WORK/bench/scalebench-$tier.log"
  echo "   rows so far: $(rows_so_far)"
done

# ---- the Version 1.82 ladder ---------------------------------------------
if [ "$RUN_F" = "1" ] && [ "$SMOKE" = "0" ]; then
  echo "== Version 1.82 ladder  $(date +%H:%M)"
  bash scalebench_f.sh
  echo "   rows so far: $(rows_so_far)"
fi

# ---- results of record ----------------------------------------------------
# A run that measured nothing must not overwrite the results of record with an
# empty file, and must not be reported as a run.
if [ "$(rows_so_far)" -lt 1 ]; then
  echo "no rows were measured -- refusing to replace the results of record." >&2
  echo "the per-tier logs are in $WORK/bench" >&2
  exit 1
fi
# A smoke run measures one tiny cell per tier to prove the wiring. Those
# numbers are real measurements of a toy design, which is exactly what must
# never reach the published tables, so it reports and stops here.
if [ "$SMOKE" = "1" ]; then
  echo "smoke ok: $(rows_so_far) rows measured across the tiers; the results of"
  echo "record and the article tables are deliberately left untouched."
  exit 0
fi
python3 "$ROOT/tools/bench/make-field-speed-tables.py" --results "$CSV" --validate-only
[ -z "$SEED_CSV" ] || { echo "a full refresh requires fresh measurements; SEED_CSV cannot replace the results of record" >&2; exit 1; }
mkdir -p "$RESULTS"

python3 - "$WORK/metadata.json" "$STATA" "$LEGACY" "$ROOT" "$started" "$STATA_ID" "$SEED_CSV" "$TIERS" "$RUN_F" "$WORK" "$CSV" <<'PY'
import json, os, subprocess, sys, platform, datetime, hashlib, re
meta_path, stata, legacy, root, started, stata_id, seed_csv, tiers, run_f = sys.argv[1:10]
work, csv_path = sys.argv[10:12]
def git(where, *a):
    return subprocess.run(["git", *a], cwd=where, capture_output=True, text=True).stdout.strip()

# This record is committed and published. An absolute path in it describes the
# filesystem of whoever ran the benchmark and describes nothing about the
# measurement, so the two path fields keep the name and drop the location; the
# commit recorded beside legacy_root is what actually identifies the checkout.
def where(path):
    return os.path.basename(os.path.normpath(path)) if path else path

# "19.5|MP|Unix|Mac (Apple Silicon)|29 Jul 2026" -> "StataNow/MP 19.5"
#
# c(edition_real), not c(flavor): on this Stata/MP 19.5, c(flavor) reports
# "IC" and c(MP) and c(SE) are BOTH 1, so the obvious fields give the wrong
# answer. c(edition_real) gives "MP".
#
# StataNow is the continuously-updated release line and carries a non-zero
# minor version (19.5); a numbered release is 19.0. That is the one inference
# here rather than a value Stata states outright.
version, edition, os_name, machine_type, born, processors = stata_id.split("|")
minor = version.split(".")[1] if "." in version else "0"
line = "StataNow" if minor not in ("", "0") else "Stata"
stata_label = f"{line}/{edition} {version}"

candidate_text = open(os.path.join(root, "src/ado/csdid.ado")).read()
candidate_match = re.search(r"^\*! csdid ([0-9.]+) ", candidate_text)
if not candidate_match:
    sys.exit("candidate source has no version stamp")
fingerprints = json.load(open(os.path.join(work, "source-fingerprint.json")))
for name, digest in fingerprints.items():
    if hashlib.sha256(open(os.path.join(root, name), "rb").read()).hexdigest() != digest:
        sys.exit(f"measured source changed during the campaign: {name}")
    if name.startswith("pkg/") and name.endswith(".plugin"):
        alias = os.path.join(root, "src/ado", os.path.basename(name))
        if os.path.isfile(alias) and hashlib.sha256(open(alias,"rb").read()).hexdigest() != digest:
            sys.exit(f"source plugin changed during the campaign: {name}")
packages = {}
for record in open(os.path.join(work, "bench/_whichstata.txt")).read().splitlines()[1:]:
    if record.startswith("engine_"):
        continue
    kind, name, path = record.split("|", 2)
    if kind != "package" or name in packages:
        sys.exit(f"invalid installed-package identity: {record}")
    if name == "lmoremata" and path == "MISSING":
        packages[name] = {"status": "not installed"}
        continue
    if not os.path.isfile(path) or (name == "lmoremata" and os.path.basename(path) != "lmoremata.mlib"):
        sys.exit(f"invalid installed-package identity: {record}")
    data = open(path, "rb").read()
    headers = [line.strip() for line in data.decode(errors="replace").splitlines()[:50]
               if re.match(r"^\s*\*!", line)]
    packages[name] = {"file": os.path.basename(path), "sha256": hashlib.sha256(data).hexdigest(),
                      "version_headers": headers}
if set(packages) != set("jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn flexdid hdidregress xthdidregress drdid reghdfe ftools lmoremata".split()):
    sys.exit("incomplete installed-package identities")
snapshot = json.load(open(os.path.join(work, "package-fingerprint.json")))
if packages != snapshot["packages"]:
    sys.exit("installed benchmark packages changed during measurement")
json.dump({
    "candidate_version": candidate_match.group(1),
    "measurement_sha256": fingerprints,
    "results_sha256": hashlib.sha256(open(csv_path,"rb").read()).hexdigest(),
    "packages": packages,
    "engine_stamp": snapshot["engine_stamp"],
    "engine_library_sha256": snapshot["engine_library_sha256"],
    "processors": snapshot["processors"],
    "observations": 172,
    "date": datetime.date.today().isoformat(),
    "started": started,
    "stata_binary": stata,
    "stata": stata_label,
    "stata_born_date": born,
    "platform": machine_type or f"{platform.system()} {platform.machine()}",
    "platform_detail": f"{os_name}; {platform.system()} {platform.release()}",
    "candidate_commit": git(root, "rev-parse", "HEAD"),
    "legacy_root": where(legacy),
    "legacy_commit": git(legacy, "rev-parse", "HEAD"),
    "trials": 10,
    "tiers_run_here": tiers.split(),
    "ladder_run_here": run_f == "1",
    # Rows carried in from an earlier invocation of the same scripts on this
    # machine, rather than re-measured. Empty when everything was measured here.
    "seeded_from": where(seed_csv),
}, open(meta_path, "w"), indent=2)
print(f"wrote {meta_path}")
PY
cp "$CSV" "$RESULTS/scalebench-results.csv"
cp "$WORK/metadata.json" "$RESULTS/metadata.json"

# ---- publish and verify ---------------------------------------------------
echo "== refreshing the article tables from the measurement"
python3 "$ROOT/tools/release/check-website-speed-tables.py" --write
python3 "$ROOT/tools/release/check-website-speed-tables.py"
Rscript "$ROOT/tools/bench/field/fig_speed.R" "$ROOT/website/assets/img" "$RESULTS"
bash "$ROOT/tests/meta/test-website-speed-claims.sh"

echo "== done $(date +%H:%M); results of record in tools/bench/field/results/"
