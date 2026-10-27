#!/usr/bin/env python3
"""Regenerate the reviewed inheritance registry against the authenticated tree."""

import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path(__file__).resolve().parent
UPSTREAM = Path(sys.argv[1]).resolve()
REFERENCE = json.loads((ROOT / "inst/spec/r-oracle-reference.json").read_text())
COMMIT = subprocess.check_output(
    ["git", "-C", str(UPSTREAM), "rev-parse", "HEAD"], text=True
).strip()
if COMMIT != REFERENCE["did_commit"]:
    raise SystemExit("RT081 source checkout differs from the authenticated reference")
TEST_THAT = re.compile(r'test_that\(\s*(["\'])(.+?)\1\s*,', re.S)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path, rows, fields):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fields, quoting=csv.QUOTE_ALL,
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_registry(path, rows, fields):
    write_csv(path, rows, fields)
    path.with_suffix(".json").write_text(json.dumps(rows, indent=2) + "\n")


inventory = []
hashes = {}
for path in sorted((UPSTREAM / "tests/testthat").glob("*.R")):
    source_file = "tests/testthat/" + path.name
    hashes[source_file] = sha(path)
    for match in TEST_THAT.finditer(path.read_text()):
        inventory.append(dict(source_file=source_file,
                              source_sha256=hashes[source_file],
                              source_test=match.group(2).strip()))
inventory_path = ROOT / "inst/spec/upstream-did-tests.csv"
with inventory_path.open("w", newline="") as stream:
    stream.write(f"# did {REFERENCE['did_version']} @ {COMMIT}\n")
    writer = csv.DictWriter(stream, ("source_file", "source_sha256", "source_test"),
                            lineterminator="\n")
    writer.writeheader()
    writer.writerows(inventory)

# These five earlier registries were hand-maintained while their generators
# only wrote numerical oracles. Keep their reviewed definitions as source and
# now reproduce every sibling contract artifact, as the regeneration gate
# requires. The retired skipped tiny-RC test is absent from the reviewed map;
# its historical exclusion record remains as history, not current coverage.
for directory in sorted((SOURCE / "reviewed-contracts").iterdir()):
    for definition in sorted(directory.glob("*.csv")):
        rows = read_csv(definition)
        with definition.open(newline="") as stream:
            fields = next(csv.reader(stream))
        if definition.name == "upstream-test-map.csv":
            for row in rows:
                if row["source_file"].endswith(".R"):
                    row["source_sha256"] = hashes[row["source_file"]]
        target = ROOT / "tests/fixtures/parity" / directory.name / "expected/contract" / definition.name
        write_registry(target, rows, fields)

fixture = ROOT / "tests/fixtures/parity/rt081"
mapping = read_csv(SOURCE / "inheritance.csv")
keys = {(row["source_file"], row["source_test"]) for row in inventory}
for row in mapping:
    if (row["source_file"], row["source_test"]) not in keys:
        raise SystemExit("RT081 definition names an absent upstream test: " + row["source_test"])
    row["source_sha256"] = hashes[row["source_file"]]
map_fields = ("source_file", "source_sha256", "source_test", "mapped_scenario",
              "assertion_family", "coverage_status", "divergence_id")
write_registry(fixture / "expected/contract/upstream-test-map.csv", mapping, map_fields)

exclusions = []
for row in mapping:
    if row["coverage_status"] != "mapped":
        exclusions.append(dict(divergence_id=row["divergence_id"],
                               source_tests=row["source_file"] + "::" + row["source_test"],
                               reason=row["assertion_family"],
                               accepted_behavior="This row describes an inapplicable R-only API or bootstrap request; it claims no Stata implementation."))
write_registry(fixture / "expected/contract/approved-divergence.csv", exclusions,
               ("divergence_id", "source_tests", "reason", "accepted_behavior"))

manifest = dict(
    matrix_id="RT081", fixture_family="upstream-test-inheritance-refresh",
    normative_source=f"did {REFERENCE['did_version']} tests/testthat",
    source_commit=COMMIT, decision_refs=[], tolerance_ids=["EXACT"],
    inputs=[],
    generators=[dict(runtime="R", command="Rscript tools/parity/generators/rt081/generate.R",
                     path="tools/parity/generators/rt081/generate.R",
                     sha256=sha(SOURCE / "generate.R"))],
    runtimes=[dict(name="Python", version=sys.version.split()[0])], rng=None,
    expected_outputs=[dict(path="expected/contract/" + name, schema=schema)
                      for name, schema in (("upstream-test-map.csv", "source-test-map"),
                                           ("upstream-test-map.json", "source-test-map"),
                                           ("approved-divergence.csv", "approved-divergence"),
                                           ("approved-divergence.json", "approved-divergence"))],
    comparison_plan=[dict(actual="Source inventory and reviewed public Stata assertions",
                          expected="expected/contract/upstream-test-map.csv",
                          tolerance_id="EXACT", key_columns=["source_file", "source_test"])],
    approved_divergence=dict(status="approved-exclusion",
                             path="expected/contract/approved-divergence.csv"),
    scope_note="Contract-only registry: 73 new upstream blocks, existing source-map hashes, and the removed historical skipped block. Numerical evidence is supplied by RT077 through RT080 and the refreshed RT040 matrix. R conditional-pretest internals, data.table implementation collisions, exact R flag-resolution messages, custom callbacks and single-draw bootstrap requests are explicitly excluded under the existing public API and bootstrap minimum. This registry does not supply or manufacture numerical expectations.",
)
(fixture / "metadata").mkdir(parents=True, exist_ok=True)
(fixture / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"RT081: {len(inventory)} upstream tests; {len(mapping)} new reviewed mappings, "
      f"{sum(row['coverage_status'] == 'mapped' for row in mapping)} public mappings")
