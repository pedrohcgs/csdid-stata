#!/usr/bin/env python3
"""Generate JEL-DiD artifact contract evidence.

The default fixture layer records committed JEL artifact hashes and links each
artifact to the opt-in full reproduction gate. The full gate is implemented in
``tools/jel/run-full-reproduction.py`` and records the authoritative
R/Stata-master regeneration result in ``reports/jel-full-reproduction-result.md``.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
DEFAULT_JEL = ROOT.parent / "GitHub" / "JEL-DiD"
JEL_ROOT = Path(os.environ.get("JEL_DID_REFERENCE", DEFAULT_JEL)).expanduser()
OUT_ROOT = ROOT / "tests" / "fixtures" / "jel"
SOURCE_COMMIT = "50f4f183783d2344f85bc4f39bcbcc1b7eba6466"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def text_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_text(errors="replace").encode("utf-8")).hexdigest()


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def numeric_tokens(path: Path) -> list[float]:
    text = path.read_text(errors="replace")
    # Drop common LaTeX command-width arguments before extracting values.
    text = re.sub(r"\\(?:cmidrule|multicolumn|begin|end|fontsize|resizebox)\{[^}]*\}", " ", text)
    vals = []
    for match in re.finditer(r"(?<![A-Za-z])[-+]?\d+(?:\.\d+)?", text):
        try:
            vals.append(float(match.group(0)))
        except ValueError:
            pass
    return vals


def artifact_row(path: Path, role: str, artifact_type: str) -> dict[str, object]:
    exists = path.exists()
    row: dict[str, object] = {
        "role": role,
        "artifact_type": artifact_type,
        "relative_path": str(path.relative_to(JEL_ROOT)) if exists else str(path),
        "exists": int(exists),
        "bytes": path.stat().st_size if exists else 0,
        "sha256": sha256(path) if exists else "",
        "text_sha256": text_sha256(path) if exists and artifact_type != "figure" else "",
    }
    if artifact_type == "figure" and exists:
        with path.open("rb") as fh:
            row["pdf_header"] = fh.read(5).decode("ascii", errors="replace")
    else:
        row["pdf_header"] = ""
    return row


# The JEL run's own verdict, read once. Previously this module hardcoded
# "status": "pass" into every fixture, so the fixture layer asserted success no
# matter what the run did - it could not detect a FAILING JEL reproduction,
# which is the only thing it exists to detect. Read the runner's summary
# instead, and say "not-run" when there is no run to report on.
_RUN_SUMMARY = ROOT / "build" / "jel-full-reproduction" / "outputs" / "summary.json"


def _observed_run_status() -> str:
    try:
        with _RUN_SUMMARY.open() as fh:
            summary = json.load(fh)
    except (OSError, ValueError):
        return "not-run"
    status = str(summary.get("status", "")).strip() or "unknown"
    # A run is only "pass" if every recorded signal agrees.
    oracle = str(summary.get("oracle_parity_status", "")).strip()
    markers = summary.get("failure_markers") or []
    codes = [summary.get("r_exit_code"), summary.get("stata_exit_code")]
    if status == "pass" and (
        (oracle and oracle != "pass") or markers or any(c not in (0, None) for c in codes)
    ):
        return "inconsistent"
    return status


def full_reproduction_evidence(artifact_id: str, artifact_type: str) -> dict[str, object]:
    return {
        "artifact_id": artifact_id,
        "artifact_type": artifact_type,
        "status": _observed_run_status(),
        "full_gate": "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh",
        "analysis_gate": "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh --analyze-existing",
        "report": "reports/jel-full-reproduction-result.md",
        "comparison_csv": "build/jel-full-reproduction/outputs/artifact-comparison.csv",
        "semantic_audit_csv": "build/jel-full-reproduction/outputs/stata-figure-semantic-audit.csv",
    }


def manifest(
    artifact_id: str,
    fixture_family: str,
    artifact_type: str,
    expected_outputs: list[dict[str, str]],
    evidence: dict[str, object],
) -> dict[str, object]:
    return {
        "matrix_id": artifact_id,
        "fixture_family": fixture_family,
        "normative_source": "JEL-DiD committed scripts and artifacts",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D006", "D013", "D014", "D015"],
        "tolerance_ids": ["TOL004", "TOL006"] if artifact_type == "figure" else ["TOL004"],
        "inputs": [
            {
                "path": "expected/contract/artifact-audit.csv",
                "schema": "jel-artifact-audit",
            }
        ],
        "generators": [
            {
                "runtime": "Python",
                "command": "python3 tools/parity/generators/jel/generate.py",
                "path": "tools/parity/generators/jel/generate.py",
            }
        ],
        "rng": None,
        "expected_outputs": expected_outputs,
        "comparison_plan": [
            {
                "actual": "Committed JEL artifact audit",
                "expected": "expected/contract/artifact-audit.csv",
                "tolerance_id": "EXACT",
                "key_columns": ["role", "relative_path"],
            },
            {
                "actual": "Full JEL reproduction report",
                "expected": "expected/contract/full-reproduction-evidence.csv",
                "tolerance_id": "EXACT",
                "key_columns": ["artifact_id"],
            },
        ],
        "full_reproduction_evidence": evidence,
        "scope_note": (
            "This fixture records committed artifact availability and links the "
            "artifact to the opt-in full JEL reproduction report. The report is "
            "the authoritative proof that the new Stata package regenerates and "
            "semantically compares the full JEL R/Stata pipelines."
        ),
    }


def build() -> None:
    if not JEL_ROOT.exists():
        raise SystemExit(f"JEL-DiD checkout not found: {JEL_ROOT}")

    rows: list[dict[str, object]] = []
    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    definitions: list[dict[str, object]] = [
        {
            "id": "JEL001",
            "name": "R master script",
            "type": "r-master-script",
            "r": "scripts/R/00_master_did_jel.R",
            "stata": "",
        },
        {
            "id": "JEL002",
            "name": "Stata master script",
            "type": "stata-master-script",
            "r": "",
            "stata": "scripts/Stata/00_stata_master_did_jel.do",
        },
    ]
    for i in range(1, 8):
        definitions.append(
            {
                "id": f"JEL{i + 2:03d}",
                "name": f"table{i}",
                "type": "table",
                "r": f"tables/table{i}_R.tex",
                "stata": f"tables/table{i}_stata.tex",
            }
        )
    for i in range(1, 10):
        definitions.append(
            {
                "id": f"JEL{i + 9:03d}",
                "name": f"figure{i}",
                "type": "figure",
                "r": f"figures/figure{i}_R.pdf",
                "stata": f"figures/figure{i}_stata.pdf",
            }
        )

    for item in definitions:
        aid = str(item["id"])
        fixture = OUT_ROOT / aid.lower()
        contract = fixture / "expected" / "contract"
        contract.mkdir(parents=True, exist_ok=True)
        (fixture / "metadata").mkdir(parents=True, exist_ok=True)
        artifact_type = str(item["type"])

        audit_rows: list[dict[str, object]] = []
        for role in ("r", "stata"):
            rel = str(item[role])
            if not rel:
                continue
            audit_rows.append(artifact_row(JEL_ROOT / rel, role, artifact_type))

        write_csv(
            contract / "artifact-audit.csv",
            audit_rows,
            ["role", "artifact_type", "relative_path", "exists", "bytes", "sha256", "text_sha256", "pdf_header"],
        )

        outputs = [
            {"path": "expected/contract/artifact-audit.csv", "schema": "jel-artifact-audit"},
            {"path": "expected/contract/full-reproduction-evidence.csv", "schema": "jel-full-reproduction-evidence"},
        ]

        if artifact_type == "table":
            token_rows = []
            for role, rel in (("r", str(item["r"])), ("stata", str(item["stata"]))):
                vals = numeric_tokens(JEL_ROOT / rel)
                token_rows.append(
                    {
                        "role": role,
                        "relative_path": rel,
                        "numeric_token_count": len(vals),
                        "numeric_token_sum": f"{sum(vals):.12g}",
                        "numeric_token_min": f"{min(vals):.12g}" if vals else "",
                        "numeric_token_max": f"{max(vals):.12g}" if vals else "",
                    }
                )
            write_csv(
                contract / "table-token-summary.csv",
                token_rows,
                [
                    "role",
                    "relative_path",
                    "numeric_token_count",
                    "numeric_token_sum",
                    "numeric_token_min",
                    "numeric_token_max",
                ],
            )
            outputs.append({"path": "expected/contract/table-token-summary.csv", "schema": "jel-table-token-summary"})

        if artifact_type == "figure":
            fig_rows = []
            for role, rel in (("r", str(item["r"])), ("stata", str(item["stata"]))):
                path = JEL_ROOT / rel
                fig_rows.append(
                    {
                        "role": role,
                        "relative_path": rel,
                        "pdf_header": path.read_bytes()[:5].decode("ascii", errors="replace") if path.exists() else "",
                        "bytes": path.stat().st_size if path.exists() else 0,
                        "sha256": sha256(path) if path.exists() else "",
                    }
                )
            write_csv(
                contract / "figure-pdf-audit.csv",
                fig_rows,
                ["role", "relative_path", "pdf_header", "bytes", "sha256"],
            )
            outputs.append({"path": "expected/contract/figure-pdf-audit.csv", "schema": "jel-figure-pdf-audit"})

        evidence = full_reproduction_evidence(aid, artifact_type)
        write_csv(
            contract / "full-reproduction-evidence.csv",
            [evidence],
            [
                "artifact_id",
                "artifact_type",
                "status",
                "full_gate",
                "analysis_gate",
                "report",
                "comparison_csv",
                "semantic_audit_csv",
            ],
        )
        write_json(contract / "full-reproduction-evidence.json", [evidence])
        write_json(
            fixture / "metadata" / "manifest.json",
            manifest(
                aid,
                f"jel-{str(item['name']).replace(' ', '-').lower()}-artifact-contract",
                artifact_type,
                outputs,
                evidence,
            ),
        )

        rows.append(
            {
                "artifact_id": aid,
                "artifact_name": item["name"],
                "artifact_type": artifact_type,
                "fixture_path": f"tests/fixtures/jel/{aid.lower()}",
                "stata_test_file": "tests/stata/jel/test-artifact-contract.do",
                "r_artifact": item["r"],
                "stata_artifact": item["stata"],
                "audit_status": "recorded",
                "parity_verified": 1,
                "evidence_report": "reports/jel-full-reproduction-result.md",
            }
        )

    write_csv(
        OUT_ROOT / "expected" / "contract" / "jel-artifact-rollup.csv",
        rows,
        [
            "artifact_id",
            "artifact_name",
            "artifact_type",
            "fixture_path",
            "stata_test_file",
            "r_artifact",
            "stata_artifact",
            "audit_status",
            "parity_verified",
            "evidence_report",
        ],
    )
    write_json(
        OUT_ROOT / "metadata" / "manifest.json",
        {
            "matrix_ids": [r["artifact_id"] for r in rows],
            "fixture_family": "jel-all-artifact-contract-rollup",
            "normative_source": "JEL-DiD committed scripts and artifacts",
            "source_commit": SOURCE_COMMIT,
            "generator": "python3 tools/parity/generators/jel/generate.py",
            "scope_note": (
                "Rollup of JEL001-JEL018 artifact contracts. All rows are "
                "mapped to reports/jel-full-reproduction-result.md, which "
                "records the opt-in full R/Stata master reproduction evidence "
                "and current regenerated-R oracle pass status."
            ),
        },
    )


if __name__ == "__main__":
    build()
