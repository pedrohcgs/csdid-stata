#!/usr/bin/env python3
"""Validate final-release evidence inventory.

This checker is intentionally stricter than local release-candidate gates. It
expects an evidence directory populated by external platform runs and
independent reviewers.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


REQUIRED_FILES = [
    "stata-mata-review-signoff.md",
    "econometrics-review-signoff.md",
    "macos-platform.csv",
    "windows-platform.csv",
    "linux-platform.csv",
    "release-owner-decision.md",
]


PLACEHOLDER_VALUES = {"", "tbd", "todo", "n/a", "na", "pending", "replace me"}


def normalize(value: str | None) -> str:
    return (value or "").strip()


def normalize_lower(value: str | None) -> str:
    return normalize(value).lower()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def field_value(text: str, field: str) -> str:
    prefix = f"{field}:"
    for line in text.splitlines():
        if line.strip().lower().startswith(prefix.lower()):
            return line.split(":", 1)[1].strip()
    return ""


def require_filled_field(path: Path, text: str, field: str, errors: list[str]) -> None:
    value = field_value(text, field)
    if normalize_lower(value) in PLACEHOLDER_VALUES:
        errors.append(f"{path.name} has unfilled field: {field}")


def require_exact_field(
    path: Path,
    text: str,
    field: str,
    expected: str,
    errors: list[str],
) -> None:
    value = normalize_lower(field_value(text, field))
    if value != expected:
        errors.append(f"{path.name} must set '{field}: {expected}'")


def validate_signoff(path: Path, kind: str, errors: list[str]) -> None:
    text = read_text(path)
    for field in ["Reviewer", "Date", "Repository commit"]:
        require_filled_field(path, text, field, errors)
    if kind == "econometrics":
        require_filled_field(path, text, "R did source", errors)
    require_filled_field(path, text, "Stata version/edition", errors)
    require_filled_field(path, text, "Operating system", errors)
    require_exact_field(path, text, "Final release approved", "yes", errors)
    require_exact_field(path, text, "Blocking findings remaining", "none", errors)
    if "| ID | Severity |" not in text:
        errors.append(f"{path.name} must include the findings table")


def validate_release_owner_decision(path: Path, errors: list[str]) -> None:
    text = read_text(path)
    for field in ["Release owner", "Date", "Repository commit", "Bundle SHA256"]:
        require_filled_field(path, text, field, errors)
    require_exact_field(path, text, "Final release approved", "yes", errors)
    require_exact_field(path, text, "Blocking findings remaining", "none", errors)


def read_platform(path: Path) -> tuple[str, str, str, str, str]:
    with path.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise ValueError(f"{path} has no platform rows")
    row = rows[0]
    os_name = (row.get("os") or row.get("OS") or "").lower()
    stata = row.get("stata_version") or row.get("Stata") or ""
    edition = row.get("edition") or row.get("stata_flavor") or row.get("Edition") or ""
    machine = (row.get("machine_type") or row.get("Machine") or "").lower()
    gate_status = normalize_lower(row.get("release_gates_status") or row.get("gate_status"))
    if not os_name or not stata or not edition:
        raise ValueError(f"{path} must contain os, stata_version, and edition columns")
    if gate_status != "pass":
        raise ValueError(f"{path} must contain release_gates_status=pass")
    return os_name, stata, edition, machine, gate_status


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", required=True)
    args = parser.parse_args()

    root = Path(args.evidence_dir)
    errors: list[str] = []
    if not root.is_dir():
        errors.append(f"evidence directory does not exist: {root}")
    else:
        for rel in REQUIRED_FILES:
            path = root / rel
            if not path.is_file():
                errors.append(f"missing required evidence file: {rel}")
            elif path.stat().st_size == 0:
                errors.append(f"empty required evidence file: {rel}")

        signoff_specs = {
            "stata-mata-review-signoff.md": "stata-mata",
            "econometrics-review-signoff.md": "econometrics",
        }
        for rel, kind in signoff_specs.items():
            path = root / rel
            if path.is_file() and path.stat().st_size > 0:
                validate_signoff(path, kind, errors)

        owner_path = root / "release-owner-decision.md"
        if owner_path.is_file() and owner_path.stat().st_size > 0:
            validate_release_owner_decision(owner_path, errors)

        platform_expectations = {
            "macos-platform.csv": ("mac", "darwin", "unix"),
            "windows-platform.csv": ("windows", "win"),
            "linux-platform.csv": ("linux", "unix"),
        }
        for rel, expected_tokens in platform_expectations.items():
            path = root / rel
            if not path.is_file():
                continue
            try:
                os_name, stata, edition, machine, _ = read_platform(path)
            except ValueError as exc:
                errors.append(str(exc))
                continue
            if rel == "windows-platform.csv" and not any(tok in os_name for tok in expected_tokens):
                errors.append(f"{rel} does not look like a Windows row: os={os_name}")
            elif rel == "linux-platform.csv" and ("mac" in machine or "windows" in os_name or "win" in os_name):
                errors.append(f"{rel} does not look like a Linux/Unix row: os={os_name}, machine={machine}")
            elif rel == "macos-platform.csv" and not ("mac" in machine or "mac" in os_name or "darwin" in os_name):
                errors.append(f"{rel} does not look like a macOS row: os={os_name}, machine={machine}")
            if not stata:
                errors.append(f"{rel} has empty Stata version")
            if not edition:
                errors.append(f"{rel} has empty Stata edition")

    if errors:
        for err in errors:
            print(f"final evidence check failed: {err}", file=sys.stderr)
        return 1

    print("final release evidence inventory ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
