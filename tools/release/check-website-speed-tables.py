#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Verify that every speed table published on the website is exactly what the
# committed benchmark results produce.
#
# The failure this prevents: a table is edited, or a benchmark is re-run and
# only some tables are refreshed, and the site then reports numbers no run ever
# produced. Nothing about a markdown table announces that it has gone stale.
#
# How it works: the generator writes each table as a fragment beginning with a
# unique `<p class="table-title">` line. That title is located in the target
# article and the block that follows is compared line for line. Locating by
# title means the public pages need no markers, comments, or anything else a
# reader would see.
#
# Usage:
#   python3 tools/release/check-website-speed-tables.py
#   python3 tools/release/check-website-speed-tables.py --write   # refresh them
# ---------------------------------------------------------------------------

import argparse
import pathlib
import subprocess
import sys
import tempfile
import json
import csv
import hashlib
import importlib.util
import datetime
import re
import difflib
import io

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "tools" / "bench" / "field" / "results"
GEN = ROOT / "tools" / "bench" / "make-field-speed-tables.py"

FIELD = ROOT / "website" / "articles" / "csdid-against-the-field.md"
LADDER = ROOT / "website" / "articles" / "speed-vs-182.md"
README = ROOT / ("packaging/README.md" if (ROOT / "packaging").is_dir() else "README.md")

# fragment file -> (article, how to find its block in that article)
#
# Two anchor styles, because the two pages are written differently. The
# comparison article labels each table with a <p class="table-title">; the
# Version 1.82 page uses a section heading and no label. Assuming one style
# would have left four tables permanently "not found", which reads as a
# missing table rather than as a checker that cannot see it.
PLACEMENT = {
    "csdid-only.md": (FIELD, "title", None),
    "balanced.md": (FIELD, "title", None),
    "unbalanced.md": (FIELD, "title", None),
    "rcs.md": (FIELD, "title", None),
    "periods.md": (FIELD, "title", None),
    "cohorts.md": (FIELD, "title", None),
    "v182-size.md": (LADDER, "heading", "## By sample size"),
    "v182-periods.md": (LADDER, "heading", "## By number of periods"),
    "v182-cohorts.md": (LADDER, "heading", "## By number of cohorts"),
    "v182-scheme.md": (LADDER, "heading", "## By sampling scheme"),
}

FIXED_WORKLOADS = [
    ("balanced_reg_analytical", "ATT(g,t), outcome regression, analytical"),
    ("balanced_dr_covariates_analytical", "ATT(g,t), doubly robust with covariates"),
    ("balanced_weighted_ipw_analytical", "ATT(g,t), IPW with weights"),
    ("balanced_cluster_reg_analytical", "ATT(g,t), clustered"),
    ("balanced_reg_bootstrap", "Bootstrap, outcome regression"),
    ("balanced_dr_covariates_bootstrap", "Bootstrap, doubly robust with covariates"),
    ("balanced_weighted_ipw_bootstrap", "Bootstrap, IPW with weights"),
    ("balanced_cluster_reg_bootstrap", "Bootstrap, clustered"),
    ("unbalanced_dr_weighted_analytical", "Unbalanced panel, weighted DR"),
    ("unbalanced_dr_weighted_bootstrap", "Unbalanced panel, bootstrap"),
    ("balanced_event_analytical", "Event study, analytical"),
    ("balanced_event_bootstrap", "Event study, bootstrap"),
    ("balanced_event_cband_bootstrap", "Event study, simultaneous bands"),
    ("balanced_cluster_event_cband_bootstrap", "Event study, clustered + bands"),
    ("large_balanced_dr_weighted_analytical", "Large panel, weighted DR"),
]


def fixed_size_record(evidence):
    """Recompute the original certification statistic from all 210 raw rows."""
    metadata = json.loads((evidence / "metadata.json").read_text())
    for filename, key in (("runs.csv", "runs_sha256"), ("summary.csv", "summary_sha256")):
        if hashlib.sha256((evidence / filename).read_bytes()).hexdigest() != metadata.get(key):
            raise ValueError(f"fixed-size evidence hash differs: {filename}")
    if metadata.get("legacy_commit") != "fdbae25521a941314af8d84ec0c93fb0596daa8e" or metadata.get("trials") != 7:
        raise ValueError("fixed-size README evidence requires the pinned baseline and seven trials")
    candidate_version = metadata.get("candidate_version", "")
    stamp = re.search(r"^\*! csdid ([0-9.]+) ", (ROOT / "src/ado/csdid.ado").read_text())
    if not stamp:
        raise ValueError("current candidate has no version stamp")
    current = stamp.group(1)
    if candidate_version != current:
        raise ValueError("fixed-size evidence does not measure the current candidate version")
    fingerprints = metadata.get("measurement_sha256", {})
    if not fingerprints or not any(name.startswith("src/") for name in fingerprints):
        raise ValueError("fixed-size evidence has no measured source identities")
    for name, digest in fingerprints.items():
        path = ROOT / name
        if path.is_absolute() and name.startswith("/") or ".." in pathlib.PurePath(name).parts:
            raise ValueError("invalid measured source path")
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"fixed-size measured source changed: {name}")
    with (evidence / "runs.csv").open(newline="") as stream:
        runs = list(csv.DictReader(stream))
    with (evidence / "summary.csv").open(newline="") as stream:
        summary = list(csv.DictReader(stream))
    expected = {(scenario, implementation, trial) for scenario, _ in FIXED_WORKLOADS
                for implementation in ("candidate", "legacy") for trial in range(1, 8)}
    observed = [(row["scenario"], row["implementation"], int(row["trial"])) for row in runs]
    if len(observed) != len(expected) or set(observed) != expected:
        raise ValueError("fixed-size evidence requires all 15 scenarios, both implementations and trials 1..7")
    runtime_keys = ("stata_version", "stata_flavor", "stata_processors", "os", "machine_type")
    runtimes = {tuple(row[key] for key in runtime_keys) for row in runs}
    runtime = metadata.get("runtime", {})
    recorded = tuple(runtime.get(key) for key in ("version", "edition", "processors", "os", "machine_type"))
    if len(runtimes) != 1 or recorded not in runtimes or not all(recorded) or int(runtime["processors"]) < 1:
        raise ValueError("fixed-size runtime differs from its measured observations")
    sys.path.insert(0, str(ROOT / "tools/bench"))
    spec = importlib.util.spec_from_file_location("speed_legacy_ab", ROOT / "tools/bench/run-legacy-candidate-ab.py")
    instrument = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(instrument)
    if fingerprints != instrument.candidate_fingerprints():
        raise ValueError("fixed-size evidence omits or changes a measured source/artifact identity")
    if set(instrument.SCENARIOS) != {name for name, _ in FIXED_WORKLOADS}:
        raise ValueError("fixed-size scenario definitions changed")
    for row in runs:
        if (int(row["inner"]) != instrument.SCENARIOS[row["scenario"]]["inner"]
                or row["comparison"] != "like-for-like"
                or any(not instrument.math.isfinite(float(row[key])) or float(row[key]) <= 0
                       for key in ("seconds", "peak_rss_mb", "observations", "rss_samples"))):
            raise ValueError("invalid fixed-size raw observation")
    by_scenario = {row["scenario"]: row for row in summary}
    if len(summary) != 15 or set(by_scenario) != set(instrument.SCENARIOS):
        raise ValueError("fixed-size summary is incomplete or duplicated")
    for scenario, config in instrument.SCENARIOS.items():
        recomputed = instrument.summarize(scenario, config, [r for r in runs if r["scenario"] == scenario])
        if {key: str(value) for key, value in recomputed.items()} != by_scenario[scenario]:
            raise ValueError(f"fixed-size summary differs from raw paired trials: {scenario}")
        if any(by_scenario[scenario][key] != "1" for key in ("candidate_faster", "candidate_lower_rss")):
            raise ValueError(f"fixed-size certification fails its unchanged budget: {scenario}")
    version, edition = recorded[:2]
    line = "StataNow" if "." in version and int(version.split(".")[1]) else "Stata"
    metadata["runtime_label"] = f"{line}/{edition} {version} using {runtime['processors']} processors"
    return metadata, by_scenario


def fixed_size_readme(evidence, readme):
    metadata, rows = fixed_size_record(evidence)
    text = readme.read_text()
    start, end = text.index("## Speed\n"), text.index("## Unbalanced panels\n")
    body = text[start:end]
    table = [f"| Workload | Version 1.82 | {metadata['candidate_version']} | |", "| --- | ---: | ---: | ---: |"]
    gains = []
    for scenario, label in FIXED_WORKLOADS:
        row = rows[scenario]
        gain = round(1 / float(row["median_paired_time_ratio"]))
        gains.append(gain)
        table.append(f"| {label} | {float(row['legacy_median_seconds']):.2f}s | "
                     f"{float(row['candidate_median_seconds']):.2f}s | **{gain}x** |")
    body, count = re.subn(r"^\| Workload \|[^\n]*\n(?:\|[^\n]*\n)+", "\n".join(table) + "\n", body, count=1, flags=re.M)
    if count != 1:
        raise ValueError("README has no unique fixed-size table")
    day = datetime.date.fromisoformat(metadata["generated_date"])
    human = f"{day.day} {day:%B} {day.year}"
    body, count = re.subn(r"line, November 2025 &mdash; on .*?\n?trials per workload after one discarded warmup, on [^\n]+\.",
                         f"line, November 2025 &mdash; on {human}, on the same machine and data, with seven timed\n"
                         f"trials per workload after one discarded warmup, on {metadata['runtime_label']}.", body, count=1, flags=re.S)
    if count != 1:
        raise ValueError("README has no unique fixed-size measurement provenance")
    large = rows["large_balanced_dr_weighted_analytical"]
    above = sum(float(row["median_paired_rss_ratio"]) > 1 for row in rows.values())
    faster = all(float(row["median_paired_time_ratio"]) < 1 for row in rows.values())
    paragraph = (f"Between **{min(gains)}x and {max(gains)}x** across these fifteen fixed-size workloads, each run\n"
                 "with the same options on both versions" + (", and never slower." if faster else ".") + " That is a different\n"
                 "measurement from the scaling comparison below, which varies the size of the\n"
                 "design on purpose. Peak memory is within 8% of Version 1.82 on every\n"
                 f"workload. On the large panel above, peak memory is {float(large['candidate_median_peak_rss_mb']):.0f}MB\n"
                 f"against {float(large['legacy_median_peak_rss_mb']):.0f}MB. The paired-trial memory ratio is above one\n"
                 f"in {above} of these 15 workloads. The memory comparison uses paired\n"
                 "trials on the same Stata interpreter.")
    body, count = re.subn(r"Between \*\*.*?(?=\n\nThose are fixed-size workloads\.)", paragraph, body, count=1, flags=re.S)
    if count != 1:
        raise ValueError("README has no unique fixed-size summary paragraph")
    return text[:start] + body + text[end:]


def verify_collection_phases(metadata, csv_path):
    """Bind the bounded log-discovery continuation to its preserved raw phases."""
    repaired_commit = "329f5ec4f2b32e442b33ab3f4ee59b5f27bb8d4a"
    repaired_results = "32949b86ef4304bddc99bd69fb5f072f5ee16973ef1314c39f85eb3c1ba6c1d5"
    known_record = hashlib.sha256(csv_path.read_bytes()).hexdigest() == repaired_results
    if (not known_record and metadata.get("candidate_commit") != repaired_commit
            and "collection_phases" not in metadata and "log_discovery_only_repair" not in metadata):
        return
    phases = metadata.get("collection_phases")
    if not isinstance(phases, list) or len(phases) != 2:
        raise ValueError("repaired timing campaign requires both original collection phases")
    lines = csv_path.read_bytes().splitlines(keepends=True)
    if len(lines) != 173:
        raise ValueError("repaired timing campaign requires exactly 172 raw observations")
    expected = [("main142",142,b"".join(lines[:143])),
                ("F30",30,lines[0]+b"".join(lines[143:]))]
    for phase, (name,count,data) in zip(phases,expected):
        if (phase.get("name"),phase.get("observations"),phase.get("results_sha256")) != (name,count,hashlib.sha256(data).hexdigest()):
            raise ValueError("timing collection phase count, order or raw SHA differs")
        rows = list(csv.DictReader(io.StringIO(data.decode())))
        if any(row["scan"].startswith("F_") != (name == "F30") for row in rows):
            raise ValueError("timing collection phase contains observations from another phase")
    if phases[0].get("source_commit") != "9dd9ba4d254d7054050a88fa1c1c96c4b7512c63" or phases[1].get("source_commit") != repaired_commit or metadata.get("candidate_commit") != repaired_commit:
        raise ValueError("timing collection commits were relabeled")
    current = metadata["measurement_sha256"]
    original = phases[0].get("measurement_sha256", {})
    if set(original) != set(current) or phases[1].get("measurement_sha256") != current:
        raise ValueError("timing collection phase source inventory differs")
    source = "tools/bench/field/scalebench_f.sh"
    if [name for name in current if current[name] != original[name]] != [source]:
        raise ValueError("timing continuation changes more than shell log discovery")
    repair = metadata.get("log_discovery_only_repair", {})
    before = repair.get("before_source", "").encode()
    after = before
    substitutions = {
        b'  : > "$B/scalebench_f_cell.log"\n': b'  # Batch Stata names this log after the final filename argument, the CSV.\n  local log="${CSV%.csv}.log"\n  : > "$log"\n',
        b'    [ ! -f "$B/scalebench_f_cell.log" ] || cp "$B/scalebench_f_cell.log"': b'    [ ! -f "$log" ] || cp "$log"',
        b'  local log="$B/scalebench_f_cell.log"\n': b'',
    }
    for old,new in substitutions.items():
        if after.count(old) != 1:
            raise ValueError("timing log-discovery repair anchor differs")
        after = after.replace(old,new)
    delta = "".join(difflib.unified_diff(before.decode().splitlines(True),after.decode().splitlines(True),fromfile="a/"+source,tofile="b/"+source))
    if (repair.get("source_file") != source or hashlib.sha256(before).hexdigest() != original[source]
            or repair.get("before_sha256") != original[source] or repair.get("after_sha256") != current[source]
            or hashlib.sha256(after).hexdigest() != current[source] or (ROOT/source).read_bytes() != after
            or repair.get("unified_diff") != delta):
        raise ValueError("timing log-discovery repair changes the qualified source patch")


def article_record_labels(text, article, metadata):
    if not metadata.get("candidate_version"):
        return text
    day = datetime.date.fromisoformat(metadata["date"])
    when = (f"{day.day} {day:%B} {day.year} with {metadata['stata']}\n"
            f"on {metadata['platform']} with {metadata['processors']} processors")
    if article == FIELD:
        text, count = re.subn(r"(?:All timings in this section were measured|The timing campaign in this section completed) on .*?, using a separate Stata process",
                             f"The timing campaign in this section completed on {when}, using a separate Stata process",
                             text, count=1, flags=re.S)
    else:
        text, count = re.subn(r"All the timings on this page were measured on .*?, in the same measurement campaign",
                             f"All the timings on this page were measured on {when}, in the same measurement campaign",
                             text, count=1, flags=re.S)
        # The opening sentence identifies the historical 2.0.0 release. Every
        # later version label identifies the candidate actually timed here.
        opening, remainder = text.split("Our protocol", 1)
        remainder = re.sub(r"\b2\.0\.\d+\b", metadata["candidate_version"], remainder)
        text = opening + "Our protocol" + remainder
    if count != 1:
        raise ValueError(f"{article.name}: missing unique timing-provenance sentence")
    return text


def block_of(fragment):
    """Return (title, full_lines) for a generated fragment.

    full_lines KEEPS the blank lines. They are not padding: a markdown table
    needs a blank line before it, and stripping them produced a page where the
    title, the table and the note ran together and the table stopped rendering
    as a table. Comparison is done on the non-blank lines (see `content`), but
    what gets written back is the fragment as generated."""
    lines = fragment.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    body = [ln for ln in lines if ln.strip()]
    if not body or not body[0].startswith('<p class="table-title"'):
        raise SystemExit("generated fragment does not start with a table title")
    return body[0], lines


def content(lines):
    """The lines that carry meaning, for comparison. Blank-line placement is
    formatting and is taken from the generator, not diffed against the page."""
    return [ln for ln in lines if ln.strip()]


def find_block(article_lines, anchor, length, style):
    """Return ((block_lines, start, stop), None) for the published block.

    The block's END is found STRUCTURALLY -- title, then the table, then an
    optional table-note paragraph -- not by counting the generated fragment's
    lines. Counting was a real bug: when the generated fragment was longer than
    the published block (a new note line, an extra column row), the span ran
    past the table and swallowed the paragraph after it. It silently deleted
    two lines of prose from the Version 1.82 page before this was caught.

    `length` is therefore unused for locating the end and kept only so callers
    read naturally; it is the caller's job to compare contents.
    """
    hits = [i for i, ln in enumerate(article_lines) if ln.strip() == anchor.strip()]
    if not hits:
        return None, f"anchor {anchor.strip()!r} not found in the article"
    if len(hits) > 1:
        return None, f"anchor {anchor.strip()!r} appears {len(hits)} times; cannot identify one block"

    i = start = hits[0]
    if style == "heading":
        # The heading is not part of the block; the table under it is. A
        # section may open with a paragraph before its table -- the periods
        # section does -- so prose is skipped, but only as far as the NEXT
        # heading. Without that bound a section with no table would silently
        # adopt the next section's.
        i += 1
        while i < len(article_lines) and not article_lines[i].lstrip().startswith("|"):
            if article_lines[i].startswith("#"):
                return None, (f"no table between {anchor.strip()!r} and the next "
                              f"heading {article_lines[i].strip()!r}")
            i += 1
        if i >= len(article_lines):
            return None, f"no table found under {anchor.strip()!r}"
        start = i
    else:
        i += 1  # past the title line

    while i < len(article_lines) and not article_lines[i].strip():
        i += 1
    if i >= len(article_lines) or not article_lines[i].lstrip().startswith("|"):
        return None, f"no table follows {anchor.strip()!r}"
    while i < len(article_lines) and article_lines[i].lstrip().startswith("|"):
        i += 1
    stop = i

    # an optional note paragraph, only if it is the very next non-blank line
    j = i
    while j < len(article_lines) and not article_lines[j].strip():
        j += 1
    if j < len(article_lines) and article_lines[j].lstrip().startswith('<p class="table-note"'):
        stop = j + 1

    return (article_lines[start:stop], start, stop), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="replace the article blocks with the generated ones")
    ap.add_argument("--fixed-size-evidence", type=pathlib.Path,
                    help="seven-trial legacy certification directory for the README")
    ap.add_argument("--fixed-size-only", action="store_true")
    ap.add_argument("--readme", type=pathlib.Path, default=README)
    args = ap.parse_args()

    fixed = args.fixed_size_evidence or RESULTS / "legacy-candidate-ab"
    current_metadata = json.loads((RESULTS / "metadata.json").read_text())
    packaged = re.search(r"^\*! csdid ([0-9.]+) ", (ROOT / "pkg/csdid.ado").read_text())
    source_stamp = re.search(r"^\*! csdid ([0-9.]+) ", (ROOT / "src/ado/csdid.ado").read_text())
    if not packaged or not source_stamp or packaged[1] != source_stamp[1]:
        sys.exit("current package and source versions differ")
    if not args.fixed_size_only and current_metadata.get("candidate_version") != packaged[1]:
        sys.exit("current timing evidence does not identify the packaged release; run the full fresh campaign")
    if args.fixed_size_only or args.fixed_size_evidence or current_metadata.get("candidate_version") == "2.0.1":
        try:
            wanted = fixed_size_readme(fixed, args.readme)
        except (ValueError, OSError, KeyError, TypeError) as error:
            sys.exit(f"fixed-size README evidence refused: {error}")
        if wanted != args.readme.read_text():
            if args.write:
                args.readme.write_text(wanted)
                print("refreshed all 15 README workloads and their fixed-size summaries")
            else:
                sys.exit("README fixed-size table/provenance/summaries differ from the fresh seven-trial evidence; rerun with --write")
        if args.fixed_size_only:
            print("README fixed-size evidence OK: 15 scenarios, 210 paired observations, unchanged certification budgets")
            return

    csv_path = RESULTS / "scalebench-results.csv"
    meta_path = RESULTS / "metadata.json"
    if not csv_path.exists():
        sys.exit(f"no results of record at {csv_path}; run the benchmark and commit its CSV")
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    try:
        verify_collection_phases(meta, csv_path)
    except (ValueError, KeyError, TypeError) as error:
        sys.exit(f"timing collection phases refused: {error}")
    if meta.get("candidate_version"):
        if meta.get("observations") != 172 or meta.get("trials") != 10 or meta.get("seeded_from"):
            sys.exit("current speed record requires all 172 fresh observations and the original main-tier trial policy")
        if hashlib.sha256(csv_path.read_bytes()).hexdigest() != meta.get("results_sha256"):
            sys.exit("current speed CSV differs from its recorded SHA256")
        compiler = meta.get("engine_stamp", "").split("|")[-1]
        if (type(meta.get("processors")) is not int or meta["processors"] < 1
                or not meta.get("engine_stamp", "").startswith(meta["candidate_version"] + "|")
                or not re.fullmatch(r"\d+(?:\.\d+)?", compiler)
                or meta.get("engine_library_sha256") != hashlib.sha256((ROOT / "pkg/lcsdid_v2.mlib").read_bytes()).hexdigest()):
            sys.exit("current speed record lacks the actual processor count and pinned compiled-engine identity")
        expected_sources = {str(p.relative_to(ROOT)) for p in (ROOT / "src").rglob("*") if p.is_file() and p.suffix != ".plugin"}
        expected_sources.add("pkg/lcsdid_v2.mlib")
        expected_sources.update(str(p.relative_to(ROOT)) for pattern in ("*.ado", "*.mata") for p in (ROOT / "pkg").glob(pattern))
        expected_sources.update(str(p.relative_to(ROOT)) for p in (ROOT / "pkg").glob("csdid_bootstrap_*.plugin"))
        expected_sources.update("tools/bench/field/" + name for name in
                                "dgp.do validate.do time.do runners.do scalebench.do scalebench_f_cell.do scalebench_f.sh".split())
        if set(meta.get("measurement_sha256", {})) != expected_sources:
            sys.exit("current speed record omits measured source identities")
        for name, digest in meta["measurement_sha256"].items():
            if pathlib.Path(name).is_absolute() or ".." in pathlib.PurePath(name).parts:
                sys.exit("invalid speed source path")
            path = ROOT / name
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                sys.exit(f"speed measurement source changed: {name}")
        expected_packages = set("jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn flexdid hdidregress xthdidregress drdid reghdfe ftools lmoremata".split())
        if set(meta.get("packages", {})) != expected_packages:
            sys.exit("current speed record lacks measured source or installed-package provenance")

    with tempfile.TemporaryDirectory() as tmp:
        proc = subprocess.run(
            [sys.executable, str(GEN),
             "--results", str(csv_path), "--outdir", tmp,
             "--stata", meta.get("stata", "unknown"),
             "--platform", meta.get("platform", "unknown"),
             "--date", meta.get("date", "unknown"),
             "--trials", str(meta.get("trials", "")),
             "--candidate-version", meta.get("candidate_version", "2.0.0")],
            capture_output=True, text=True)
        if proc.returncode != 0:
            sys.exit(f"the table generator refused:\n{proc.stderr}")

        failures, checked = [], 0
        edits = {}
        for name, (article, style, anchor) in PLACEMENT.items():
            frag_path = pathlib.Path(tmp) / name
            if not frag_path.exists():
                failures.append(f"missing required generated fragment: {name}")
                continue
            title, want = block_of(frag_path.read_text(encoding="utf-8"))
            if style == "heading":
                # the page carries no table label, so the generated one is not
                # published and must not be written or compared
                want = want[1:]
                while want and not want[0].strip():
                    want.pop(0)
            art_lines = article.read_text(encoding="utf-8").splitlines()
            found, why = find_block(art_lines, anchor if style == "heading" else title,
                                    len(want), style)
            checked += 1
            if found is None:
                failures.append(f"{article.name}: {name}: {why}")
                continue
            got, start, stop = found
            if content(got) != content(want):
                if args.write:
                    edits.setdefault(article, []).append((start, stop, want))
                else:
                    diff = []
                    for a, b in zip(content(got), content(want)):
                        if a != b:
                            diff.append(f"      published: {a}\n      measured:  {b}")
                    if len(content(got)) != len(content(want)):
                        diff.append(f"      published has {len(content(got))} lines, "
                                    f"measured has {len(content(want))}")
                    failures.append(f"{article.name}: {name} differs from the measurement:\n"
                                    + "\n".join(diff[:6]))

        labels_changed = False
        if meta.get("candidate_version"):
            for article in {value[0] for value in PLACEMENT.values()}:
                original = article.read_text()
                expected = article_record_labels(original, article, meta)
                if expected != original:
                    labels_changed = True
                    if not args.write:
                        failures.append(f"{article.name}: measurement date, runtime or candidate-version labels differ from metadata")
        if args.write and (edits or labels_changed):
            for article in {value[0] for value in PLACEMENT.values()}:
                spans = edits.get(article, [])
                lines = article.read_text(encoding="utf-8").splitlines()
                # last span first, so earlier spans keep their indices
                for start, stop, want in sorted(spans, key=lambda x: -x[0]):
                    lines[start:stop] = want
                updated = article_record_labels("\n".join(lines) + "\n", article, meta)
                article.write_text(updated, encoding="utf-8")
                print(f"  rewrote {len(spans)} table(s) in {article.name}")
            return

        # The provenance sentence is the claim that was false before any of
        # this existed: the article named a Stata release the numbers had not
        # been measured on. Tables being right does not fix that, so the
        # interpreter and the date are checked against the metadata too.
        import datetime
        if meta.get("stata") and meta.get("date"):
            d = datetime.date.fromisoformat(meta["date"])
            human = f"{d.day} {d:%B} {d.year}"
            for article in {a for a, _, _ in PLACEMENT.values()}:
                body = article.read_text(encoding="utf-8")
                if meta["stata"] not in body:
                    failures.append(
                        f"{article.name}: publishes speed tables but never names "
                        f"{meta['stata']}, which is the interpreter that measured them")
                if human not in body:
                    failures.append(
                        f"{article.name}: publishes speed tables but never names "
                        f"the measurement date ({human})")

        if failures:
            print(f"\n{len(failures)} of {checked} published tables disagree with the "
                  f"committed benchmark results:\n", file=sys.stderr)
            for f in failures:
                print(f"  {f}", file=sys.stderr)
            print("\nRe-run with --write to refresh them from the measurement.",
                  file=sys.stderr)
            sys.exit(1)

        if checked != len(PLACEMENT):
            sys.exit(f"only {checked} of {len(PLACEMENT)} speed tables were checked")
        print(f"website speed tables OK: {checked} tables match the committed results")


if __name__ == "__main__":
    main()
