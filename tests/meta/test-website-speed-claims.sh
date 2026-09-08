#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Table generation is checked separately against the measured CSV. This gate
# follows each summary to its named table/design, including the public README
# layout and both NEWS copies; a missing claim cannot become a silent pass.
python3 - "$ROOT" <<'PY'
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
checked = 0

def read(relative):
    path = root / relative
    if not path.is_file():
        raise ValueError(f"missing speed evidence/surface: {relative}")
    return path.read_text()

def plain(text):
    return " ".join(text.replace("**", "").replace("`", "").split())

def section(text, start, stop=None):
    if text.count(start) != 1:
        raise ValueError(f"expected one speed-section anchor: {start}")
    text = text.split(start, 1)[1]
    if stop:
        if stop not in text:
            raise ValueError(f"missing speed-section end: {stop}")
        text = text.split(stop, 1)[0]
    return text

def table(text, anchor):
    lines = section(text, anchor).splitlines()
    rows, started = [], False
    for line in lines:
        if line.startswith("|"):
            started = True
            cells = [plain(cell) for cell in line.split("|")[1:-1]]
            if cells and not all(re.fullmatch(r"[-: ]*", cell) for cell in cells):
                rows.append(cells)
        elif started:
            break
    if len(rows) < 2:
        raise ValueError(f"missing table after {anchor}")
    return {row[0]: row[1:] for row in rows[1:]}

def gain(row):
    value = row[-1]
    return float(value[:-1]) if re.fullmatch(r"\d+(?:\.\d+)?x", value) else None

def expect(pattern, text, values, label, minimum=1):
    global checked
    matches = list(re.finditer(pattern, plain(text)))
    if len(matches) < minimum:
        raise ValueError(f"{label}: missing measured claim or scope")
    for match in matches:
        actual = tuple(float(value) for value in match.groups())
        if actual != tuple(values):
            raise ValueError(f"{label}: states {actual}; named evidence supports {tuple(values)}")
        checked += 1

def program(relative, name):
    matches = re.findall(r"^program define " + re.escape(name) + r"[^\n]*\n(.*?)^end\s*$",
                         read(relative), re.M | re.S)
    if len(matches) != 1:
        raise ValueError(f"{relative}: expected one {name} runner")
    return matches[0]

def csdid_call(body, name):
    match = re.search(r"^\s*capture noisily csdid (.*?)^\s*local rc = _rc\s*$", body, re.M | re.S)
    if not match:
        raise ValueError(f"{name}: missing timed estimation call")
    return " ".join(match.group(1).replace("///", "").split())

def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate speed-figure fingerprint field: {key}")
        result[key] = value
    return result

number = r"(\d+(?:\.\d+)?)"
try:
    ladder = read("website/articles/speed-vs-182.md")
    field = read("website/articles/csdid-against-the-field.md")
    index = section(read("website/index.md"), "## Speed", "## Also in R and Python")
    guides = read("website/guides.md")
    readme_path = "packaging/README.md" if (root / "packaging").is_dir() else "README.md"
    readme = section(read(readme_path), "## Speed", "## Unbalanced panels")
    tables = {key: table(ladder, "## By " + heading) for key, heading in [
        ("n", "sample size"), ("T", "number of periods"),
        ("G", "number of cohorts"), ("scheme", "sampling scheme")
    ]}
    gains = [gain(row) for rows in tables.values() for row in rows.values()]
    gains = [value for value in gains if value is not None]
    if len(gains) < 8:
        raise ValueError("fewer than eight measured ladder gains")
    bounds = (min(gains), max(gains))
    range_pattern = rf"from {number}x to {number}x"
    for label, body in [("field cross-reference", field), ("guides", guides), ("homepage", index)]:
        expect(range_pattern, body, bounds, label)
    expect(rf"{number}x there against {number}x at forty periods", ladder, bounds, "ladder extrema")
    expect(rf"up to {number}x", readme, [bounds[1]], "README ladder ceiling", minimum=2)
    fixed_gains = [gain(row) for row in table("## Speed" + readme, "## Speed").values()]
    if len(fixed_gains) != 15 or None in fixed_gains:
        raise ValueError("README fixed-size table must retain its fifteen measured gains")
    expect(rf"Between {number}x and {number}x", readme,
           [min(fixed_gains), max(fixed_gains)], "README separate fixed-size range")
    if "seven timed trials per workload after one discarded warmup" not in plain(readme):
        raise ValueError("README must distinguish seven timed trials from the discarded warmup")
    if "7 August 2026" not in readme:
        raise ValueError("README must date its separate fixed-size measurement")

    generator = read("tools/bench/make-field-speed-tables.py")
    match = re.search(r'\("E_default", "csdid-only.md", "([^"]+)"', generator)
    if not match:
        raise ValueError("missing within-package generated table title")
    title = match.group(1)
    if "estimation and event-study aggregation" not in title:
        raise ValueError("generated table title must include the complete timed workflow")
    million = table(field, f'>{title}</p>')["100,000"]
    field_times = [float(value) for value in million[1:]]
    protocol = plain(section(field, "## Speed", "### Balanced panel"))
    for requirement in ["times include estimation and event-study aggregation",
                        "calls are timed separately and summed",
                        "separate Stata process for each benchmark tier"]:
        if requirement not in protocol:
            raise ValueError(f"field timing protocol omits: {requirement}")
    if "fresh Stata process" not in plain(ladder):
        raise ValueError("legacy ladder must state its fresh-process isolation")
    for label, body in [("field protocol", protocol), ("ladder", plain(ladder)), ("generator", generator)]:
        if re.search(r"(?:single|same) session|after the clock stops", body):
            raise ValueError(f"{label}: timing scope or process-isolation claim contradicts the runners")

    # The current reproduction recipes must request the dated campaign's
    # inference. Analytical SEs alone now leave simultaneous bands requested.
    expected_dispatch = [
        ("", "analytical pointwise"),
        ("if \"`mode'\" == \"bootstrap\"", "wboot(reps(999) rseed(20260729)) pointwise"),
        ("if \"`mode'\" == \"bands\"", "wboot(reps(999) rseed(20260729))"),
    ]
    for relative, name in [("tools/bench/field/runners.do", "bench_csdid"),
                           ("tools/bench/field/scalebench.do", "bench_csdidbf"),
                           ("tools/bench/field/scalebench.do", "bench_csdidpair")]:
        body = program(relative, name)
        dispatch = [(" ".join(prefix.split()), options) for prefix, options in
                    re.findall(r'^[ \t]*(.*?)local inf "([^"\n]+)"[ \t]*$', body, re.M)]
        if dispatch != expected_dispatch or "`inf'" not in csdid_call(body, name):
            raise ValueError(f"{name}: pointwise/bootstrap/bands dispatch differs from the timed protocol")
    candidate = csdid_call(program("tools/bench/field/scalebench_f_cell.do", "bench_c200"), "bench_c200")
    if "method(dr) analytical pointwise cluster(`cluster') agg(event)" not in candidate:
        raise ValueError("bench_c200: legacy comparison must use analytical pointwise event-study inference")
    for name, relative in [("bench_c182", "tools/bench/field/scalebench_f_cell.do"),
                           ("bench_csdidboot", "tools/bench/field/scalebench.do")]:
        call = csdid_call(program(relative, name), name)
        if re.search(r"\b(?:analytical|pointwise)\b", call):
            raise ValueError(f"{name}: preserve the measured legacy/default-bootstrap inference")
        if name == "bench_csdidboot" and "wboot(reps(`reps') rseed(20260729))" not in call:
            raise ValueError("bench_csdidboot: missing measured bootstrap request")

    # Rendering is separate from table generation. Bind the image to its exact
    # source and measured inputs so stale graphics cannot pass with fresh prose.
    fingerprints = json.loads(read("website/assets/img/field-speed.provenance.json"),
                              object_pairs_hook=unique_fields)
    figure_inputs = {
        "r_source_sha256": "tools/bench/field/fig_speed.R",
        "results_sha256": "tools/bench/field/results/scalebench-results.csv",
        "metadata_sha256": "tools/bench/field/results/metadata.json",
        "image_sha256": "website/assets/img/field-speed.png",
    }
    if not isinstance(fingerprints, dict) or set(fingerprints) != set(figure_inputs):
        raise ValueError("speed-figure fingerprint must contain exactly four named input/image hashes")
    for key, relative in figure_inputs.items():
        value = fingerprints[key]
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
            raise ValueError(f"invalid speed-figure SHA256: {key}")
        actual = hashlib.sha256((root / relative).read_bytes()).hexdigest()
        if value != actual:
            raise ValueError(f"speed figure does not match recorded source/input/image: {relative}")

    timing_rows = list(csv.DictReader(read("tools/bench/field/results/news-timings.csv").splitlines()))
    timings = {}
    for row in timing_rows:
        key = (row["claim"], row["detail"])
        value = float(row["seconds"])
        if key in timings or not math.isfinite(value) or value <= 0:
            raise ValueError(f"invalid or duplicate supplementary timing: {key}")
        timings[key] = value
    panel = [timings[("panel350k", f"{method} cov={cov}")]
             for method in ("dr", "reg", "ipw") for cov in ("none", "x")]
    for relative in ("NEWS.md", "website/news.md"):
        news = section(read(relative), "### Performance", "### Legacy commands")
        expect(range_pattern, news, bounds, relative + " ladder range")
        expect(rf"{number}x at five periods and {number}x at forty", news,
               [gain(tables["T"]["5"]), gain(tables["T"]["40"])], relative + " period designs")
        expect(rf"{number}x at three cohorts and {number}x at six", news,
               [gain(tables["G"]["3"]), gain(tables["G"]["6"])], relative + " cohort designs")
        expect(rf"smallest on repeated cross sections,.*?at {number}x\.", news,
               [gain(tables["scheme"]["repeated cross sections"])], relative + " sampling scheme")
        expect(rf"where 2\.0\.0 takes {number} seconds", news,
               [float(tables["n"]["100,000"][2].rstrip("s"))], relative + " million-row ladder")
        expect(rf"one-million-row panel estimates and aggregates the event study in {number} seconds "
               rf"with analytical standard errors, and in {number} seconds", news,
               field_times, relative + " million-row complete workflow")
        expect(rf"350,000-row panel takes between {number} and {number} seconds", news,
               [round(min(panel), 2), round(max(panel), 2)], relative + " separate panel timings")
        expect(rf"400,000-observation repeated cross section with 20 periods and 12 cohorts "
               rf"takes about {number} seconds", news,
               [round(timings[("rcs400k", "T=20 G=12")], 1)], relative + " separate RC timing")
        expect(rf"estat event takes {number} seconds after a 20,000-unit estimation and {number} "
               rf"seconds after 100,000 units", news,
               [round(timings[("estat_event", f"n={n}")], 2) for n in (20000, 100000)],
               relative + " separate aggregation timings")
        expect(rf"199 replications on a 350,000-row panel add about {number} seconds", news,
               [round(timings[("boot199", "added over analytical")], 2)], relative + " bootstrap increment")
        expect(rf"saverif\(\) writes its dataset in about {number} seconds at 20,000 units", news,
               [round(timings[("saverif", "n=20000")], 2)], relative + " file-writing timing")
        if "Separate measurements on 7 August 2026" not in plain(news) or "news-timings.csv" not in news:
            raise ValueError(f"{relative}: supplementary timings need their separate date and source")
except (ValueError, KeyError, IndexError, OSError) as error:
    sys.exit(f"FAIL speed claims: {error}")
print(f"speed claims OK: {checked} summary claims trace to their named measured designs; "
      "timed workflow, process isolation, six inference recipes and separate historical measurements are explicit; "
      "figure matches its source, measured inputs and generated image")
PY
