#!/usr/bin/env python3
"""Identify the runtime and exact inputs behind reusable preflight A/B evidence."""

import ast
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys


AB_FILES = (
    "tests/run-legacy-candidate-ab.sh",
    "tools/bench/run-legacy-candidate-ab.py",
    "tools/bench/legacy-candidate-ab-workload.do",
    "tools/bench/stata_runtime.py",
    "tools/plugin/build-bootstrap-plugin.sh",
    "tools/release/build-package.sh",
    "tools/release/build-package.do",
    "tools/release/check-stata-log-tail.sh",
    "tools/release/preflight.sh",
    "tools/release/preflight-digest.sh",
    "tools/release/preflight-evidence.py",
)


def sha256(path):
    with path.open("rb") as handle:
        digest = hashlib.sha256()
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
        return digest.hexdigest()


def runtime_identity(path, stata):
    fields = {}
    for line in path.read_text().splitlines():
        key, separator, value = line.partition("=")
        if not separator or key in fields or not value.strip():
            raise ValueError("incomplete or duplicated platform identity")
        fields[key] = value.strip()
    if set(fields) != {"stata_version", "edition", "os", "machine_type"}:
        raise ValueError("platform identity must contain exactly four canonical fields")
    if (not re.fullmatch(r"[1-9]\d*(?:\.\d+)?", fields["stata_version"])
            or fields["edition"] not in {"MP", "SE", "BE", "IC"}
            or any(value.lower() in {"unknown", "pending", "n/a"} for value in fields.values())):
        raise ValueError("invalid platform identity")
    command = shutil.which(stata)
    if command is None:
        raise ValueError("measured Stata executable is unavailable")
    executable = Path(command).resolve(strict=True)
    fields["executable"] = str(executable)
    fields["executable_sha256"] = sha256(executable)
    fields["host"] = platform.node()
    fields["system"] = platform.platform()
    return fields


def ab_identity(root, legacy):
    files = {name: sha256(root / name) for name in AB_FILES}
    runner = ast.parse((root / "tools/bench/run-legacy-candidate-ab.py").read_text())
    pins = [ast.literal_eval(node.value) for node in runner.body
            if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == "LEGACY_COMMIT"
                    for target in node.targets)]
    if len(pins) != 1 or re.fullmatch(r"[0-9a-f]{40}", pins[0]) is None:
        raise ValueError("A/B runner has no unambiguous pinned legacy commit")
    legacy = legacy.resolve(strict=True)
    def git(*args):
        return subprocess.check_output(["git", "-C", str(legacy), *args], text=True).strip()
    if git("rev-parse", "HEAD") != pins[0] or git("status", "--porcelain"):
        raise ValueError("legacy A/B checkout is not clean at the pinned commit")
    if not (legacy / "codes/csdid.ado").is_file():
        raise ValueError("pinned legacy A/B source is missing")
    return {"files": files, "legacy_commit": pins[0], "legacy_root": str(legacy)}


def reusable(path, production, runtime, inputs):
    try:
        if path.is_dir():
            return any(reusable(candidate, production, runtime, inputs)
                       for candidate in path.glob("receipt.*") if candidate.is_file())
        receipt = json.loads(path.read_text())
        return (receipt.get("mode") in {"full", "release"}
                and all(type(receipt.get(name)) is int and receipt[name] == 0
                        for name in ("fail", "blocked"))
                and receipt.get("ab_production_digest") == production
                and receipt.get("ab_runtime") == runtime
                and receipt.get("ab_inputs") == inputs)
    except (OSError, ValueError, AttributeError):
        return False


def main():
    mode, *args = sys.argv[1:]
    if mode == "runtime":
        value = runtime_identity(Path(args[0]), args[1])
    elif mode == "ab-inputs":
        value = ab_identity(Path(args[0]), Path(args[1]))
    elif mode == "reuse":
        if reusable(Path(args[0]), args[1], json.loads(args[2]), json.loads(args[3])):
            print(args[1])
        return
    else:
        raise ValueError("unknown evidence operation")
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, IndexError, TypeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"preflight evidence refused: {error}")
