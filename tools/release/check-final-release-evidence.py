#!/usr/bin/env python3
"""Validate declared final-release evidence against a candidate and bundle.

This authenticates inventory and attribution, not reviewer identity, execution
logs, or artifact contents. Independent review remains a release requirement.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime
import hashlib
import math
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
REQUIRED_FILES = [
    "stata-mata-review-signoff.md", "econometrics-review-signoff.md",
    "macos-platform.csv", "windows-platform.csv", "linux-platform.csv",
    "release-owner-decision.md",
]
PLATFORM_COLUMNS = {
    "date", "stata_version", "edition", "os", "machine_type", "byteorder",
    "release_gates_status", "repository_commit", "production_digest",
}
PLACEHOLDERS = {"", "tbd", "todo", "n/a", "na", "pending", "replace me",
                "unknown", "unverified", "not run", "not-run"}
COMMIT = re.compile(r"[0-9a-f]{40}", re.I)
SHA256 = re.compile(r"[0-9a-f]{64}", re.I)
VERSION = re.compile(r"[1-9]\d*(?:\.\d+)?")
EDITIONS = {"MP", "SE", "BE", "IC"}


def filled(value: str) -> bool:
    return value.strip().lower().strip("<>[] ") not in PLACEHOLDERS


def valid_date(value: str) -> bool:
    for pattern in ("%Y-%m-%d", "%d %b %Y"):
        try:
            datetime.strptime(value, pattern)
            return True
        except ValueError:
            pass
    return False


def version_number(value: str) -> float:
    number = float(value) if VERSION.fullmatch(value) else 0
    return number if math.isfinite(number) else 0


def fields(text: str, required: list[str], name: str, errors: list[str]) -> dict[str, str]:
    result = {}
    for field in required:
        values = [line.split(":", 1)[1].strip() for line in text.splitlines()
                  if line.strip().lower().startswith(field.lower() + ":")]
        if len(values) != 1:
            errors.append(f"{name} must contain exactly one '{field}:' field")
        value = values[0] if values else ""
        if not filled(value):
            errors.append(f"{name} has unfilled field: {field}")
        result[field] = value
    return result


def validate_signoff(path: Path, candidate: str, bundle_sha: str, errors: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    owner = path.name == "release-owner-decision.md"
    required = ["Release owner" if owner else "Reviewer", "Date", "Repository commit",
                "Final release approved", "Blocking findings remaining"]
    required += ["Bundle SHA256"] if owner else ["Stata version/edition", "Operating system"]
    if path.name == "econometrics-review-signoff.md":
        required.append("R did source")
    record = fields(text, required, path.name, errors)
    if not valid_date(record["Date"]):
        errors.append(f"{path.name} has invalid Date; use YYYY-MM-DD or DD Mon YYYY")
    if record["Repository commit"].lower() != candidate:
        errors.append(f"{path.name} Repository commit must equal candidate {candidate}")
    if record["Final release approved"].lower() != "yes":
        errors.append(f"{path.name} must set 'Final release approved: yes'")
    if record["Blocking findings remaining"].lower() != "none":
        errors.append(f"{path.name} must set 'Blocking findings remaining: none'")
    if owner:
        if record["Bundle SHA256"].lower() != bundle_sha:
            errors.append(f"{path.name} Bundle SHA256 must match the supplied bundle: {bundle_sha}")
    else:
        version = re.fullmatch(r"(?:Stata(?:Now)?\s+)?([1-9]\d*(?:\.\d+)?)\s*[/, ]\s*(MP|SE|BE|IC)",
                               record["Stata version/edition"], re.I)
        if not version or version_number(version[1]) < 14:
            errors.append(f"{path.name} needs a supported Stata version/edition, for example '17 MP'")
        if "| ID | Severity |" not in text:
            errors.append(f"{path.name} must include the findings table")


def platform_name(os_name: str, machine: str) -> str:
    os_name, machine = os_name.lower(), machine.lower()
    mac = bool(re.search(r"\bmac\b|\bmacintosh\b|\bdarwin\b|apple silicon", machine))
    linux = bool(re.search(r"\blinux\b", machine))
    windows = bool(re.search(r"\bwindows\b|\bwin(?:32|64)\b", machine))
    if sum((mac, linux, windows)) > 1:
        return ""
    if os_name in {"mac", "macos", "macosx", "mac os x", "darwin"} and not (linux or windows):
        return "macos"
    if os_name in {"windows", "win32", "win64"} and not (mac or linux):
        return "windows"
    if os_name in {"linux", "gnu/linux"} and not (mac or windows):
        return "linux"
    if os_name == "unix":
        if mac:
            return "macos"
        # Linux's documented Stata x86-64 label does not contain "Linux":
        # stata.com/manuals/pcreturn.pdf and statalist/archive/2010-11/msg00850.html.
        if linux or machine == "pc (64-bit x86-64)":
            return "linux"
    return ""


def validate_platform(path: Path, candidate: str, errors: list[str]) -> None:
    expected_platform = path.name.removesuffix("-platform.csv")
    with path.open(encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh, strict=True)
        header = next(reader, [])
        if len(header) != len(set(header)) or not PLATFORM_COLUMNS.issubset(header):
            errors.append(f"{path.name} needs unique canonical columns: {', '.join(sorted(PLATFORM_COLUMNS))}")
            return
        count = 0
        for line, values in enumerate(reader, 2):
            if not values:
                continue
            count += 1
            label = f"{path.name} row {line}"
            if len(values) != len(header):
                errors.append(f"{label} has {len(values)} fields for {len(header)} columns")
                continue
            row = {key: value.strip() for key, value in zip(header, values)}
            for key in PLATFORM_COLUMNS:
                if not filled(row[key]):
                    errors.append(f"{label} has unfilled {key}")
            if row["release_gates_status"].lower() != "pass":
                errors.append(f"{label} must contain release_gates_status=pass")
            if row["repository_commit"].lower() != candidate:
                errors.append(f"{label} repository_commit must equal candidate {candidate}")
            if not SHA256.fullmatch(row["production_digest"]):
                errors.append(f"{label} production_digest must be a SHA256")
            if not valid_date(row["date"]):
                errors.append(f"{label} has invalid date")
            if row["byteorder"].lower() not in {"lohi", "hilo"}:
                errors.append(f"{label} has invalid byteorder")
            actual_platform = platform_name(row["os"], row["machine_type"])
            if actual_platform != expected_platform:
                errors.append(f"{label} does not identify {expected_platform}: os={row['os']}, machine={row['machine_type']}")
            floor = 15 if expected_platform == "macos" else 17
            editions = EDITIONS if expected_platform == "macos" else {"MP", "SE"}
            if version_number(row["stata_version"]) < floor or row["edition"].upper() not in editions:
                errors.append(f"{label} requires Stata {floor}+ and edition {'/'.join(sorted(editions))}")
        if not count:
            errors.append(f"{path.name} has no platform rows")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--candidate-commit", required=True, help="full repository commit reviewed and tested")
    parser.add_argument("--bundle", required=True, type=Path, help="actual nonempty bundle reviewed by the release owner")
    args = parser.parse_args()
    candidate = args.candidate_commit.lower()
    if not COMMIT.fullmatch(candidate):
        parser.error("--candidate-commit must be a full 40-character Git commit")
    try:
        resolved = subprocess.run(["git", "rev-parse", "--verify", candidate + "^{commit}"],
                                  cwd=ROOT, capture_output=True, text=True)
    except OSError as exc:
        parser.error(f"cannot resolve --candidate-commit: {exc}")
    if resolved.returncode or resolved.stdout.strip() != candidate:
        parser.error("--candidate-commit does not identify a commit in this repository")
    try:
        if not args.bundle.is_file():
            parser.error("--bundle must name a regular file")
        with args.bundle.open("rb") as fh:
            first = fh.read(1024 * 1024)
            if not first:
                parser.error("--bundle must be a nonempty file")
            digest = hashlib.sha256(first)
            for block in iter(lambda: fh.read(1024 * 1024), b""):
                digest.update(block)
        bundle_sha = digest.hexdigest()
    except OSError as exc:
        parser.error(f"cannot read --bundle: {exc}")

    root = Path(args.evidence_dir)
    errors: list[str] = []
    for name in REQUIRED_FILES:
        path = root / name
        if not path.is_file():
            errors.append(f"missing required evidence file: {name}")
            continue
        try:
            if not path.stat().st_size:
                errors.append(f"empty required evidence file: {name}")
            elif path.suffix == ".csv":
                validate_platform(path, candidate, errors)
            else:
                validate_signoff(path, candidate, bundle_sha, errors)
        except (OSError, UnicodeError, csv.Error) as exc:
            errors.append(f"cannot read {name}: {exc}")
    if errors:
        for error in errors:
            print(f"final evidence check failed: {error}", file=sys.stderr)
        return 1
    print(f"final release evidence inventory matches commit {candidate} and bundle SHA256 {bundle_sha}")
    print("Declared attribution checked; reviewer identity, execution logs and artifact contents require independent review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
