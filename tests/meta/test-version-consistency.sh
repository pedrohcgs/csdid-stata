#!/usr/bin/env bash
# The version string lives in ~13 places that are otherwise hand-maintained, so
# they drift: the .ado and .sthlp headers can end up carrying two different
# dates for the same release, and nothing about the package says so. Use
# tools/release/stamp-version.py to set them together. Distribution metadata
# may be later than the unchanged build; its citation date must agree.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 tools/release/stamp-version.py --check

# Exercise the real checker and stamper on isolated inputs. Generated fixtures
# move only through their generator in the working tree; the temporary JSON
# update below models regeneration after a future package-version stamp.
python3 - "$ROOT" <<'PY'
from pathlib import Path
import datetime as dt
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
script = root / "tools/release/stamp-version.py"
selected = Path(os.environ.get("CSDID_VERSION_STAMPER", script))
record = os.environ.get("CSDID_VERSION_EVIDENCE_DIR")
evidence = Path(record) if record else None
if evidence is not None:
    evidence.mkdir(parents=True, exist_ok=False)
spec = importlib.util.spec_from_file_location("csdid_version_stamper", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
paths = set(module.ADOS + module.MATAS + module.HELPS + list(module.MLIB_FILES))
paths.update((module.PKG, module.CFF, module.F026_CONTRACT, script))
checks = []
with tempfile.TemporaryDirectory(prefix="csdid-version-check-") as temporary:
    tree = Path(temporary)
    for source in paths:
        target = tree / source.relative_to(root)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    staged_script = tree / script.relative_to(root)
    staged_script.write_bytes(selected.read_bytes())
    pkg = tree / module.PKG.relative_to(root)
    cff = tree / module.CFF.relative_to(root)
    build_stamp = next(iter(module.collect()["dates"]))
    build_day = dt.datetime.strptime(build_stamp, "%d%b%Y").date()
    later = build_day + dt.timedelta(days=1)
    earlier = build_day - dt.timedelta(days=1)
    # Keep the isolated same-day control independent of the live release's
    # possibly later distribution date. No working-tree metadata is written.
    pkg.write_text(module.DIST_DATE.sub(lambda m: m.group(1) + build_day.strftime("%Y%m%d"), pkg.read_text()))
    cff.write_text(module.CFF_DATE.sub(lambda m: m.group(1) + build_day.isoformat() + m.group(3), cff.read_text()))
    original_pkg, original_cff = pkg.read_text(), cff.read_text()
    def dates(distribution, citation):
        pkg.write_text(module.DIST_DATE.sub(lambda m: m.group(1) + distribution, original_pkg))
        cff.write_text(module.CFF_DATE.sub(lambda m: m.group(1) + citation + m.group(3), original_cff))
    def run(*arguments):
        return subprocess.run([sys.executable, str(staged_script), *arguments],
                              cwd=tree, text=True, capture_output=True)
    def expect(status, phrase, label):
        result = run("--check")
        body = result.stdout + result.stderr
        if evidence is not None:
            name = re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")
            (evidence / (name + ".log")).write_text(body)
            (evidence / (name + ".json")).write_text(json.dumps({
                "label": label, "actual_exit": result.returncode,
                "expected_exit_zero": status == 0, "expected_phrase": phrase,
                "package_metadata": pkg.read_text(), "citation_metadata": cff.read_text(),
                "source_header_dates": {str(p.relative_to(root)): [m.group(4) for m in
                    (module.HELP_HDR if p in module.HELPS else module.ADO_HDR).finditer((tree / p.relative_to(root)).read_text())]
                    for p in module.ADOS + module.MATAS + module.HELPS},
            }, indent=2) + "\n")
        assert (result.returncode == 0) == (status == 0), (label, body)
        assert phrase in body, (label, body)
        checks.append(label)
    expect(0, "version consistent:", "same-day baseline")

    dates(later.strftime("%Y%m%d"), later.isoformat())
    expect(0, "version consistent:", "later distribution with unchanged build")
    dates(earlier.strftime("%Y%m%d"), earlier.isoformat())
    expect(1, "precedes the stamped build date", "distribution before build")
    dates(later.strftime("%Y%m%d"), build_day.isoformat())
    expect(1, "disagrees with the distribution date", "citation earlier than distribution")
    dates(build_day.strftime("%Y%m%d"), later.isoformat())
    expect(1, "disagrees with the distribution date", "citation later than distribution")
    pkg.write_text(module.DIST_DATE.sub("REMOVED_DISTRIBUTION_DATE", original_pkg))
    cff.write_text(original_cff)
    expect(1, "has no 'd Distribution-Date:' line", "missing distribution date")
    dates("20261301", "2026-13-01")
    expect(1, "not a valid calendar date", "invalid distribution calendar date")
    pkg.write_text(original_pkg)
    cff.write_text(module.CFF_DATE.sub("REMOVED_CITATION_DATE", original_cff))
    expect(1, "CITATION.cff date-released missing", "missing citation date")
    dates(later.strftime("%Y%m%d"), later.isoformat())
    for source, pattern in ((module.ADOS[0], module.ADO_HDR), (module.HELPS[0], module.HELP_HDR)):
        target = tree / source.relative_to(root)
        original_header = target.read_text()
        target.write_text(pattern.sub(lambda m: m.group(0).replace(m.group(4), earlier.strftime("%d%b%Y").lower()), original_header, count=1))
        expect(1, "date stamps disagree", f"header drift {source.relative_to(root)}")
        target.write_text(original_header)
    pkg.write_text(module.PKG_VERSION.sub(lambda m: m.group(1) + "0.0.0", original_pkg))
    cff.write_text(original_cff)
    expect(1, "disagrees with the stamped version", "stale manifest version")
    pkg.write_text(original_pkg)
    cff.write_text(module.CFF_VERSION.sub(lambda m: m.group(1) + "0.0.0", original_cff))
    expect(1, "disagrees with the stamped version", "stale citation version")
    cff.write_text(original_cff)

    ado = tree / "src/ado/csdid.ado"
    original = ado.read_text()
    ado.write_text(module.ERETURN_V.sub(lambda m: m.group(1) + "0.0.0" + m.group(3), original, count=1))
    expect(1, "version strings disagree", "stale posted version")
    ado.write_text(original)

    contract_path = tree / module.F026_CONTRACT.relative_to(root)
    original_contract = contract_path.read_text()
    for name in ("panel_reg", "rc_reg", "panel_reg_cluster"):
        contract = json.loads(original_contract)
        contract["scenarios"][name]["macros"]["version"] = "0.0.0"
        contract_path.write_text(json.dumps(contract))
        expect(1, f"F026 {name} version", f"stale F026 {name}")
        contract = json.loads(original_contract)
        del contract["scenarios"][name]["macros"]["version"]
        contract_path.write_text(json.dumps(contract))
        expect(1, f"F026 {name} version", f"missing F026 {name}")
    contract_path.unlink()
    expect(1, "cannot read the F026 version contract", "absent F026 contract")
    contract_path.write_text("{")
    expect(1, "cannot read the F026 version contract", "malformed F026 contract")
    contract_path.write_text(original_contract)

    for source, required in module.MLIB_FILES.items():
        target = tree / source.relative_to(root)
        original = target.read_text()
        for name in required:
            target.write_text(module.MLIB_STAMP[name].sub("HIDDEN_STAMP_SITE", original))
            expect(1, "the library stamp is gone", f"absent {source.relative_to(root)}:{name}")
            target.write_text(original)

    session = tree / "tests/stata/test-mlib-session.do"
    foreign_seed = re.search(r'^\s*local other_pkg "([^"]+)"', session.read_text(), re.M).group(1)
    result = run("--version", "9.8.7", "--date", "31oct2026")
    assert result.returncode == 0, result.stderr
    assert module.DIST_DATE.search(pkg.read_text()).group(2) == "20261031", ("explicit stamp changed Distribution-Date", pkg.read_text())
    assert module.CFF_DATE.search(cff.read_text()).group(2) == "2026-10-31"
    assert {m.group(4) for p in module.ADOS + module.MATAS for m in module.ADO_HDR.finditer((tree / p.relative_to(root)).read_text())} == {"31oct2026"}
    checks.append("explicit stamp keeps one date across build and distribution")
    expect(1, "F026 panel_reg version", "future stamp requires fixture regeneration")
    contract = json.loads(original_contract)
    for name in ("panel_reg", "rc_reg", "panel_reg_cluster"):
        contract["scenarios"][name]["macros"]["version"] = "9.8.7"
    contract_path.write_text(json.dumps(contract))
    expect(0, "version consistent: 9.8.7", "future stamp and regenerated identity")
    before_today = dt.date.today()
    result = run("--version", "9.8.8")
    after_today = dt.date.today()
    assert result.returncode == 0, result.stderr
    stamped = dt.datetime.strptime(module.DIST_DATE.search(pkg.read_text()).group(2), "%Y%m%d").date()
    assert stamped in (before_today, after_today), ("default stamp is not today", stamped, before_today, after_today)
    assert module.CFF_DATE.search(cff.read_text()).group(2) == stamped.isoformat()
    assert {m.group(4) for p in module.ADOS + module.MATAS for m in module.ADO_HDR.finditer((tree / p.relative_to(root)).read_text())} == {stamped.strftime("%d%b%Y").lower()}
    checks.append("default stamp uses today's equal build and distribution date")
    expect(1, "F026 panel_reg version", "default stamp requires fixture regeneration")
    for name in ("panel_reg", "rc_reg", "panel_reg_cluster"):
        contract["scenarios"][name]["macros"]["version"] = "9.8.8"
    contract_path.write_text(json.dumps(contract))
    expect(0, "version consistent: 9.8.8", "default stamp and regenerated identity")
    assert re.search(r'^\s*local other_pkg "([^"]+)"', session.read_text(), re.M).group(1) == foreign_seed
    checks.append("foreign-package seed preserved")
print(f"version checker qualified: {len(checks)} isolated states; foreign-package seed preserved")
PY
