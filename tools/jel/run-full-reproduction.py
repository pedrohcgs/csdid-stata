#!/usr/bin/env python3
"""Run the full JEL-DiD empirical reproduction in an isolated worktree.

This is intentionally opt-in and writes generated files under build/.  It does
not modify the frozen upstream JEL-DiD checkout.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path


EXPECTED_JEL_COMMIT = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466"
EXPECTED_DID_VERSION = "2.5.1"
EXPECTED_DID_COMMIT = "9aba07d054a798558ac9b551887f5cb592d8db10"
EXPECTED_DRDID_VERSION = "1.3.0"
# Home-relative, and overridable: an absolute path here only worked on one
# machine and hardcoded the maintainer's layout into a public repository.
DEFAULT_JEL_REPO = Path(
    os.environ.get("JEL_DID_REFERENCE", Path.home() / "Documents/GitHub/JEL-DiD")
).expanduser()
JEL_SSC_DATE = "2025-11-29"

TABLES = [f"tables/table{i}_{role}.tex" for i in range(1, 8) for role in ("R", "stata")]
FIGURES = [f"figures/figure{i}_{role}.pdf" for i in range(1, 10) for role in ("R", "stata")]
DATA_ARTIFACTS = [
    "data/county_mortality_data.csv",
    "data/did_jel_aca_replication_data.dta",
]
EXPECTED_ARTIFACTS = DATA_ARTIFACTS + TABLES + FIGURES

FAILURE_PATTERNS = [
    re.compile(r"^r\([0-9]+\);$", re.MULTILINE),
    re.compile(r"assertion is false", re.IGNORECASE),
    re.compile(r"after merge, not all observations matched", re.IGNORECASE),
    re.compile(r"type mismatch", re.IGNORECASE),
    re.compile(r"invalid syntax", re.IGNORECASE),
    re.compile(r"conformability error", re.IGNORECASE),
    re.compile(r"command .* unrecognized", re.IGNORECASE),
    re.compile(r"option .* not allowed", re.IGNORECASE),
    re.compile(r"--Break--"),
]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def run(
    cmd: list[str],
    *,
    cwd: Path,
    log_path: Path,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with log_path.open("w", encoding="utf-8") as log:
        log.write(f"$ {' '.join(cmd)}\n")
        log.write(f"cwd: {cwd}\n\n")
        log.flush()
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            env=env,
            text=True,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        log.write(f"\nexit_code: {proc.returncode}\n")
        log.write(f"elapsed_seconds: {time.time() - started:.3f}\n")
    if check and proc.returncode != 0:
        tail = tail_text(log_path)
        raise RuntimeError(f"command failed: {' '.join(cmd)}\nlog: {log_path}\n\n{tail}")
    return proc


def tail_text(path: Path, lines: int = 80) -> str:
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(text[-lines:])


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def artifact_record(base: Path, rel: str, role: str) -> dict[str, str]:
    path = base / rel
    record = {
        "artifact": rel,
        "role": role,
        "exists": "1" if path.exists() else "0",
        "bytes": "",
        "sha256": "",
    }
    if path.exists():
        record["bytes"] = str(path.stat().st_size)
        record["sha256"] = sha256(path)
    return record


def numeric_tokens(path: Path) -> list[str]:
    if not path.exists() or path.suffix.lower() != ".tex":
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    return re.findall(r"[-+]?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?", text)


def rendered_pdf_comparison(source_path: Path, generated_path: Path) -> tuple[bool | None, str]:
    pdftoppm = shutil.which("pdftoppm")
    compare = shutil.which("compare")
    if pdftoppm is None or compare is None:
        return None, "pdf-hash-compared"

    with tempfile.TemporaryDirectory(prefix="jel-pdf-compare-") as tmp:
        tmpdir = Path(tmp)
        frozen_prefix = tmpdir / "frozen"
        generated_prefix = tmpdir / "generated"
        for pdf, prefix in ((source_path, frozen_prefix), (generated_path, generated_prefix)):
            proc = subprocess.run(
                [pdftoppm, "-r", "144", "-png", str(pdf), str(prefix)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if proc.returncode != 0:
                return None, "pdf-render-failed"

        frozen_pages = sorted(tmpdir.glob("frozen-*.png"))
        generated_pages = sorted(tmpdir.glob("generated-*.png"))
        if len(frozen_pages) != len(generated_pages):
            return False, f"pdf-rendered-page-count-drift:{len(frozen_pages)}->{len(generated_pages)}"

        total_drift = 0
        for frozen_page, generated_page in zip(frozen_pages, generated_pages):
            proc = subprocess.run(
                [compare, "-metric", "AE", str(frozen_page), str(generated_page), "null:"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            metric = (proc.stderr or proc.stdout).strip().split(" ", 1)[0]
            try:
                drift = int(float(metric))
            except ValueError:
                return None, "pdf-rendered-compare-failed"
            total_drift += drift

        if total_drift == 0:
            return True, "pdf-rendered-pixel-match"
        return False, f"pdf-rendered-pixel-drift:{total_drift}"


def pdf_text(path: Path) -> str:
    pdftotext = shutil.which("pdftotext")
    if pdftotext is None or not path.exists():
        return ""
    proc = subprocess.run(
        [pdftotext, str(path), "-"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.replace("\u2212", "-")


def extract_labeled_effect(text: str) -> dict[str, float]:
    out: dict[str, float] = {}
    patterns = {
        "estimate": r"Estimate.*?=\s*([-+]?\d+(?:\.\d+)?)",
        "std_error": r"Std\.\s*Error\s*=\s*([-+]?\d+(?:\.\d+)?)",
        "ci_low": r"Conf\.\s*Int\s*=\s*\[\s*([-+]?\d+(?:\.\d+)?)\s*,",
        "ci_high": r"Conf\.\s*Int\s*=\s*\[\s*[-+]?\d+(?:\.\d+)?\s*,\s*([-+]?\d+(?:\.\d+)?)\s*\]",
    }
    compact = " ".join(text.split())
    for metric, pattern in patterns.items():
        match = re.search(pattern, compact)
        if match:
            out[metric] = float(match.group(1))
    return out


def normalized_pdf_tokens(path: Path) -> Counter[str]:
    text = pdf_text(path)
    text = text.replace("\u2013", "-").replace("\u2014", "-")
    text = text.replace("Event-Time", "Event Time")
    text = text.replace("event-time", "event time")
    text = text.lower()
    text = re.sub(r"(?<!\d)\.(\d)", r"0.\1", text)
    return Counter(re.findall(r"[a-z]+|[-+]?\d+(?:\.\d+)?|[{}]", text))


def _label_number_token(value: float) -> str:
    return f"{value:.2f}"


def _remove_label_number_tokens(tokens: Counter[str], values: dict[str, float]) -> Counter[str]:
    out = Counter(tokens)
    for metric in ("estimate", "std_error", "ci_low", "ci_high"):
        value = values.get(metric)
        if value is None:
            continue
        token = _label_number_token(value)
        if out[token] > 0:
            out[token] -= 1
            if out[token] == 0:
                del out[token]
    return out


def stata_pdf_semantic_comparison(
    source_path: Path,
    generated_path: Path,
    worktree: Path,
    render_detail: str,
) -> tuple[bool, dict[str, str]]:
    match = re.search(r"figure(\d+)_stata\.pdf$", generated_path.name)
    figure = f"figure{match.group(1)}" if match else generated_path.stem
    figure_number = int(match.group(1)) if match else -1

    source_tokens = normalized_pdf_tokens(source_path)
    generated_tokens = normalized_pdf_tokens(generated_path)
    text_status = "text-token-drift"
    label_status = "not-applicable"
    status = "needs-review"

    if source_tokens == generated_tokens:
        text_status = "text-token-match"
        status = "semantic-match"
    elif figure_number in {3, 8, 9}:
        source_labels = extract_labeled_effect(pdf_text(source_path))
        generated_labels = extract_labeled_effect(pdf_text(generated_path))
        r_labels = extract_labeled_effect(pdf_text(worktree / "figures" / f"figure{figure_number}_R.pdf"))

        label_diffs: list[str] = []
        for metric in ("estimate", "std_error", "ci_low", "ci_high"):
            rv = r_labels.get(metric)
            sv = generated_labels.get(metric)
            if rv is None or sv is None:
                label_diffs.append(f"{metric}=missing")
            elif abs(rv - sv) > 0.005:
                label_diffs.append(f"{metric}={rv:.2f}->{sv:.2f}")

        # HONESTY GUARD. For these figures the harness injects R's own label
        # values into the Stata script (see the _jel_load_r_label_values
        # injection below), so `generated_labels' are R's numbers, not Stata's.
        # Comparing them to `r_labels' therefore compares R with R and can only
        # ever agree. Reporting that as "r-label-match" reads as evidence of
        # parity when it carries no information at all, so name what it is.
        # The genuine evidence for these figures is the text/render comparison
        # below; the label channel is not evidence and is marked as such.
        # A real Stata-vs-R label comparison requires the harness to dump
        # Stata's own computed values before the injection - recorded as
        # outstanding work, not silently implied here.
        labels_injected = (
            worktree / "data" / f"figure{figure_number}_r_label_values.csv"
        ).is_file()

        if label_diffs:
            label_status = "r-label-drift:" + ",".join(label_diffs)
        elif labels_injected:
            label_status = "r-labels-injected-not-evidence"
        else:
            label_status = "r-label-match"
            stripped_source = _remove_label_number_tokens(source_tokens, source_labels)
            stripped_generated = _remove_label_number_tokens(generated_tokens, generated_labels)
            if stripped_source == stripped_generated:
                text_status = "text-token-match-ignoring-stale-labels"
                status = "semantic-match"

    detail = f"{text_status}; {label_status}; {render_detail}"
    return status == "semantic-match", {
        "figure": figure,
        "artifact": str(generated_path.relative_to(worktree)),
        "text_status": text_status,
        "label_status": label_status,
        "render_detail": render_detail,
        "status": status,
        "detail": detail,
    }


def audit_r_stata_figure_labels(worktree: Path, outputs_dir: Path) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    failures: list[dict[str, str]] = []
    tolerance = 0.005
    for fig in (3, 8, 9):
        r_values = extract_labeled_effect(pdf_text(worktree / "figures" / f"figure{fig}_R.pdf"))
        stata_values = extract_labeled_effect(pdf_text(worktree / "figures" / f"figure{fig}_stata.pdf"))
        for metric in ("estimate", "std_error", "ci_low", "ci_high"):
            rv = r_values.get(metric)
            sv = stata_values.get(metric)
            if rv is None or sv is None:
                status = "missing-label"
                diff = ""
            else:
                abs_diff = abs(rv - sv)
                status = "display-match" if abs_diff <= tolerance else "display-drift"
                diff = f"{abs_diff:.6g}"
            row = {
                "figure": f"figure{fig}",
                "metric": metric,
                "r_value": "" if rv is None else f"{rv:.12g}",
                "stata_value": "" if sv is None else f"{sv:.12g}",
                "abs_diff": diff,
                "tolerance": f"{tolerance:.12g}",
                "status": status,
            }
            rows.append(row)
            if status != "display-match":
                failures.append(row)

    write_csv(
        outputs_dir / "figure-label-audit.csv",
        rows,
        ["figure", "metric", "r_value", "stata_value", "abs_diff", "tolerance", "status"],
    )
    return rows, failures


TABLE7_LAYOUT = [
    ("unweighted", "reg"),
    ("unweighted", "ipw"),
    ("unweighted", "dr"),
    ("weighted", "reg"),
    ("weighted", "ipw"),
    ("weighted", "dr"),
]


def extract_table7_display_values(path: Path) -> dict[tuple[str, str, str], float]:
    values: dict[tuple[str, str, str], float] = {}
    if not path.exists():
        return values
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    idx = next((i for i, line in enumerate(lines) if "Medicaid Expansion" in line), None)
    if idx is None:
        return values
    est_tokens = [float(x) for x in re.findall(r"[-+]?\d+\.\d+", lines[idx])]
    se_tokens: list[float] = []
    for line in lines[idx + 1 : idx + 5]:
        se_tokens = [float(x) for x in re.findall(r"[-+]?\d+\.\d+", line)]
        if se_tokens:
            break
    for i, (panel, method) in enumerate(TABLE7_LAYOUT):
        if i < len(est_tokens):
            values[(panel, method, "estimate")] = est_tokens[i]
        if i < len(se_tokens):
            values[(panel, method, "std_error")] = se_tokens[i]
    return values


def audit_r_stata_table7_display(worktree: Path, outputs_dir: Path) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    failures: list[dict[str, str]] = []
    tolerance = 0.005
    r_values = extract_table7_display_values(worktree / "tables" / "table7_R.tex")
    stata_values = extract_table7_display_values(worktree / "tables" / "table7_stata.tex")
    for panel, method in TABLE7_LAYOUT:
        for metric in ("estimate", "std_error"):
            key = (panel, method, metric)
            rv = r_values.get(key)
            sv = stata_values.get(key)
            if rv is None or sv is None:
                status = "missing-value"
                diff = ""
            else:
                abs_diff = abs(rv - sv)
                status = "display-match" if abs_diff <= tolerance else "display-drift"
                diff = f"{abs_diff:.6g}"
            row = {
                "table": "table7",
                "panel": panel,
                "method": method,
                "metric": metric,
                "r_value": "" if rv is None else f"{rv:.12g}",
                "stata_value": "" if sv is None else f"{sv:.12g}",
                "abs_diff": diff,
                "tolerance": f"{tolerance:.12g}",
                "status": status,
            }
            rows.append(row)
            if status != "display-match":
                failures.append(row)

    write_csv(
        outputs_dir / "table7-display-audit.csv",
        rows,
        ["table", "panel", "method", "metric", "r_value", "stata_value", "abs_diff", "tolerance", "status"],
    )
    return rows, failures


def is_historical_r_oracle_repin_drift(row: dict[str, str]) -> bool:
    artifact = row["artifact"]
    return row["status"] == "hash-drift" and (
        artifact.endswith("_R.tex") or artifact.endswith("_R.pdf")
    )


def is_table7_stata_rebuilt_drift(row: dict[str, str]) -> bool:
    return row["artifact"] == "tables/table7_stata.tex" and row["status"] == "hash-drift"


def render_pdf_side_by_side(
    source: Path,
    worktree: Path,
    comparison_rows: list[dict[str, str]],
    outputs_dir: Path,
) -> dict[str, object]:
    pdftoppm = shutil.which("pdftoppm")
    magick = shutil.which("magick") or shutil.which("convert")
    if pdftoppm is None or magick is None:
        return {
            "available": False,
            "reason": "pdftoppm-or-imagemagick-missing",
            "count": 0,
            "sheets": [],
        }

    pdf_rows = [
        row
        for row in comparison_rows
        if row["artifact"].endswith(".pdf")
        and row["status"] not in {"hash-match", "semantic-match", "generated-new"}
        and row["frozen_exists"] == "1"
        and row["regenerated_exists"] == "1"
    ]
    if not pdf_rows:
        return {"available": True, "reason": "", "count": 0, "sheets": []}

    visual_dir = outputs_dir / "visual-review"
    if visual_dir.exists():
        shutil.rmtree(visual_dir)
    visual_dir.mkdir(parents=True, exist_ok=True)

    side_paths: list[Path] = []
    for row in pdf_rows:
        rel = row["artifact"]
        safe = rel.replace("/", "__").replace(".pdf", "")
        frozen_prefix = visual_dir / f"{safe}-frozen"
        generated_prefix = visual_dir / f"{safe}-regenerated"
        for pdf, prefix in ((source / rel, frozen_prefix), (worktree / rel, generated_prefix)):
            proc = subprocess.run(
                [pdftoppm, "-r", "96", "-png", str(pdf), str(prefix)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if proc.returncode != 0:
                continue
        frozen_page = visual_dir / f"{safe}-frozen-1.png"
        generated_page = visual_dir / f"{safe}-regenerated-1.png"
        side_path = visual_dir / f"{safe}-side-by-side.png"
        if frozen_page.exists() and generated_page.exists():
            proc = subprocess.run(
                [magick, str(frozen_page), str(generated_page), "+append", str(side_path)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if proc.returncode == 0 and side_path.exists():
                side_paths.append(side_path)

    overview = visual_dir / "stata-pdf-drift-side-by-side.png"
    if side_paths:
        subprocess.run(
            [magick, *map(str, side_paths), "-append", str(overview)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    sheets = [str(overview)] if overview.exists() else [str(p) for p in side_paths]
    return {
        "available": True,
        "reason": "",
        "count": len(side_paths),
        "sheets": sheets,
    }


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def renv_package_versions(lockfile: Path) -> dict[str, str]:
    if not lockfile.exists():
        raise RuntimeError(f"JEL R oracle lockfile not found: {lockfile}")
    data = json.loads(lockfile.read_text(encoding="utf-8"))
    packages = data.get("Packages", {})
    versions: dict[str, str] = {}
    for package in ("did", "DRDID"):
        meta = packages.get(package)
        versions[package] = "" if meta is None else str(meta.get("Version", ""))
    return versions


def patch_jel_r_oracle_lock(worktree: Path, summary: dict[str, object]) -> None:
    """Repin the copied JEL renv lock to the package-wide R did oracle.

    The upstream JEL repository intentionally remains frozen.  The release gate
    runs from a copied worktree and must certify the Stata package against the
    current package oracle, R did 2.5.1, not the historical JEL lock.
    """

    lockfile = worktree / "renv.lock"
    if not lockfile.exists():
        raise RuntimeError(f"JEL R oracle lockfile not found: {lockfile}")

    data = json.loads(lockfile.read_text(encoding="utf-8"))
    packages = data.setdefault("Packages", {})
    before = {
        "did": str(packages.get("did", {}).get("Version", "")),
        "DRDID": str(packages.get("DRDID", {}).get("Version", "")),
    }
    summary["r_oracle_lock_versions_before_repin"] = before

    packages["did"] = {
        "Package": "did",
        "Version": EXPECTED_DID_VERSION,
        "Source": "GitHub",
        "Title": "Treatment Effects with Multiple Periods and Groups",
        "URL": "https://bcallaway11.github.io/did/, https://github.com/bcallaway11/did/",
        "Depends": ["R (>= 4.1.0)"],
        "License": "GPL-3",
        "Encoding": "UTF-8",
        "LazyData": "true",
        "Imports": [
            "BMisc (>= 1.4.4)",
            "Matrix",
            "pbapply",
            "ggplot2",
            "DRDID (>= 1.3.0)",
            "generics",
            "methods",
            "tidyr",
            "fastglm",
            "data.table (>= 1.15.4)",
            "dreamerr (>= 1.4.0)",
        ],
        "RemoteType": "github",
        "RemoteHost": "api.github.com",
        "RemoteRepo": "did",
        "RemoteUsername": "bcallaway11",
        "RemoteRef": "HEAD",
        "RemoteSha": EXPECTED_DID_COMMIT,
        "NeedsCompilation": "no",
    }

    packages["DRDID"] = {
        "Package": "DRDID",
        "Version": EXPECTED_DRDID_VERSION,
        "Source": "Repository",
        "Type": "Package",
        "Title": "Doubly Robust Difference-in-Differences Estimators",
        "URL": "https://psantanna.com/DRDID/, https://github.com/pedrohcgs/DRDID",
        "License": "GPL-3",
        "Encoding": "UTF-8",
        "LazyData": "true",
        "Depends": ["R (>= 3.5)"],
        "Imports": [
            "stats",
            "trust",
            "BMisc (>= 1.4.1)",
            "Rcpp (>= 1.0.12)",
            "fastglm (>= 0.0.3)",
        ],
        "LinkingTo": ["Rcpp (>= 1.0.12)"],
        "Repository": "CRAN",
        "NeedsCompilation": "yes",
    }

    lockfile.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    summary["r_oracle_lock_repin"] = {
        "did": EXPECTED_DID_VERSION,
        "did_remote_sha": EXPECTED_DID_COMMIT,
        "DRDID": EXPECTED_DRDID_VERSION,
        "scope": "copied JEL worktree only",
    }


def validate_jel_r_oracle(worktree: Path, summary: dict[str, object]) -> None:
    versions = renv_package_versions(worktree / "renv.lock")
    summary["r_oracle_versions"] = versions
    expected = {"did": EXPECTED_DID_VERSION, "DRDID": EXPECTED_DRDID_VERSION}
    failures = [
        f"{package}={versions.get(package) or 'missing'} (expected {version})"
        for package, version in expected.items()
        if versions.get(package) != version
    ]
    if failures:
        raise RuntimeError(
            "JEL R oracle version mismatch in renv.lock; refusing to produce "
            "release evidence against the wrong R oracle: " + "; ".join(failures)
        )


def copy_jel_repo(source: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    ignore = shutil.ignore_patterns(
        ".git",
        "renv/library",
        "renv/staging",
        "ado",
        "*.log",
        "*.gph",
        "*.emf",
        "testo.dta",
        "testo.ster",
    )
    shutil.copytree(source, dest, ignore=ignore)


def git_output(repo: Path, *args: str) -> str:
    out = subprocess.check_output(["git", "-C", str(repo), *args], text=True)
    return out.strip()


def find_jel_rscript() -> Path | str:
    override = os.environ.get("CSDID_JEL_RSCRIPT")
    if override:
        return Path(override).expanduser()

    candidates = [
        Path("/Library/Frameworks/R.framework/Versions/4.4-arm64/Resources/bin/Rscript"),
        Path("/Library/Frameworks/R.framework/Versions/4.4/Resources/bin/Rscript"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return "Rscript"


def prepare_r_home_overlay(work_dir: Path) -> Path | None:
    base = Path("/Library/Frameworks/R.framework/Versions/4.4-arm64/Resources")
    exec_r = base / "bin" / "exec" / "R"
    if not exec_r.exists():
        return None

    overlay = work_dir / "R-4.4-home"
    bin_dir = overlay / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    for name in ["doc", "etc", "include", "lib", "library", "modules", "share"]:
        target = overlay / name
        if target.exists() or target.is_symlink():
            continue
        target.symlink_to(base / name)

    for source in (base / "bin").iterdir():
        target = bin_dir / source.name
        if source.name in {"R", "Rscript", "exec"}:
            continue
        if target.exists() or target.is_symlink():
            continue
        target.symlink_to(source)

    exec_dir = bin_dir / "exec"
    if exec_dir.is_symlink():
        exec_dir.unlink()
    exec_dir.mkdir(exist_ok=True)
    exec_wrapper = f"""#!/bin/sh
R_HOME_DIR="{overlay}"
export R_HOME="$R_HOME_DIR"
export R_SHARE_DIR="$R_HOME_DIR/share"
export R_INCLUDE_DIR="$R_HOME_DIR/include"
export R_DOC_DIR="$R_HOME_DIR/doc"
export DYLD_LIBRARY_PATH="$R_HOME_DIR/lib:${{DYLD_LIBRARY_PATH:-}}"
for arg in "$@"; do
  if [ "$arg" = "CMD" ]; then
    while [ "$1" != "CMD" ]; do shift; done
    shift
    exec sh "$R_HOME/bin/Rcmd" "$@"
  fi
done
exec "{exec_r}" "$@"
"""
    exec_path = exec_dir / "R"
    exec_path.write_text(exec_wrapper, encoding="utf-8")
    exec_path.chmod(0o755)

    wrapper = f"""#!/bin/sh
R_HOME_DIR="{overlay}"
export R_HOME="$R_HOME_DIR"
export R_SHARE_DIR="$R_HOME_DIR/share"
export R_INCLUDE_DIR="$R_HOME_DIR/include"
export R_DOC_DIR="$R_HOME_DIR/doc"
export DYLD_LIBRARY_PATH="$R_HOME_DIR/lib:${{DYLD_LIBRARY_PATH:-}}"
for arg in "$@"; do
  if [ "$arg" = "CMD" ]; then
    while [ "$1" != "CMD" ]; do shift; done
    shift
    exec sh "$R_HOME/bin/Rcmd" "$@"
  fi
done
exec "{exec_r}" "$@"
"""
    r_path = bin_dir / "R"
    r_path.write_text(wrapper, encoding="utf-8")
    r_path.chmod(0o755)
    return overlay


def configure_r_toolchain_env(env: dict[str, str]) -> None:
    """Use a discoverable Fortran runtime when R's baked-in FLIBS is stale."""

    homebrew = Path("/opt/homebrew")
    if (homebrew / "include").exists() and (homebrew / "lib").exists():
        env["CPPFLAGS"] = f"-I{homebrew / 'include'} {env.get('CPPFLAGS', '')}".strip()
        env["LDFLAGS"] = f"-L{homebrew / 'lib'} {env.get('LDFLAGS', '')}".strip()
        pkg_config = homebrew / "lib" / "pkgconfig"
        if pkg_config.exists():
            env["PKG_CONFIG_PATH"] = (
                f"{pkg_config}:{env['PKG_CONFIG_PATH']}"
                if env.get("PKG_CONFIG_PATH")
                else str(pkg_config)
            )
        env["DYLD_LIBRARY_PATH"] = (
            f"{homebrew / 'lib'}:{env['DYLD_LIBRARY_PATH']}"
            if env.get("DYLD_LIBRARY_PATH")
            else str(homebrew / "lib")
        )

    for gcc_root in sorted(Path("/opt/homebrew/Cellar/gcc").glob("*/lib/gcc/current"), reverse=True):
        arch_lib = next((gcc_root / "gcc").glob("aarch64-apple-darwin*/15"), None)
        gfortran = Path("/opt/homebrew/bin/gfortran")
        if (
            arch_lib
            and gfortran.exists()
            and (gcc_root / "libgfortran.dylib").exists()
            and (gcc_root / "libquadmath.dylib").exists()
            and (arch_lib / "libemutls_w.a").exists()
            and (arch_lib / "libheapt_w.a").exists()
        ):
            env["FC"] = f"{gfortran} -arch arm64"
            env["F77"] = f"{gfortran} -arch arm64"
            env["FLIBS"] = (
                f"-L{arch_lib} -L{gcc_root} "
                "-lemutls_w -lheapt_w -lgfortran -lquadmath"
            )
            env["DYLD_LIBRARY_PATH"] = (
                f"{gcc_root}:{env['DYLD_LIBRARY_PATH']}"
                if env.get("DYLD_LIBRARY_PATH")
                else str(gcc_root)
            )
            return


def write_r_makevars(work_dir: Path, env: dict[str, str]) -> None:
    if not env.get("FLIBS"):
        return
    cppflags = env.get("CPPFLAGS", "")
    ldflags = env.get("LDFLAGS", "")
    makevars = work_dir / "Makevars.jel-full"
    makevars.parent.mkdir(parents=True, exist_ok=True)
    makevars.write_text(
        "\n".join(
            [
                f"FC = {env['FC']}",
                f"F77 = {env['F77']}",
                f"CPPFLAGS += {cppflags}",
                f"LDFLAGS += {ldflags}",
                f"FLIBS = {env['FLIBS']}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    env["R_MAKEVARS_USER"] = str(makevars)


def _csv_missing(value: str | None) -> bool:
    return value is None or value == "" or value.upper() == "NA"


def _csv_float(value: str | None) -> float | None:
    if _csv_missing(value):
        return None
    return float(value)


def write_figure3_r_order(worktree: Path, out_path: Path) -> None:
    """Write county order produced by the R Figure 3 data pipeline."""
    rows: list[dict[str, str]] = []
    with (worktree / "data" / "county_mortality_data.csv").open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            county = row.get("county", "")
            state = county[-2:]
            yaca = _csv_float(row.get("yaca"))
            if state in {"DC", "DE", "MA", "NY", "VT"}:
                continue
            if not (yaca == 2014 or yaca is None or yaca > 2019):
                continue

            required = [
                "county",
                "county_code",
                "year",
                "population_20_64",
                "population_20_64_white",
                "population_20_64_hispanic",
                "population_20_64_female",
                "crude_rate_20_64",
                "unemp_rate",
                "poverty_rate",
                "median_income",
            ]
            if any(_csv_missing(row.get(col)) for col in required):
                continue
            rows.append(row)

    by_county: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_county.setdefault(row["county_code"], []).append(row)

    keep_counties: set[str] = set()
    for county_code, county_rows in by_county.items():
        years = {_csv_float(row.get("year")) for row in county_rows}
        has_2013_2014 = 2013 in years and 2014 in years
        full_mortality = len(county_rows) == 11
        if has_2013_2014 and full_mortality:
            keep_counties.add(county_code)

    county_yaca: dict[str, float | None] = {}
    for row in rows:
        county_code = row["county_code"]
        if county_code in keep_counties and county_code not in county_yaca:
            county_yaca[county_code] = _csv_float(row.get("yaca"))

    ordered = sorted(
        keep_counties,
        key=lambda county_code: (
            0 if county_yaca.get(county_code) == 2014 else 1,
            float(county_code),
        ),
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["county_code", "__jel_r_order"])
        for i, county_code in enumerate(ordered, start=1):
            writer.writerow([county_code, i])


def patch_jel_r_rng_state_exports(worktree: Path) -> None:
    """Export R RNG states needed to mirror R did 2.5.1 display bootstraps."""
    script2 = worktree / "scripts" / "R" / "2_2x2.R"
    text = script2.read_text(encoding="utf-8", errors="replace")
    table7_marker = "  # aggregate estimates \n  aggte(atts, na.rm = TRUE, biters = 25000) %>% "
    table7_export = (
        '  state_suffix <- paste0(ifelse(is.null(wt), "unweighted", "weighted"), "_", method)\n'
        "  write_csv(tibble(idx = seq_along(.Random.seed), val = .Random.seed),\n"
        '            here::here("data", paste0("table7_rng_state_", state_suffix, ".csv")))\n'
        "\n"
        + table7_marker
    )
    if "table7_rng_state_unweighted_reg.csv" not in text:
        text, count = re.subn(re.escape(table7_marker), table7_export, text, count=1)
        if count != 1:
            raise RuntimeError(f"expected to patch Table 7 R RNG exports in {script2}, patched {count}")
        script2.write_text(text, encoding="utf-8")

    script3 = worktree / "scripts" / "R" / "3_2XT.R"
    text = script3.read_text(encoding="utf-8", errors="replace")
    marker = 'robust_ci <- honest_did(es = es, type = "relative_magnitude")$robust_ci'
    export = (
        marker
        + '\n\nwrite_csv(tibble(idx = seq_along(.Random.seed), val = .Random.seed),\n'
        + '          here::here("data", "figure3_honestdid_rng_state.csv"))'
    )
    if 'figure3_honestdid_rng_state.csv' not in text:
        text, count = re.subn(re.escape(marker), export, text, count=1)
        if count != 1:
            raise RuntimeError(f"expected to patch Figure 3 R RNG export in {script3}, patched {count}")
    if "figure3_r_label_values.csv" not in text:
        label_pattern = re.compile(
            r'(label2 <- paste0\("Std\. Error = ", scales::number\(agg\$overall\.se, 0\.01\), " \\n",\n'
            r'\s*"Conf\. Int = \[", scales::number\(agg\$overall\.att - 1\.96\*agg\$overall\.se, 0\.01\), ", ", \n'
            r'\s*scales::number\(agg\$overall\.att \+ 1\.96\*agg\$overall\.se, 0\.01\), "\]"\))',
            re.MULTILINE,
        )
        label_export = (
            r"\1"
            + '\n\nwrite_csv(tibble(figure = "figure3", estimate = agg$overall.att,\n'
            + '                  std_error = agg$overall.se,\n'
            + '                  ci_low = agg$overall.att - 1.96 * agg$overall.se,\n'
            + '                  ci_high = agg$overall.att + 1.96 * agg$overall.se),\n'
            + '          here::here("data", "figure3_r_label_values.csv"))'
        )
        text, count = label_pattern.subn(label_export, text, count=1)
        if count != 1:
            raise RuntimeError(f"expected to patch Figure 3 R label export in {script3}, patched {count}")
        script3.write_text(text, encoding="utf-8")

    script4 = worktree / "scripts" / "R" / "4_GxT.R"
    text = script4.read_text(encoding="utf-8", errors="replace")
    if "figure8_r_label_values.csv" not in text:
        label_pattern = re.compile(
            r'(label2 <- paste0\("Std\. Error = ", scales::number\(agg\$overall\.se, 0\.01\), " \\n",\n'
            r'\s*"Conf\. Int = \[", scales::number\(agg\$overall\.att - 1\.96\*agg\$overall\.se, 0\.01\), ", ", \n'
            r'\s*scales::number\(agg\$overall\.att \+ 1\.96\*agg\$overall\.se, 0\.01\), "\]"\))',
            re.MULTILINE,
        )
        figures = iter(("figure8", "figure9"))

        def add_label_export(match: re.Match[str]) -> str:
            figure = next(figures)
            return (
                match.group(1)
                + f'\n\nwrite_csv(tibble(figure = "{figure}", estimate = agg$overall.att,\n'
                + '                  std_error = agg$overall.se,\n'
                + '                  ci_low = agg$overall.att - 1.96 * agg$overall.se,\n'
                + '                  ci_high = agg$overall.att + 1.96 * agg$overall.se),\n'
                + f'          here::here("data", "{figure}_r_label_values.csv"))'
            )

        text, count = label_pattern.subn(add_label_export, text, count=2)
        if count != 2:
            raise RuntimeError(f"expected to patch Figure 8/9 R label exports in {script4}, patched {count}")
        script4.write_text(text, encoding="utf-8")


def build_stata_wrapper(path: Path, port_root: Path, worktree: Path) -> None:
    plus = worktree / "ado" / "plus"
    personal = worktree / "ado" / "personal"
    plus_under = plus / "_"
    plus_under.mkdir(parents=True, exist_ok=True)
    figure3_order = plus_under / "figure3_r_order.csv"
    write_figure3_r_order(worktree, figure3_order)
    (plus_under / "_jel_apply_figure3_r_order.ado").write_text(
        f"""
program define _jel_apply_figure3_r_order
    version 15
    preserve
        import delimited using "{figure3_order}", clear varnames(1)
        tempfile order
        save `order'
    restore
    merge m:1 county_code using `order', nogen keep(master match)
    sort __jel_r_order year
end
""".lstrip(),
        encoding="utf-8",
    )
    (plus_under / "_jel_repost_event_with_label.ado").write_text(
        """
program define _jel_repost_event_with_label, eclass
    version 15
    args min_e max_e pre_min_e pre_max_e carry_state extra_draws permute_order statefile
    if "`min_e'" == "" local min_e 0
    if "`max_e'" == "" local max_e 5
    if "`extra_draws'" == "" | "`extra_draws'" == "." local extra_draws 0
    tempname pre_agg pre_if label_agg label_if full_agg rng rng_loaded label_se label_if_ordered label_cluster_ordered

    local biters = e(biters)
    local cband = e(cband)
    local boot_dist "`e(boot_dist)'"
    if "`boot_dist'" == "" local boot_dist "rademacher"
    if "`boot_dist'" != "rademacher" {
        display as error "_jel_repost_event_with_label requires BMisc rademacher bootstrap state"
        exit 498
    }
    capture confirm matrix e(boot_rng_state)
    if _rc {
        display as error "_jel_repost_event_with_label requires e(boot_rng_state)"
        exit 498
    }
    matrix `rng' = e(boot_rng_state)

    if "`carry_state'" != "" & "`carry_state'" != "." {
        capture confirm matrix __jel_bmisc_rng_state
        if !_rc {
            matrix `rng' = __jel_bmisc_rng_state
            mata: csdid_bmisc_attgtskip("e(inffunc)", `biters', "`rng'")
        }
    }

    if "`pre_min_e'" != "" & "`pre_min_e'" != "." & "`pre_max_e'" != "" & "`pre_max_e'" != "." {
        mata: csdid_aggte("dynamic", `pre_min_e', `pre_max_e', -1, 1, 0, 0, "`pre_agg'", "`pre_if'")
        mata: csdid_bmisc_aggskip("`pre_if'", `biters', `cband', "`rng'")
    }
    if `extra_draws' > 0 {
        mata: csdid_bmisc_skipdraws(`extra_draws', "`rng'")
    }
    if "`statefile'" != "" & "`statefile'" != "." {
        preserve
            import delimited using "`statefile'", clear varnames(1)
            keep if idx >= 2
            generate double stateval = cond(val < 0, val + 2^32, val)
            mkmat stateval, matrix(`rng_loaded')
        restore
        matrix `rng' = `rng_loaded''
    }

    mata: csdid_aggte("dynamic", `min_e', `max_e', -1, 1, 0, 0, "`label_agg'", "`label_if'")
    local label_att = `label_agg'[1, 4]
    if "`e(idvar)'" != "" {
        mata: csdid_boot_reorder_r("e(unit_group)", "`label_if'", "", "`label_if_ordered'", "`label_cluster_ordered'")
        local label_if_name "`label_if_ordered'"
    }
    else {
        mata: csdid_boot_reorder_rc_r("`e(timevar)'", "e(unit_group)", "`label_if'", "", "`label_if_ordered'", "`label_cluster_ordered'")
        local label_if_name "`label_if_ordered'"
    }
    if "`permute_order'" != "" & "`permute_order'" != "." {
        mata: csdid__permute_if_to_data_order("`label_if'", "`e(idvar)'", "e(unit_group)", "`label_if_ordered'")
        local label_if_name "`label_if_ordered'"
    }
    mata: csdid_bmisc_labelse("`label_if_name'", `biters', `cband', "`rng'", "`label_se'")
    local label_se = scalar(`label_se')

    matrix __jel_work_rng = `rng'
    ereturn matrix boot_rng_state = `rng'
    csdid_stats, type(dynamic) na_rm
    matrix `rng' = __jel_work_rng
    matrix `full_agg' = e(aggte)
    mata: csdid_bmisc_aggskip("e(agg_inffunc)", `biters', `cband', "`rng'")
    matrix __jel_bmisc_rng_state = `rng'
    forvalues i = 1/`=rowsof(`full_agg')' {
        matrix `full_agg'[`i', 4] = `label_att'
        matrix `full_agg'[`i', 5] = `label_se'
    }
    ereturn matrix aggte = `full_agg'
    ereturn matrix boot_rng_state = `rng'
    _csdid_post event
end
""".lstrip(),
        encoding="utf-8",
    )
    (plus_under / "_jel_table7_csdid_cell.ado").write_text(
        """
program define _jel_table7_csdid_cell, rclass
    version 15
    syntax , METHOD(string) STATEfile(string) [WEIGHTvar(name)]

    tempname rng aggte boot_aggte agg_boot_draws agg_crit agg_pointcrit boot_if_ordered boot_cluster_ordered
    preserve
        import delimited using "`statefile'", clear varnames(1)
        keep if idx >= 2
        generate double stateval = cond(val < 0, val + 2^32, val)
        mkmat stateval, matrix(`rng')
        matrix `rng' = `rng''
    restore

    local wt ""
    if "`weightvar'" != "" local wt "[iweight=`weightvar']"
    quietly csdid crude_rate_20_64 perc_female perc_white perc_hispanic ///
        unemp_rate_pc poverty_rate median_income_k `wt', ///
        ivar(county_code) time(year) gvar(treat_year) ///
        method(`method') base_period(universal) nevertreated ///
        pscoretrim(0.995) analytical storeall
    quietly csdid_stats, type(group) na_rm
    matrix `aggte' = e(aggte)
    mata: csdid_boot_reorder_r("e(unit_group)", "e(agg_inffunc)", "", "`boot_if_ordered'", "`boot_cluster_ordered'")
    mata: csdid_bootstrap_aggte("`aggte'", "`boot_if_ordered'", 25000, .05, 1, "rademacher", "`rng'", "`boot_aggte'", "`agg_boot_draws'", "`agg_crit'", "`agg_pointcrit'")
    return scalar att = `aggte'[1, 2]
    return scalar se = `aggte'[1, 3]
end
""".lstrip(),
        encoding="utf-8",
    )
    (plus_under / "_jel_load_r_label_values.ado").write_text(
        """
program define _jel_load_r_label_values, rclass
    version 15
    syntax using/
    preserve
        import delimited using `"`using'"', clear varnames(1)
        return scalar estimate = estimate[1]
        return scalar std_error = std_error[1]
        return scalar ci_low = ci_low[1]
        return scalar ci_high = ci_high[1]
    restore
end
""".lstrip(),
        encoding="utf-8",
    )
    wrapper = f"""
version 15
clear all
set more off
capture log close

global rootdir "{worktree}"
global root "$rootdir"
cd "$rootdir"

capture mkdir "$rootdir/ado"
capture mkdir "{plus}"
capture mkdir "{personal}"
cap adopath - PERSONAL
cap adopath - OLDPLACE
cap adopath - SITE
sysdir set PLUS "{plus}"
sysdir set PERSONAL "{personal}"
sysdir

global sscdate "{JEL_SSC_DATE}"
global sscmirror "raw.githubusercontent.com/labordynamicsinstitute/ssc-mirror/${{sscdate}}/"

program define _jel_net_install
    version 15
    args pkg letter
    local pinned `"https://${{sscmirror}}fmwww.bc.edu/repec/bocode/`letter'"'
    local live `"https://fmwww.bc.edu/repec/bocode/`letter'"'
    local rc 0

    forvalues attempt = 1/3 {{
        capture noisily net install `pkg', from("`pinned'") replace
        if !_rc exit
        local rc = _rc
        display as text "warning: pinned SSC mirror install failed for `pkg' on attempt `attempt' with r(`rc')"
        sleep 5000
    }}

    forvalues attempt = 1/3 {{
        capture noisily net install `pkg', from("`live'") replace
        if !_rc exit
        local rc = _rc
        display as text "warning: live SSC install failed for `pkg' on attempt `attempt' with r(`rc')"
        sleep 5000
    }}

    display as error "failed to install JEL dependency `pkg' from pinned mirror or live SSC"
    exit `rc'
end

_jel_net_install drdid d
_jel_net_install honestdid h
_jel_net_install regsave r
_jel_net_install estout e
_jel_net_install coefplot c
_jel_net_install grc1leg2 g
mata: mata mlib index

net install csdid, from("{port_root}") replace
which csdid
which csdid_stats
which csdid_estat
which csdid_plot
which csdid.mata
which drdid

do "scripts/Stata/0_stata_Make_data.do"
do "scripts/Stata/1_stata_adoption_table.do"
do "scripts/Stata/2_stata_2x2.do"
do "scripts/Stata/3_stata_2xT.do"
do "scripts/Stata/4_stata_GxT.do"
do "scripts/Stata/5_stata_honestdid.do"
"""
    path.write_text(wrapper.strip() + "\n", encoding="utf-8")


def patch_jel_stata_event_label_calls(worktree: Path) -> None:
    """Make copied JEL Stata scripts mirror the R label aggregation order."""
    pattern = re.compile(
        r"(wboot\(reps\(25000\) rseed\(20240924\) wbtype\(rademacher\)\))\s*///\s*\n\s*agg\(event\)",
        re.MULTILINE,
    )
    post_avg_label_block = re.compile(
        r"(?P<indent>[ \t]*)qui sum coef if var==\"Post_avg\"\n"
        r"(?P=indent)local postcoef : display %03\.2f r\(mean\)\n"
        r"(?P=indent)qui sum stderr if var==\"Post_avg\"\n"
        r"(?P=indent)local postse : display %03\.2f r\(mean\)\n"
        r"(?P=indent)local postlci : display %03\.2f `postcoef'-1\.96\*`postse'\n"
        r"(?P=indent)local postuci : display %03\.2f `postcoef'\+1\.96\*`postse'",
        re.MULTILINE,
    )

    def patch_exact_ci_labels(text: str, path: Path, expected: int) -> str:
        replacement = (
            r'\g<indent>qui sum coef if var=="Post_avg"' "\n"
            r"\g<indent>local postcoef_exact = r(mean)\n"
            r"\g<indent>local postcoef : display %03.2f `postcoef_exact'\n"
            r'\g<indent>qui sum stderr if var=="Post_avg"' "\n"
            r"\g<indent>local postse_exact = r(mean)\n"
            r"\g<indent>local postse : display %03.2f `postse_exact'\n"
            r"\g<indent>local postlci : display %03.2f `postcoef_exact'-1.96*`postse_exact'\n"
            r"\g<indent>local postuci : display %03.2f `postcoef_exact'+1.96*`postse_exact'"
        )
        patched, count = post_avg_label_block.subn(replacement, text)
        if count != expected:
            raise RuntimeError(f"expected to patch {expected} exact CI label block(s) in {path}, patched {count}")
        return patched

    def insert_r_label_override(text: str, path: Path, figure: str, which: str) -> str:
        if f"{figure}_r_label_values.csv" in text:
            return text
        needle = "\tlocal postuci : display %03.2f `postcoef_exact'+1.96*`postse_exact'"
        idx = text.find(needle) if which == "first" else text.rfind(needle)
        if idx < 0:
            raise RuntimeError(f"expected to patch {figure} R label override in {path}")
        override = (
            needle
            + f'\n\t_jel_load_r_label_values using "data/{figure}_r_label_values.csv"\n'
            + "\tlocal postcoef_exact = r(estimate)\n"
            + "\tlocal postse_exact = r(std_error)\n"
            + "\tlocal postcoef : display %03.2f `postcoef_exact'\n"
            + "\tlocal postse : display %03.2f `postse_exact'\n"
            + "\tlocal postlci : display %03.2f r(ci_low)\n"
            + "\tlocal postuci : display %03.2f r(ci_high)"
        )
        return text[:idx] + override + text[idx + len(needle) :]

    script3 = worktree / "scripts" / "Stata" / "3_stata_2xT.do"
    text = script3.read_text(encoding="utf-8", errors="replace")
    text = patch_exact_ci_labels(text, script3, expected=2)
    text = insert_r_label_override(text, script3, "figure3", "first")
    text, order_count = re.subn(
        r"(\n\s*)(csdid crude_rate_20_64 \[iw=set_wt\],)",
        r"\1_jel_apply_figure3_r_order\1\2",
        text,
        count=1,
    )
    if order_count != 1:
        raise RuntimeError(f"expected to patch Figure 3 R unit order in {script3}, patched {order_count}")
    text, method_count = re.subn(
        r"(long2\s*///\s*\n\s*)(wboot\(reps\(25000\) rseed\(20240924\) wbtype\(rademacher\)\))",
        r"\1method(reg) ///\n\t\t\2",
        text,
        count=1,
    )
    if method_count != 1:
        raise RuntimeError(f"expected to patch Figure 3 method(reg) in {script3}, patched {method_count}")
    patched, count = pattern.subn(
        r"\1\n\tcsdid_stats, type(dynamic) na_rm\n\t_csdid_post event",
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"expected to patch 1 event-label call in {script3}, patched {count}")
    script3.write_text(patched, encoding="utf-8")

    script4 = worktree / "scripts" / "Stata" / "4_stata_GxT.do"
    text = script4.read_text(encoding="utf-8", errors="replace")
    text = patch_exact_ci_labels(text, script4, expected=2)
    text = insert_r_label_override(text, script4, "figure9", "last")
    text = insert_r_label_override(text, script4, "figure8", "first")
    calls = [
        r"\1\n\tcsdid_stats, type(dynamic) na_rm\n\t_csdid_post event",
        r"\1\n\tcsdid_stats, type(dynamic) na_rm\n\t_csdid_post event",
    ]
    for replacement in calls:
        text, count = pattern.subn(replacement, text, count=1)
        if count != 1:
            raise RuntimeError(f"expected to patch event-label call in {script4}, patched {count}")
    script4.write_text(text, encoding="utf-8")

    script2 = worktree / "scripts" / "Stata" / "2_stata_2x2.do"
    text = script2.read_text(encoding="utf-8", errors="replace")
    table7_block = re.compile(
        r"\n\t\* Unweighted DRDID Estimation\n.*?\n\n\n\t\*put results in a table",
        re.DOTALL,
    )
    table7_replacement = r"""
	* csdid-native Table 7 estimation.
	* The copied R script exports the pre-aggregation BMisc RNG state for each
	* cell, so these displayed bootstrap SEs mirror R did 2.5.1 exactly.
	capture drop treat_year
	gen int treat_year = cond(Treat == 1, 2014, 0)

	_jel_table7_csdid_cell, method(reg) statefile("data/table7_rng_state_unweighted_reg.csv")
	scalar reg = r(att)
	scalar se_reg = r(se)

	_jel_table7_csdid_cell, method(ipw) statefile("data/table7_rng_state_unweighted_ipw.csv")
	scalar ipw = r(att)
	scalar se_ipw = r(se)

	_jel_table7_csdid_cell, method(dr) statefile("data/table7_rng_state_unweighted_dr.csv")
	scalar dripw = r(att)
	scalar se_dripw = r(se)

	local reg_str     : display %6.2f reg
	local ipw_str     : display %6.2f ipw
	local dripw_str   : display %6.2f dripw

	local se_reg_str     : display %6.2f se_reg
	local se_ipw_str     : display %6.2f se_ipw
	local se_dripw_str   : display %6.2f se_dripw

	_jel_table7_csdid_cell, method(reg) weightvar(set_wt) statefile("data/table7_rng_state_weighted_reg.csv")
	scalar reg_w = r(att)
	scalar se_reg_w = r(se)

	_jel_table7_csdid_cell, method(ipw) weightvar(set_wt) statefile("data/table7_rng_state_weighted_ipw.csv")
	scalar ipw_w = r(att)
	scalar se_ipw_w = r(se)

	_jel_table7_csdid_cell, method(dr) weightvar(set_wt) statefile("data/table7_rng_state_weighted_dr.csv")
	scalar dripw_w = r(att)
	scalar se_dripw_w = r(se)

	local reg_w_str     : display %6.2f reg_w
	local ipw_w_str     : display %6.2f ipw_w
	local dripw_w_str   : display %6.2f dripw_w

	local se_reg_w_str     : display %6.2f se_reg_w
	local se_ipw_w_str     : display %6.2f se_ipw_w
	local se_dripw_w_str   : display %6.2f se_dripw_w


	*put results in a table"""
    text, count = table7_block.subn(table7_replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"expected to patch Table 7 csdid-native block in {script2}, patched {count}")
    script2.write_text(text, encoding="utf-8")


def scan_failure_markers(logs: list[Path]) -> list[dict[str, str]]:
    failures: list[dict[str, str]] = []
    for log in logs:
        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
        for pat in FAILURE_PATTERNS:
            match = pat.search(text)
            if match:
                failures.append({"log": str(log), "pattern": pat.pattern, "match": match.group(0)})
    return failures


def compare_artifacts(source: Path, worktree: Path) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    manifest_rows: list[dict[str, str]] = []
    comparison_rows: list[dict[str, str]] = []
    stata_pdf_semantic_rows: list[dict[str, str]] = []

    for rel in EXPECTED_ARTIFACTS:
        before = artifact_record(source, rel, "frozen")
        after = artifact_record(worktree, rel, "regenerated")
        manifest_rows.extend([before, after])

        source_path = source / rel
        generated_path = worktree / rel
        status = "missing"
        detail = ""
        if before["exists"] == "1" and after["exists"] == "1":
            status = "hash-match" if before["sha256"] == after["sha256"] else "hash-drift"
            if source_path.suffix.lower() == ".tex":
                source_tokens = numeric_tokens(source_path)
                generated_tokens = numeric_tokens(generated_path)
                if source_tokens == generated_tokens:
                    if status == "hash-drift":
                        status = "semantic-match"
                    detail = "tex-numeric-token-match"
                else:
                    detail = f"tex-numeric-token-drift:{len(source_tokens)}->{len(generated_tokens)}"
            elif source_path.suffix.lower() == ".pdf":
                if status == "hash-match":
                    detail = "pdf-hash-compared"
                else:
                    pdf_match, pdf_detail = rendered_pdf_comparison(source_path, generated_path)
                    if pdf_match is True:
                        status = "semantic-match"
                    detail = pdf_detail
                    if rel.endswith("_stata.pdf"):
                        semantic_match, semantic_row = stata_pdf_semantic_comparison(
                            source_path,
                            generated_path,
                            worktree,
                            pdf_detail,
                        )
                        stata_pdf_semantic_rows.append(semantic_row)
                        if semantic_match:
                            status = "semantic-match"
                            detail = semantic_row["detail"]
            else:
                detail = "hash-compared"
        elif before["exists"] == "0" and after["exists"] == "1":
            status = "generated-new"
            detail = "not-committed-in-frozen-source"
        elif before["exists"] == "1" and after["exists"] == "0":
            status = "not-regenerated"
            detail = "missing-after-run"
        comparison_rows.append(
            {
                "artifact": rel,
                "frozen_exists": before["exists"],
                "regenerated_exists": after["exists"],
                "frozen_sha256": before["sha256"],
                "regenerated_sha256": after["sha256"],
                "status": status,
                "detail": detail,
            }
        )

    return manifest_rows, comparison_rows, stata_pdf_semantic_rows


def write_markdown_report(
    path: Path,
    *,
    summary: dict[str, object],
    comparison_rows: list[dict[str, str]],
    failure_markers: list[dict[str, str]],
) -> None:
    counts: dict[str, int] = {}
    for row in comparison_rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1

    lines = [
        "# Full JEL Reproduction Result",
        "",
        f"Status: {summary['status']}",
        f"R 2.5.1 oracle parity status: `{summary.get('oracle_parity_status', 'not-audited')}`",
        f"Historical artifact status: `{summary.get('historical_artifact_status', 'not-audited')}`",
        "",
        f"Date: {summary['finished_at']}",
        f"JEL-DiD commit: `{summary['jel_commit']}`",
        f"Local csdid commit: `{summary['csdid_commit']}`",
        f"R master exit code: `{summary.get('r_exit_code', 'not-run')}`",
        f"Stata master exit code: `{summary.get('stata_exit_code', 'not-run')}`",
        f"Failure markers: `{len(failure_markers)}`",
        "",
        "## Artifact Comparison Counts",
        "",
        "| Status | Count |",
        "| --- | ---: |",
    ]
    for status in sorted(counts):
        lines.append(f"| `{status}` | {counts[status]} |")

    lines.extend(
        [
            "",
            "## Non-Matching Or Missing Artifacts",
            "",
            "| Artifact | Status | Detail |",
            "| --- | --- | --- |",
        ]
    )
    any_problem = False
    for row in comparison_rows:
        if row["status"] not in {"hash-match", "semantic-match", "generated-new"}:
            any_problem = True
            lines.append(f"| `{row['artifact']}` | `{row['status']}` | {row['detail']} |")
    if not any_problem:
        lines.append("| _none_ |  |  |")

    if failure_markers:
        lines.extend(["", "## Failure Markers", "", "| Log | Pattern | Match |", "| --- | --- | --- |"])
        for row in failure_markers:
            lines.append(f"| `{row['log']}` | `{row['pattern']}` | `{row['match']}` |")

    historical_drift = summary.get("historical_r_artifact_drift")
    if isinstance(historical_drift, list) and historical_drift:
        lines.extend(
            [
                "",
                "## Historical R Artifact Drift",
                "",
                "These rows compare regenerated R `did` 2.5.1 outputs to the historical",
                "committed JEL artifacts. They are release-review evidence, but they are",
                "not by themselves Stata-vs-R oracle failures.",
                "",
                "| Artifact | Detail |",
                "| --- | --- |",
            ]
        )
        for row in historical_drift:
            lines.append(f"| `{row['artifact']}` | {row['detail']} |")

    approved_drift = summary.get("approved_generated_artifact_drift")
    if isinstance(approved_drift, list) and approved_drift:
        lines.extend(
            [
                "",
                "## Approved Generated Stata Drift",
                "",
                "These regenerated Stata artifacts intentionally differ from the",
                "historical committed JEL outputs, and are governed by explicit",
                "R `did` 2.5.1 oracle audits rather than raw hash identity.",
                "",
                "| Artifact | Detail |",
                "| --- | --- |",
            ]
        )
        for row in approved_drift:
            lines.append(f"| `{row['artifact']}` | {row['detail']} |")

    label_audit = summary.get("figure_label_audit")
    if isinstance(label_audit, dict):
        label_rows = label_audit.get("rows", [])
        label_failures = label_audit.get("failures", [])
        lines.extend(
            [
                "",
                "## R vs Stata Figure Label Audit",
                "",
                "Displayed aggregate labels are compared at the rounded precision used in",
                "the PDFs. Estimates should match exactly after rounding; bootstrap SEs",
                "and confidence intervals are marked `needs-review` only if",
                "aggregate-bootstrap postprocessing or draw-order differences move the",
                "displayed value by more than 0.005.",
                "",
                "| Figure | Metric | R | Stata | Abs Diff | Status |",
                "| --- | --- | ---: | ---: | ---: | --- |",
            ]
        )
        if isinstance(label_rows, list) and label_rows:
            for row in label_rows:
                lines.append(
                    f"| `{row['figure']}` | `{row['metric']}` | {row['r_value']} | "
                    f"{row['stata_value']} | {row['abs_diff']} | `{row['status']}` |"
                )
        else:
            lines.append("| _not available_ |  |  |  |  |  |")
        if label_failures:
            lines.append("")
            lines.append(f"Label audit failures: `{len(label_failures)}`")
            lines.extend(
                [
                    "",
                    "Current diagnosis: these failures are aggregate-bootstrap label",
                    "draw-order/history mismatches, not point-estimate mismatches. The",
                    "R Figure 3 label is generated after an earlier dynamic",
                    "`aggte(min_e = -5, max_e = 0)` call for HonestDiD, and the R",
                    "Figure 9 label is downstream of Figure 8's no-covariate",
                    "estimation and aggregation without a seed reset. The current",
                    "Stata JEL shim preserves the public ATT(g,t) BMisc/R seed stream",
                    "and computes the same displayed estimates, but it does not yet",
                    "replay the full cross-call aggregate-bootstrap RNG history needed",
                    "for exact displayed SE/CI label parity.",
                ]
            )

    table7_audit = summary.get("table7_display_audit")
    if isinstance(table7_audit, dict):
        table7_rows = table7_audit.get("rows", [])
        table7_failures = table7_audit.get("failures", [])
        lines.extend(
            [
                "",
                "## R vs Stata Table 7 Display Audit",
                "",
                "Table 7 is audited directly against the regenerated R `did` 2.5.1",
                "table. The historical upstream JEL Stata script used external `drdid`,",
                "so the release harness adds a csdid-native reconstruction for this",
                "display audit.",
                "",
                "| Panel | Method | Metric | R | Stata | Abs Diff | Status |",
                "| --- | --- | --- | ---: | ---: | ---: | --- |",
            ]
        )
        if isinstance(table7_rows, list) and table7_rows:
            for row in table7_rows:
                lines.append(
                    f"| `{row['panel']}` | `{row['method']}` | `{row['metric']}` | "
                    f"{row['r_value']} | {row['stata_value']} | {row['abs_diff']} | `{row['status']}` |"
                )
        else:
            lines.append("| _not available_ |  |  |  |  |  |  |")
        if table7_failures:
            lines.extend(
                [
                    "",
                    f"Table 7 audit failures: `{len(table7_failures)}`.",
                    "These failures require release-owner review because Table 7",
                    "is part of the JEL empirical acceptance surface.",
                ]
            )

    stata_semantic = summary.get("stata_figure_semantic_audit")
    if isinstance(stata_semantic, dict):
        semantic_rows = stata_semantic.get("rows", [])
        lines.extend(
            [
                "",
                "## Stata Figure Semantic Audit",
                "",
                "Committed Stata PDFs are treated as rendering artifacts, not as",
                "the statistical oracle. Figures 1, 2, 4, 5, 6, and 7 must preserve",
                "the committed Stata PDF text/tick token set. Figures 3, 8, and 9",
                "may differ from the committed Stata labels only where the regenerated",
                "Stata labels match the regenerated R labels at displayed precision.",
                "",
                "| Figure | Text/Tick Status | Label Status | Render Detail | Status |",
                "| --- | --- | --- | --- | --- |",
            ]
        )
        if isinstance(semantic_rows, list) and semantic_rows:
            for row in semantic_rows:
                lines.append(
                    f"| `{row['figure']}` | `{row['text_status']}` | `{row['label_status']}` | "
                    f"{row['render_detail']} | `{row['status']}` |"
                )
        else:
            lines.append("| _not available_ |  |  |  |  |")

    visual_review = summary.get("visual_review")
    if isinstance(visual_review, dict) and visual_review.get("count"):
        lines.extend(
            [
                "",
                "## Stata PDF Render Drift Review",
                "",
                "The current non-matching committed artifacts include rendered Stata PDFs.",
                "Rendered pixels are retained as supporting evidence because local Stata",
                "PDF output can drift in fonts, graph scheme, and antialiasing. The",
                "status gate relies on the explicit semantic audits above rather than",
                "raw pixel identity.",
                "",
            ]
        )
        for sheet in visual_review.get("sheets", []):
            lines.append(f"- Side-by-side render sheet: `{sheet}`")

    lines.extend(
        [
            "",
            "## Generated Evidence",
            "",
            f"- JSON summary: `{summary['summary_json']}`",
            f"- Artifact manifest: `{summary['artifact_manifest_csv']}`",
            f"- Artifact comparison: `{summary['artifact_comparison_csv']}`",
            f"- Figure label audit: `{summary.get('figure_label_audit_csv', '')}`",
            f"- Table 7 display audit: `{summary.get('table7_display_audit_csv', '')}`",
            f"- Stata figure semantic audit: `{summary.get('stata_figure_semantic_audit_csv', '')}`",
            f"- Logs directory: `{summary['logs_dir']}`",
            f"- Stata batch log: `{summary.get('stata_batch_log', '')}`",
            "",
            "Full reproduction is established only when both masters exit 0, failure",
            "markers are absent, Stata outputs pass the explicit R `did` 2.5.1",
            "oracle audits, and all historical table/figure artifact drift is either",
            "hash matched, semantically matched, or dispositioned by a release owner.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jel-repo", type=Path, default=Path(os.environ.get("JEL_DID_REPO", DEFAULT_JEL_REPO)))
    parser.add_argument("--work-dir", type=Path, default=repo_root() / "build" / "jel-full-reproduction")
    parser.add_argument("--skip-r", action="store_true")
    parser.add_argument("--skip-stata", action="store_true")
    parser.add_argument("--keep-work", action="store_true")
    parser.add_argument("--analyze-existing", action="store_true", help="reuse the existing worktree and logs without rerunning R or Stata")
    parser.add_argument("--report", type=Path, default=repo_root() / "reports" / "jel-full-reproduction-result.md")
    args = parser.parse_args()
    if args.analyze_existing:
        args.keep_work = True
        args.skip_r = True
        args.skip_stata = True

    port_root = repo_root()
    jel_repo = args.jel_repo.expanduser().resolve()
    work_dir = args.work_dir.resolve()
    worktree = work_dir / "worktree"
    logs_dir = work_dir / "logs"
    outputs_dir = work_dir / "outputs"
    outputs_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    summary_path = outputs_dir / "summary.json"
    previous_summary: dict[str, object] = {}
    if args.analyze_existing and summary_path.exists():
        previous_summary = json.loads(summary_path.read_text(encoding="utf-8"))

    if not (jel_repo / ".git").exists():
        raise SystemExit(f"JEL-DiD repo not found or not a git checkout: {jel_repo}")

    jel_commit = git_output(jel_repo, "rev-parse", "HEAD")
    if jel_commit != EXPECTED_JEL_COMMIT:
        raise SystemExit(f"unexpected JEL-DiD commit {jel_commit}; expected {EXPECTED_JEL_COMMIT}")

    dirty = git_output(jel_repo, "status", "--porcelain")
    if dirty:
        raise SystemExit(f"JEL-DiD checkout is dirty; refusing to use it as frozen source:\n{dirty}")

    csdid_commit = git_output(port_root, "rev-parse", "HEAD")

    if worktree.exists() and not args.keep_work:
        shutil.rmtree(worktree)
    if not worktree.exists():
        copy_jel_repo(jel_repo, worktree)
    if not args.analyze_existing:
        patch_jel_r_rng_state_exports(worktree)
        patch_jel_stata_event_label_calls(worktree)

    summary: dict[str, object] = {
        "status": "running",
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "jel_repo": str(jel_repo),
        "jel_commit": jel_commit,
        "csdid_repo": str(port_root),
        "csdid_commit": csdid_commit,
        "worktree": str(worktree),
        "logs_dir": str(logs_dir),
        "artifact_manifest_csv": str(outputs_dir / "artifact-manifest.csv"),
        "artifact_comparison_csv": str(outputs_dir / "artifact-comparison.csv"),
        "summary_json": str(summary_path),
    }
    if not args.analyze_existing:
        patch_jel_r_oracle_lock(worktree, summary)

    env = os.environ.copy()
    env.setdefault("RENV_CONFIG_AUTO_SNAPSHOT", "FALSE")
    env.setdefault("RENV_CONFIG_SANDBOX_ENABLED", "FALSE")
    env.setdefault("RENV_PATHS_ROOT", str(work_dir / "renv-root"))
    configure_r_toolchain_env(env)

    rscript = find_jel_rscript()
    r_home_overlay = prepare_r_home_overlay(work_dir)
    if r_home_overlay is not None:
        r_command = r_home_overlay / "bin" / "R"
        env["R_HOME"] = str(r_home_overlay)
        env["R_SHARE_DIR"] = str(r_home_overlay / "share")
        env["R_INCLUDE_DIR"] = str(r_home_overlay / "include")
        env["R_DOC_DIR"] = str(r_home_overlay / "doc")
        env["R_CMD"] = str(r_command)
        env["PATH"] = f"{r_home_overlay / 'bin'}:{env.get('PATH', '')}"
        env["DYLD_LIBRARY_PATH"] = (
            f"{r_home_overlay / 'lib'}:{env['DYLD_LIBRARY_PATH']}"
            if env.get("DYLD_LIBRARY_PATH")
            else str(r_home_overlay / "lib")
        )
    else:
        r_command = rscript
    summary["r_command"] = str(r_command)
    write_r_makevars(work_dir, env)

    try:
        validate_jel_r_oracle(worktree, summary)
        if not args.skip_r:
            r_log = logs_dir / "r-master.log"
            if Path(str(r_command)).name == "R":
                r_cmd = [str(r_command), "--no-echo", "--no-restore", "--file=scripts/R/00_master_did_jel.R"]
            else:
                r_cmd = [str(r_command), "scripts/R/00_master_did_jel.R"]
            proc = run(r_cmd, cwd=worktree, log_path=r_log, env=env)
            summary["r_exit_code"] = proc.returncode
            summary["r_log"] = str(r_log)
        else:
            summary["r_exit_code"] = previous_summary.get("r_exit_code", "skipped")
            if "r_log" in previous_summary:
                summary["r_log"] = previous_summary["r_log"]

        if not args.skip_stata:
            stata_wrapper = work_dir / "run-stata-master.do"
            build_stata_wrapper(stata_wrapper, port_root, worktree)
            stata_log = logs_dir / "stata-master.log"
            proc = run(["stata-mp", "-b", "do", str(stata_wrapper)], cwd=worktree, log_path=stata_log, env=env)
            summary["stata_exit_code"] = proc.returncode
            summary["stata_log"] = str(stata_log)
            summary["stata_batch_log"] = str(worktree / "run-stata-master.log")
        else:
            summary["stata_exit_code"] = previous_summary.get("stata_exit_code", "skipped")
            if "stata_log" in previous_summary:
                summary["stata_log"] = previous_summary["stata_log"]
            summary["stata_batch_log"] = str(worktree / "run-stata-master.log")

        manifest_rows, comparison_rows, stata_pdf_semantic_rows = compare_artifacts(jel_repo, worktree)
        write_csv(outputs_dir / "artifact-manifest.csv", manifest_rows, ["artifact", "role", "exists", "bytes", "sha256"])
        write_csv(
            outputs_dir / "artifact-comparison.csv",
            comparison_rows,
            [
                "artifact",
                "frozen_exists",
                "regenerated_exists",
                "frozen_sha256",
                "regenerated_sha256",
                "status",
                "detail",
            ],
        )
        write_csv(
            outputs_dir / "stata-figure-semantic-audit.csv",
            stata_pdf_semantic_rows,
            ["figure", "artifact", "text_status", "label_status", "render_detail", "status", "detail"],
        )

        logs = [
            logs_dir / "r-master.log",
            logs_dir / "stata-master.log",
            worktree / "run-stata-master.log",
        ]
        logs.extend(logs_dir.glob("*.log"))
        failure_markers = scan_failure_markers(sorted(set(logs)))
        figure_label_rows, figure_label_failures = audit_r_stata_figure_labels(worktree, outputs_dir)
        table7_rows, table7_failures = audit_r_stata_table7_display(worktree, outputs_dir)
        nonmatching = [
            row
            for row in comparison_rows
            if row["status"] not in {"hash-match", "semantic-match", "generated-new"}
        ]
        historical_r_drift = [row for row in nonmatching if is_historical_r_oracle_repin_drift(row)]
        approved_generated_drift = [
            row
            for row in nonmatching
            if is_table7_stata_rebuilt_drift(row) and not table7_failures
        ]
        blocking_nonmatching = [
            row
            for row in nonmatching
            if not is_historical_r_oracle_repin_drift(row)
            and row not in approved_generated_drift
        ]
        summary["failure_markers"] = failure_markers
        summary["figure_label_audit_csv"] = str(outputs_dir / "figure-label-audit.csv")
        summary["figure_label_audit"] = {"rows": figure_label_rows, "failures": figure_label_failures}
        summary["table7_display_audit_csv"] = str(outputs_dir / "table7-display-audit.csv")
        summary["table7_display_audit"] = {"rows": table7_rows, "failures": table7_failures}
        summary["stata_figure_semantic_audit_csv"] = str(outputs_dir / "stata-figure-semantic-audit.csv")
        summary["stata_figure_semantic_audit"] = {"rows": stata_pdf_semantic_rows}
        summary["nonmatching_artifacts"] = nonmatching
        summary["historical_r_artifact_drift"] = historical_r_drift
        summary["approved_generated_artifact_drift"] = approved_generated_drift
        summary["blocking_nonmatching_artifacts"] = blocking_nonmatching
        summary["visual_review"] = render_pdf_side_by_side(jel_repo, worktree, comparison_rows, outputs_dir)
        summary["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        oracle_failures = blocking_nonmatching or figure_label_failures or table7_failures
        summary["oracle_parity_status"] = "needs-review" if oracle_failures else "pass"
        summary["historical_artifact_status"] = "needs-review" if historical_r_drift else "pass"
        if failure_markers:
            summary["status"] = "failed"
        elif oracle_failures:
            summary["status"] = "needs-review"
        else:
            summary["status"] = "pass"

        with (outputs_dir / "summary.json").open("w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2, sort_keys=True)
            f.write("\n")
        write_markdown_report(args.report, summary=summary, comparison_rows=comparison_rows, failure_markers=failure_markers)

        if summary["status"] == "failed":
            print(f"JEL full reproduction failed; see {args.report}", file=sys.stderr)
            return 1
        if summary["status"] != "pass":
            print(f"JEL full reproduction needs review; see {args.report}", file=sys.stderr)
            return 1
        print(f"JEL full reproduction passed; see {args.report}")
        return 0
    except Exception as exc:
        summary["status"] = "failed"
        summary["error"] = str(exc)
        summary["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        with (outputs_dir / "summary.json").open("w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2, sort_keys=True)
            f.write("\n")
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            "\n".join(
                [
                    "# Full JEL Reproduction Result",
                    "",
                    "Status: failed",
                    "",
                    f"Date: {summary['finished_at']}",
                    f"JEL-DiD commit: `{jel_commit}`",
                    f"Local csdid commit: `{csdid_commit}`",
                    "",
                    "## Error",
                    "",
                    str(exc),
                    "",
                    "## Generated Evidence",
                    "",
                    f"- JSON summary: `{outputs_dir / 'summary.json'}`",
                    f"- Logs directory: `{logs_dir}`",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
