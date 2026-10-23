#!/usr/bin/env python3
"""Run the published statistical experiments against an immutable engine snapshot.

Examples:
  python3 tools/bench/run-website-simulations.py --workers 3 --output build/site-mc
  python3 tools/bench/run-website-simulations.py --only core,cov,dr,ps2 --workers 3 --output build/site-mc
  python3 tools/bench/run-website-simulations.py --resume --workers 3 --output build/site-mc

Each job has its own bench/src layout and raw outputs. Fixed-seed statistical
jobs may run concurrently; wall-clock benchmarks are deliberately excluded.
Nothing replaces committed results without the separate --promote operation.
"""
from __future__ import annotations
import argparse
import concurrent.futures
import csv
import datetime as dt
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
LOADED_RUNNER_BYTES = Path(__file__).read_bytes()
LOADED_RUNNER_SHA256 = hashlib.sha256(LOADED_RUNNER_BYTES).hexdigest()
MANIFEST = ROOT / "tools/bench/website-simulation-designs.json"
PRODUCERS = ROOT / "tools/bench/website-simulation-producers.json"
BLOCK = re.compile(r"<summary><code>(?P<name>[^<]+)</code>.*?</summary>\s*<pre><code>(?P<body>.*?)</code></pre>", re.S)
PROCESSES = set()
LOCK = threading.Lock()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()


def source_inventory(base):
    return {str(p.relative_to(base)): sha(p) for p in sorted((base / "src").rglob("*")) if p.is_file()}


def verify_campaign_snapshot(campaign, record):
    if source_inventory(campaign / "engine") != record["source_files"]:
        raise RuntimeError("Frozen campaign engine source changed")
    if sha(campaign / "engine/pkg/lcsdid_v2.mlib") != record["compiled_library_sha256"]:
        raise RuntimeError("Frozen compiled engine changed")
    for name, digest in record["published_scripts"].items():
        if sha(campaign / "published-scripts" / name) != digest:
            raise RuntimeError(f"Frozen appendix script changed: {name}")


def verify_receipt(campaign, receipt, config):
    if receipt.get("config_sha256") != canonical_sha(config) or receipt.get("config") != config:
        raise RuntimeError(f"Receipt configuration differs from the prescribed design: {config['id']}")
    if receipt.get("status") != "pass":
        return
    log = Path(receipt["log"])
    if not log.is_file() or sha(log) != receipt["log_sha256"]:
        raise RuntimeError(f"Completed job log changed: {config['id']}")
    if len(receipt.get("outputs", [])) != len(config["outputs"]):
        raise RuntimeError(f"Wrong output count: {config['id']}")
    for name, output in zip(config["outputs"], receipt["outputs"]):
        expected = campaign / "jobs" / config["id"] / "bench" / name
        if Path(output["path"]) != expected or not expected.is_file() or sha(expected) != output["sha256"]:
            raise RuntimeError(f"Completed job output changed: {config['id']}/{name}")
        validate_raw(expected, config)
    for output in receipt.get("derived_outputs", []):
        if not Path(output["path"]).is_file() or sha(output["path"]) != output["sha256"]:
            raise RuntimeError(f"Completed diagnostic output changed: {config['id']}")
    identity = parse_identity(campaign / "jobs" / config["id"] / "bench/identity.txt", campaign / "engine")
    if identity != receipt["identity"]:
        raise RuntimeError(f"Completed job runtime identity changed: {config['id']}")
    if config.get("processors",0) and int(identity["runtime"].get("stata_processors",-1)) != config["processors"]:
        raise RuntimeError(f"Completed job processor setting differs from its design: {config['id']}")


def diagnostic_source_repair(job_id, name, original):
    if (job_id,name) == ("mech","mech.do"):
        old = b'''        capture bench_`pkg', horizons(0) cluster(cl)
        if _rc == 0 & r(ok) == 1 {
            matrix E = r(ES)
            di "MECH A  `pkg'  = " %10.6f E[1,2]
        }
        else di "MECH A  `pkg'  FAILED"'''
        new = b'''        if "`pkg'" == "jwdid" {
            quietly jwdid y, ivar(id) tvar(time) gvar(gvar) cluster(cl)
            quietly estat event, window(0 0)
            matrix J = r(table)
            assert colsof(J) == 1
            assert !missing(J[1,1], J[2,1])
            di "MECH A  jwdid  = " %10.6f J[1,1]
        }
        else {
            capture bench_bjs, horizons(0) cluster(cl)
            assert _rc == 0 & r(ok) == 1
            matrix E = r(ES)
            assert !missing(E[1,2], E[1,3])
            di "MECH A  bjs  = " %10.6f E[1,2]
        }'''
        if original.count(old) != 1:
            raise RuntimeError("Unexpected original single-horizon diagnostic source")
        result = original.replace(old,new)
        old = b'''        local out "`out'  `pkg'=" + string(E[1,2],"%9.6f")'''
        new = b'''        local out = "`out'  `pkg'=" + string(E[1,2],"%9.6f")'''
        if result.count(old) != 1:
            raise RuntimeError("Unexpected original diagnostic string expression")
        return result.replace(old,new)
    if (job_id,name) == ("mech","dgp.do"):
        old = b"local first_g = floor(`t' / 3) + 1"
        new = b"local first_g = max(2, floor(`t' / 3) + 1)"
    elif (job_id,name) == ("eqgate","eqgate.do"):
        old = b"set seed 7654321\n"
        new = old+b"        set sortseed 7654321\n"
    else:
        return original
    if original.count(old) != (2 if job_id == "eqgate" else 1):
        raise RuntimeError(f"Unexpected original source for diagnostic repair: {job_id}/{name}")
    return original.replace(old,new)


def read_prescribed_receipt(campaign, job, smoke, processors):
    original_path = campaign/"jobs"/job["id"]/"receipt.json"
    if not original_path.exists():
        return None
    original = json.loads(original_path.read_text())
    config = job_parameters(job,smoke,processors)
    repair_path = campaign/"diagnostic-repairs"/(job["id"]+".json")
    if not repair_path.exists():
        verify_receipt(campaign,original,config)
        return original
    if job["id"] not in {"mech","eqgate"} or job["kind"] != "diagnostic" or original["status"] != "failed":
        raise RuntimeError("Diagnostic repair is restricted to the two qualified failed diagnostics")
    repair = json.loads(repair_path.read_text())
    failed_log = campaign/"jobs"/job["id"]/"bench/campaign_job.log"
    if repair["original_receipt_sha256"] != sha(original_path) or repair["original_log_sha256"] != sha(failed_log):
        raise RuntimeError(f"Original failed diagnostic evidence changed: {job['id']}")
    replay = Path(repair["replay_campaign"]).resolve()
    if not (campaign/"diagnostic-replays").resolve() in replay.parents:
        raise RuntimeError("Diagnostic replay must remain under its parent campaign")
    if sha(replay/"campaign.json") != repair["replay_campaign_sha256"]:
        raise RuntimeError("Diagnostic replay campaign identity changed")
    parent_record = json.loads((campaign/"campaign.json").read_text())
    replay_record = json.loads((replay/"campaign.json").read_text())
    verify_campaign_snapshot(campaign,parent_record)
    verify_campaign_snapshot(replay,replay_record)
    if replay_record["source_files"] != parent_record["source_files"] or replay_record["compiled_library_sha256"] != parent_record["compiled_library_sha256"] or replay_record["identity"]["processors"] != processors:
        raise RuntimeError("Diagnostic replay engine or processor identity differs")
    if replay_record["published_scripts"].keys() != parent_record["published_scripts"].keys():
        raise RuntimeError("Diagnostic replay script inventory differs")
    changes = {}
    for name in parent_record["published_scripts"]:
        before = (campaign/"published-scripts"/name).read_bytes()
        after = (replay/"published-scripts"/name).read_bytes()
        if after != diagnostic_source_repair(job["id"],name,before):
            raise RuntimeError(f"Unapproved diagnostic source difference: {job['id']}/{name}")
        if before != after:
            changes[name] = dict(original_sha256=hashlib.sha256(before).hexdigest(),replay_sha256=hashlib.sha256(after).hexdigest())
    expected_changes = {"dgp.do","mech.do"} if job["id"] == "mech" else {"eqgate.do"}
    if set(changes) != expected_changes:
        raise RuntimeError("Diagnostic repair must change exactly its qualified scripts")
    path = replay/"jobs"/job["id"]/"receipt.json"
    if sha(path) != repair["replay_receipt_sha256"]:
        raise RuntimeError("Diagnostic replay receipt changed")
    receipt = json.loads(path.read_text())
    if repair["loaded_runner_sha256"] != receipt["loaded_collection_runner_sha256"] or sha(repair["loaded_runner_source_file"]) != repair["loaded_runner_sha256"]:
        raise RuntimeError("Diagnostic replay loaded collector source differs from its startup identity")
    verify_receipt(replay,receipt,config)
    if receipt["status"] != "pass":
        raise RuntimeError("Diagnostic replay did not pass")
    receipt["diagnostic_repair"] = dict(kind=repair["kind"],definition=repair["definition"],source_changes=changes,
        original_failed_receipt_sha256=sha(original_path),original_failed_log_sha256=sha(failed_log),repair_record_sha256=sha(repair_path),
        replay_receipt_sha256=sha(path),loaded_replay_runner_sha256=repair["loaded_runner_sha256"],qualification=repair["qualification"])
    return receipt


def scripts_from_appendix(manifest):
    text = (ROOT / manifest["source_appendix"]).read_text()
    pairs = [(m.group("name").strip(), html.unescape(m.group("body")).rstrip("\n") + "\n") for m in BLOCK.finditer(text)]
    if len(pairs) != manifest["published_script_count"] or len(dict(pairs)) != len(pairs):
        raise RuntimeError("Published script count or uniqueness differs from the design manifest")
    for name, body in pairs:
        if Path(name).name != name:
            raise RuntimeError(f"Unsafe appendix script name: {name}")
        native = ROOT / "tools/bench/field" / name
        if not native.is_file() or native.read_text().rstrip("\n") != body.rstrip("\n"):
            raise RuntimeError(f"Appendix/source drift for {name}; synchronize the appendix first")
    return dict(pairs)


def statistical_script_dependencies(campaign, manifest):
    names = {p.name for p in (campaign/"published-scripts").glob("*.do")}
    pending = [j["script"] for j in manifest["jobs"]]
    reached = set()
    while pending:
        name = pending.pop()
        if name in reached:
            continue
        reached.add(name)
        body = (campaign/"published-scripts"/name).read_text()
        code = "\n".join(line for line in body.splitlines() if not line.lstrip().startswith("*"))
        pending.extend(set(re.findall(r"\b([A-Za-z_][\w-]*\.do)\b",code)) & names - reached)
    return reached


def stata_quote(value):
    value = str(value)
    if any(c in value for c in ('"', '`', '$', '\n', '\r')):
        raise ValueError(f"Unsafe Stata path/argument: {value!r}")
    return '"' + value + '"'


def prepare_campaign(path, manifest, args):
    scripts = scripts_from_appendix(manifest)
    src = source_inventory(ROOT)
    stata_scripts = {name: hashlib.sha256(body.encode()).hexdigest() for name, body in scripts.items() if name.endswith(".do")}
    identity = {"source_tree_sha256": canonical_sha(src), "stata_scripts_sha256": canonical_sha(stata_scripts), "smoke": args.smoke, "processors": args.processors}
    record = path / "campaign.json"
    if record.exists():
        if not args.resume:
            raise RuntimeError(f"Campaign exists: {path}; use --resume to verify and extend this run")
        prior = json.loads(record.read_text())
        if prior["identity"] != identity:
            stable = ("source_tree_sha256","smoke","processors")
            if not args.assemble_only or any(prior["identity"][key] != identity[key] for key in stable):
                raise RuntimeError("Resume refused: current engine or published Stata scripts differ from this campaign")
            differences = {}
            unused_timing = {"optcost.do","rcstime.do","time.do","scalebench_f.sh"}
            statistical_dependencies = statistical_script_dependencies(path,manifest)
            for name,body in scripts.items():
                if (not name.endswith(".do") and name not in unused_timing) or hashlib.sha256(body.encode()).hexdigest() == prior["published_scripts"][name]:
                    continue
                owner = {"dgp.do":"mech","mech.do":"mech","eqgate.do":"eqgate"}.get(name)
                if owner:
                    job = next(j for j in manifest["jobs"] if j["id"] == owner)
                    receipt = read_prescribed_receipt(path,job,args.smoke,args.processors)
                    before = (path/"published-scripts"/name).read_bytes()
                    if not receipt.get("diagnostic_repair") or body.encode() != diagnostic_source_repair(owner,name,before):
                        raise RuntimeError(f"Current diagnostic source has no qualified replay: {name}")
                    role = "qualified isolated diagnostic replay"
                elif name in unused_timing and name not in statistical_dependencies:
                    role = "unused statistical-campaign timing driver; timed separately"
                else:
                    raise RuntimeError(f"Unapproved current Stata-script difference: {name}")
                differences[name] = dict(collection_snapshot_sha256=prior["published_scripts"][name],current_source_sha256=hashlib.sha256(body.encode()).hexdigest(),role=role)
            prior["assembly_current_source_differences"] = differences
        if prior["design_manifest"] != manifest:
            before = prior["design_manifest"]
            old_jobs = {j["id"]: j for j in before["jobs"]}
            new_jobs = {j["id"]: j for j in manifest["jobs"]}
            if ({k:v for k,v in before.items() if k != "jobs"} != {k:v for k,v in manifest.items() if k != "jobs"}
                or not old_jobs.keys() <= new_jobs.keys() or any(new_jobs[k] != v for k,v in old_jobs.items())):
                raise RuntimeError("Resume refused: an existing prescribed design changed")
            prior.setdefault("design_extensions", []).append(dict(added_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                added_jobs=sorted(new_jobs.keys()-old_jobs.keys()),manifest_sha256=sha(MANIFEST)))
            prior["design_manifest"] = manifest
            write_json(record, prior)
        verify_campaign_snapshot(path, prior)
        return prior
    if args.resume:
        raise RuntimeError("--resume needs an existing campaign.json")
    if path.exists() and any(path.iterdir()):
        raise RuntimeError(f"Output directory is not empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    engine = path / "engine"
    engine.mkdir()
    shutil.copytree(ROOT / "src", engine / "src")
    shutil.copytree(ROOT / "pkg", engine / "pkg")
    template = path / "published-scripts"
    template.mkdir()
    for name, body in scripts.items():
        (template / name).write_text(body)
    version = (engine / "src/ado/csdid.ado").read_text().splitlines()[0]
    record_value = {"schema_version": 1, "identity": identity, "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_commit": git("rev-parse", "HEAD"), "source_dirty_paths": git("status", "--short"),
        "source_files": src, "published_scripts": {name: sha(template / name) for name in scripts},
        "package_version_header": version, "compiled_library_sha256": sha(engine / "pkg/lcsdid_v2.mlib"),
        "design_manifest": manifest, "design_manifest_sha256": sha(MANIFEST), "runner_sha256": LOADED_RUNNER_SHA256,
        "stata_binary": args.stata, "historical_parameter_gaps": manifest.get("historical_parameter_gaps", []),
        "promotion": "No committed results replaced by this run."}
    write_json(record, record_value)
    return record_value


def job_parameters(job, smoke, processors=0):
    config = dict(job)
    config["processors"] = processors
    if smoke:
        if not job.get("smoke_parameters"):
            raise RuntimeError(f"{job['id']} has fixed published parameters; choose a parameterized job for --smoke")
        config.update(units=80, reps=1, args=[80, 1, "raw.csv"])
    return config


def identity_driver(engine, processors=0):
    setting = f"set processors {processors}\n" if processors else ""
    return f'''version 15
clear all
set more off
set linesize 255
{setting}local campaign_processors = c(processors)
adopath ++ {stata_quote(engine / "pkg")}
adopath ++ {stata_quote(engine / "src/mata")}
adopath ++ {stata_quote(engine / "src/ado")}
file open ident using "identity.txt", write replace text
file write ident "stata_version=`c(stata_version)'" _n
file write ident "stata_edition=`c(edition_real)'" _n
file write ident "stata_born=`c(born_date)'" _n
file write ident "stata_processors=`c(processors)'" _n
foreach cmd in csdid csdid_stats _csdid_engine_load jwdid did_imputation did_multiplegt_dyn lpdid eventstudyinteract flexdid reghdfe ftools drdid {{
    capture which `cmd'
    capture findfile `cmd'.ado
    if _rc file write ident "package:`cmd'=MISSING" _n
    else file write ident "package:`cmd'=`r(fn)'" _n
}}
capture findfile lmoremata.mlib
if _rc file write ident "package:lmoremata=MISSING" _n
else file write ident "package:lmoremata=`r(fn)'" _n
quietly _csdid_engine_load
mata: st_local("engine_stamp", csdid_mlib_version())
file write ident "engine_stamp=`engine_stamp'" _n
file close ident
'''


def target_driver():
    # Report empirical agreement; the source does not specify an acceptance
    # tolerance for its finite 200k draw, so none is invented here.
    return '''quietly do "fielddgp.do"
dgp_master, n(200000) seed(90001)
file open target using "target-check.csv", write replace text
file write target "h,population_target,empirical_target,difference" _n
forvalues h=0/2 {
    quietly summarize tau if gvar>0 & time==gvar+`h', meanonly
    local target = 2.516666666666667 + 0.6333333333333333*`h'
    local actual = r(mean)
    assert !missing(`actual')
    file write target "`h'," (`target') "," (`actual') "," (`actual'-`target') _n
}
file close target
'''


def diagnostic_export(job_id):
    expressions = {
        "hetx": {"hetx_se_gap_e0_percent": "100*(B2[2,1]/J2[2,1]-1)",
                 "hetx_se_gap_e2_percent": "100*(B2[2,3]/J2[2,3]-1)"},
        "dcdhse": {"dcdh_se_gap_min_percent": "min(100*(E[1,3]/sqrt(V[1,1])-1),100*(E[2,3]/sqrt(V[2,1])-1),100*(E[3,3]/sqrt(V[3,1])-1))",
                   "dcdh_se_gap_max_percent": "max(100*(E[1,3]/sqrt(V[1,1])-1),100*(E[2,3]/sqrt(V[2,1])-1),100*(E[3,3]/sqrt(V[3,1])-1))"}
    }.get(job_id, {})
    if not expressions:
        return ""
    lines = ['file open diagnostic using "diagnostic-values.csv", write replace text',
             'file write diagnostic "key,value" _n']
    for key, expression in expressions.items():
        lines.extend([f"local measured = {expression}", "assert !missing(`measured')",
                      f'''file write diagnostic "{key}," %24.17g (`measured') _n'''])
    return "\n".join(lines + ["file close diagnostic", ""])


def parse_identity(path, engine):
    data = dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)
    resolved = Path(data.get("package:csdid", "")).resolve()
    if resolved != (engine / "src/ado/csdid.ado").resolve():
        raise RuntimeError(f"Wrong csdid resolved: {resolved}")
    header = (engine / "src/ado/csdid.ado").read_text().splitlines()[0]
    expected_version = re.search(r"\b\d+\.\d+\.\d+\b", header).group()
    if data.get("engine_stamp", "").split("|")[0] != expected_version:
        raise RuntimeError(f"Loaded engine stamp differs from frozen command: {data.get('engine_stamp')}")
    required = {"csdid", "csdid_stats", "_csdid_engine_load", "jwdid", "did_imputation", "did_multiplegt_dyn", "lpdid", "eventstudyinteract", "flexdid", "reghdfe", "ftools"}
    missing = sorted(p for p in required if data.get("package:"+p) in {None,"MISSING"})
    if missing:
        raise RuntimeError("Required commands unavailable: " + ", ".join(missing))
    packages = {}
    for key, value in data.items():
        if not key.startswith("package:"):
            continue
        packages[key[8:]] = {"path": value}
        p = Path(value)
        if p.is_file():
            packages[key[8:]].update(sha256=sha(p))
            if p.suffix == ".ado":
                packages[key[8:]]["header"] = p.read_text(errors="replace").splitlines()[:4]
    return {"runtime": {k: v for k, v in data.items() if not k.startswith("package:")}, "packages": packages}


def expected_arms(job_id):
    def cross(regimes, packages):
        return {(r,p) for r in regimes.split() for p in packages.split()}
    base = "balanced varmiss unbalanced"
    options = base + " bal_ok bal_owrong bal_pwrong2"
    mapping = {
        "core": cross(base+" rcs", "csdid jwdid bjs dcdh lpdid") | cross("varmiss unbalanced","csdidpair"),
        "cov": cross("rcs rcsvar","csdid jwdid bjs flexdid"),
        "dr": cross("bal_ok bal_owrong bal_pwrong","csdid_dr csdid_ipw csdid_reg jwdid bjs dcdh lpdid flexdid"),
        "ps2": cross("bal_ps2","csdid_dr csdid_ipw csdid_reg jwdid bjs dcdh lpdid flexdid"),
        "rv": cross("rcsvar","csdid jwdid bjs"), "fx": cross("rcs rcsvar","flexdid"),
        "fxpanel": cross(base,"flexdid"), "lp": cross(options,"lpdid lpdid_rw"),
        "lp4000": cross(options,"lpdid lpdid_rw"), "jw": cross(options,"jwdid jwdid_uc"),
        "bjs": cross(base,"bjs bjs_wtr"), "sa": cross(options,"sa"),
        "ur": cross("unitroot","csdid jwdid bjs dcdh lpdid flexdid"),
        "bands": cross("bands","csdid_band"),
        "figdata": cross("varmiss","csdid jwdid jwdid_uc bjs bjs_wtr dcdh lpdid lpdid_rw sa"),
        "master": cross("master","csdid_reg csdid_dr jwdid jwdid_uc bjs lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh dcdh_tnp sa sa_xt"),
        "ctvar": cross("ctvar","csdid_dr csdid_ipw csdid_reg csdid_dr_nt csdid_ipw_nt csdid_reg_nt jwdid jwdid_uc bjs bjs_wtr dcdh dcdh_tnp lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl sa sa_xt"),
        "cohorthet": cross("cohorthet","csdid_dr csdid_reg jwdid bjs lpdid_rw_ctl dcdh sa csdid_reg_nt csdid_dr_nt sa_xt"),
        "breakhunt": cross("breakB breakC","csdid_dr csdid_ipw csdid_reg sa_xt lpdid_rw_ctl jwdid bjs"),
        "smallnt": cross("smallnt","csdid_dr csdid_dr_nt sa"),
        "ymiss": cross("ymiss_drop ymiss_ymiss","csdid_dr jwdid bjs")}
    return mapping[job_id]


def validate_raw(path, config):
    if not path.is_file() or not path.stat().st_size:
        raise RuntimeError(f"Missing/empty required output: {path}")
    if config["kind"] != "monte_carlo":
        if config["id"] == "eqgate":
            records = list(csv.DictReader(path.open()))
            required = {(str(seed),arm,str(h)) for seed in (90001,90002,90003)
                        for arm in "csdid_reg csdid_dr csdid_reg_nt lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh_tnp sa_xt".split()
                        for h in (0,1,2)}
            keys = {(row["seed"],row["arm"],row["h"]) for row in records}
            if keys != required or len(records) != len(required):
                raise RuntimeError("Literal-command equivalence gate has incomplete/duplicate cells")
            for row in records:
                if any(number(row[name]) is None for name in ("b_branch","b_inline","se_branch","se_inline")):
                    raise RuntimeError(f"Literal-command equivalence has a missing comparison; adjudication required: {row['seed']}/{row['arm']}/{row['h']}")
                if numeric_identity(row["b_branch"]) != numeric_identity(row["b_inline"]) or numeric_identity(row["se_branch"]) != numeric_identity(row["se_inline"]):
                    raise RuntimeError(f"Literal-command equivalence failed: {row['seed']}/{row['arm']}/{row['h']}")
        if config["id"] == "target_check":
            records = list(csv.DictReader(path.open()))
            if len(records) != 3 or {int(row["h"]) for row in records} != {0,1,2} or any(number(row[key]) is None for row in records for key in ("population_target","empirical_target","difference")):
                raise RuntimeError("Population target check must report all three finite horizons")
        return {"path": str(path), "sha256": sha(path)}
    rows = list(csv.DictReader(path.open()))
    required = {"regime", "pkg", "rep", "h", "est", "se"}
    if not rows or not required <= rows[0].keys():
        raise RuntimeError(f"Invalid Monte Carlo schema: {path}")
    expected = set(range(1, config["reps"] + 1))
    arms = {}
    seen = set()
    for row in rows:
        key = (row["regime"], row["pkg"], int(row["rep"]), int(row["h"]))
        if key in seen:
            raise RuntimeError(f"Duplicate raw key: {path}: {key}")
        seen.add(key)
        if int(row["rep"]) not in expected:
            raise RuntimeError(f"Out-of-design replication: {path}: {key}")
        if int(row["h"]) in (0, 1, 2):
            arms.setdefault((row["regime"], row["pkg"]), {}).setdefault(int(row["rep"]), set()).add(int(row["h"]))
    # The published band driver omits all rows when a fit declines; the fixed
    # design still attempted every draw. Keep those omissions in denominators.
    may_omit_failed_draws = config["id"] == "bands"
    if not arms or any((not may_omit_failed_draws and set(reps) != expected) or any(hs != {0, 1, 2} for hs in reps.values()) for reps in arms.values()):
        raise RuntimeError(f"Incomplete attempted replications/horizons: {path}")
    if set(arms) != expected_arms(config["id"]):
        raise RuntimeError(f"Arm roster differs from published design: {path}: missing={expected_arms(config['id'])-set(arms)}, extra={set(arms)-expected_arms(config['id'])}")
    finite_cells = {(r["regime"],r["pkg"],int(r["h"])) for r in rows if int(r["h"]) in (0,1,2) and number(r["est"]) is not None}
    finite_se_cells = {(r["regime"],r["pkg"],int(r["h"])) for r in rows if int(r["h"]) in (0,1,2) and number(r["est"]) is not None and number(r["se"]) is not None}
    expected_empty = {("rcs","dcdh"),("rcs","lpdid")} if config["id"] == "core" else set()
    expected_cells = {(reg,pkg,h) for reg,pkg in set(arms)-expected_empty for h in (0,1,2)}
    missing_estimates = expected_cells-finite_cells
    missing_ses = expected_cells-finite_se_cells
    if config["reps"] > 1 and (missing_estimates or missing_ses):
        raise RuntimeError(f"A supported horizon has no finite estimate or standard error; adjudicate captured failures before publication: {path}: estimates={sorted(missing_estimates)}, standard_errors={sorted(missing_ses)}")
    return {"path": str(path), "sha256": sha(path), "rows": len(rows), "attempted_arms": len(arms), "replications": config["reps"]}


def run_job(campaign, job, args):
    config = job_parameters(job, args.smoke, args.processors)
    jobdir = campaign / "jobs" / job["id"]
    receipt = jobdir / "receipt.json"
    config_sha = canonical_sha(config)
    if receipt.exists() and args.resume:
        prior = json.loads(receipt.read_text())
        if prior.get("status") == "running":
            raise RuntimeError(f"Job {job['id']} has a running receipt; wait for that campaign process before resuming")
        if prior.get("status") == "pass":
            verify_receipt(campaign, prior, config)
            print(f"reuse {job['id']}: verified fresh campaign output", flush=True)
            return prior
    if jobdir.exists():
        archive = campaign / "incomplete" / (job["id"] + "-" + str(time.time_ns()))
        archive.parent.mkdir(exist_ok=True)
        jobdir.rename(archive)
    bench = jobdir / "bench"
    bench.mkdir(parents=True)
    for script in (campaign / "published-scripts").iterdir():
        shutil.copy2(script, bench / script.name)
    (jobdir / "src").symlink_to(campaign / "engine/src", target_is_directory=True)
    cmdargs = [str((bench / v).resolve()) if v == "raw.csv" else str(v) for v in config.get("args", [])]
    body = target_driver() if config["kind"] == "target_check" else "do " + stata_quote(bench / config["script"]) + " " + " ".join(stata_quote(v) for v in cmdargs) + "\n"
    driver = bench / "campaign_job.do"
    driver.write_text(identity_driver(campaign / "engine", args.processors) + body + diagnostic_export(job["id"]) + '\nassert c(processors) == `campaign_processors\'\n' + f'display "WEBSITE-SIMULATION-COMPLETE {job["id"]}"\n')
    result = {"id": job["id"], "config": config, "config_sha256": config_sha, "loaded_collection_runner_sha256": LOADED_RUNNER_SHA256, "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "status": "running"}
    write_json(receipt, result)
    print(f"start {job['id']}: {config.get('units', 'fixed')} units / {config.get('reps', 'fixed')} replications", flush=True)
    try:
        with (jobdir / "launch.txt").open("w") as launch:
            proc = subprocess.Popen([args.stata, "-b", "do", str(driver)], cwd=bench, stdout=launch, stderr=subprocess.STDOUT)
            with LOCK:
                PROCESSES.add(proc)
            try:
                proc.wait(timeout=args.timeout)
            finally:
                with LOCK:
                    PROCESSES.discard(proc)
        log = bench / "campaign_job.log"
        if proc.returncode != 0:
            raise RuntimeError(f"Stata process exit {proc.returncode}")
        subprocess.run(["bash", str(ROOT / "tools/release/check-stata-log-tail.sh"), str(log)], check=True, capture_output=True, text=True)
        text = log.read_text(errors="replace")
        if not re.search(r"^WEBSITE-SIMULATION-COMPLETE " + re.escape(job["id"]) + r"\s*$", text, re.M) or re.search(r"^r\(\d+\);\s*$|^assertion is false\s*$", text, re.M):
            raise RuntimeError("Missing completion marker or uncaught Stata error")
        if config.get("completion") and config["completion"] not in text:
            raise RuntimeError(f"Missing script completion marker {config['completion']}")
        result["identity"] = parse_identity(bench / "identity.txt", campaign / "engine")
        result["outputs"] = [validate_raw(bench / name, config) for name in config["outputs"]]
        if (bench / "diagnostic-values.csv").exists():
            result["derived_outputs"] = [{"path": str(bench / "diagnostic-values.csv"), "sha256": sha(bench / "diagnostic-values.csv")}]
        result.update(status="pass", log=str(log), log_sha256=sha(log))
        print(f"done {job['id']}: {sum(o.get('rows', 0) for o in result['outputs'])} raw rows", flush=True)
    except Exception as exc:
        if 'proc' in locals() and proc.poll() is None:
            proc.kill(); proc.wait()
        result.update(status="failed", error=str(exc))
        print(f"FAIL {job['id']}: {exc} (inspect {jobdir})", flush=True)
    result["finished_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    write_json(receipt, result)
    return result


def number(value):
    if value.strip().lower() in {"", ".", "na", "nan"}:
        return None
    result = float(value)
    if not math.isfinite(result):
        raise RuntimeError(f"Nonfinite exported value: {value!r}")
    return result


def numeric_identity(value):
    n = number(value)
    return None if n is None else n.hex()


def population_truth(regime, h):
    if h >= 1000:
        g, t = divmod(h, 1000)
        return g - 2 + .5 * (t - g)
    if h == 99:
        return 2.5
    base, slope = {"master": (151 / 60, 19 / 30), "cohorthet": (151 / 60, 19 / 30), "breakC": (2.0945, .556)}.get(regime, (2., .5))
    return base + slope * h


def calculate_metrics(rows, repetitions):
    buckets = {}
    for row in rows:
        h = int(row["h"])
        if h not in (0, 1, 2, 99) and h < 1000:
            continue
        buckets.setdefault((row["regime"], row["pkg"], h), []).append(row)
    result = []
    for (regime, pkg, h), records in sorted(buckets.items()):
        observed = [(number(r["est"]), number(r["se"])) for r in records]
        finite = [(e, s) for e, s in observed if e is not None]
        estimates = [e for e, _ in finite]
        ses = [s for _, s in finite if s is not None]
        eligible = [(e, s) for e, s in finite if s is not None and s > 0]
        truth = population_truth(regime, h)
        hit = sum(abs(e-truth) <= 1.959964*s for e, s in eligible)
        mean = statistics.mean(estimates) if estimates else None
        sd = statistics.stdev(estimates) if len(estimates)>1 else None
        mean_se = statistics.mean(ses) if ses else None
        result.append(dict(regime=regime, pkg=pkg, h=h, truth=truth,
            attempted=repetitions, observed_rows=len(records), finite_estimates=len(estimates), finite_se=len(ses),
            finite_positive_se=len(eligible), declined_estimates=repetitions-len(estimates),
            bias=mean-truth if mean is not None else None,
            sd=sd,bias_mcse=sd/math.sqrt(len(estimates)) if sd is not None else None,
            rmse=math.sqrt(statistics.mean((e-truth)**2 for e in estimates)) if estimates else None,
            mean_se=mean_se,mean_se_to_sd_ratio=mean_se/sd if mean_se is not None and sd is not None and sd>0 else None,
            coverage=hit/len(eligible) if eligible else None, coverage_hits=hit, coverage_denominator=len(eligible)))
    return result


def paired_metrics(rows, dataset, repetitions):
    indexed = {(r["regime"],r["pkg"],int(r["h"]),int(r["rep"])):number(r["est"]) for r in rows}
    result = []
    for regime in sorted({r["regime"] for r in rows}):
        packages = {r["pkg"] for r in rows if r["regime"] == regime}
        pairs = [("jwdid","bjs"),("jwdid","jwdid_uc")]
        if (dataset,regime) == ("sampling_main","balanced"):
            pairs.append(("csdid","dcdh"))
        for left,right in pairs:
            if not {left,right} <= packages:
                continue
            for h in (0,1,2):
                left_rows = {i:indexed.get((regime,left,h,i)) for i in range(1,repetitions+1)}
                right_rows = {i:indexed.get((regime,right,h,i)) for i in range(1,repetitions+1)}
                lset = {i for i,v in left_rows.items() if v is not None}
                rset = {i for i,v in right_rows.items() if v is not None}
                differences = [left_rows[i]-right_rows[i] for i in sorted(lset&rset)]
                result.append(dict(dataset_id=dataset,regime=regime,left_pkg=left,right_pkg=right,h=h,attempted=repetitions,
                    matched_estimates=len(differences),missing_left_only=len(rset-lset),missing_right_only=len(lset-rset),missing_both=repetitions-len(lset|rset),
                    max_abs_estimate_difference=max(map(abs,differences)) if differences else None,
                    mean_abs_estimate_difference=statistics.mean(map(abs,differences)) if differences else None,
                    mean_signed_estimate_difference=statistics.mean(differences) if differences else None))
    return result


def ps2_decline_metrics(rows, repetitions):
    if not any(r["regime"] == "bal_ps2" and r["pkg"] in {"csdid_ipw","csdid_dr"} for r in rows):
        return [],[]
    nodes = {}
    all_reps = set(range(1,repetitions+1))
    for pkg in ("csdid_ipw","csdid_dr"):
        for h in (1,5006):
            selected = {int(r["rep"]):(number(r["est"]),number(r["se"])) for r in rows if (r["regime"],r["pkg"],int(r["h"])) == ("bal_ps2",pkg,h)}
            nodes[(pkg,h)] = selected
    sets = []
    comparisons = []
    for (pkg,h), selected in sorted(nodes.items()):
        finite = {i for i,(e,s) in selected.items() if e is not None}
        sets.append(dict(dataset_id="covariates_panel",regime="bal_ps2",pkg=pkg,h=h,attempted=repetitions,
            finite_estimate_reps=sorted(finite),missing_estimate_reps=sorted(all_reps-finite),
            finite_se_reps=sorted(i for i,(e,s) in selected.items() if e is not None and s is not None)))
    keys = sorted(nodes)
    for j,left in enumerate(keys):
        for right in keys[j+1:]:
            ls = {i for i,(e,s) in nodes[left].items() if e is not None}
            rs = {i for i,(e,s) in nodes[right].items() if e is not None}
            both = ls&rs
            item = dict(dataset_id="covariates_panel",regime="bal_ps2",left_pkg=left[0],left_h=left[1],right_pkg=right[0],right_h=right[1],attempted=repetitions,conditional_estimates=len(both),
                both_finite_estimate_reps=sorted(both),both_missing_estimate_reps=sorted(all_reps-(ls|rs)),left_missing_only_reps=sorted(rs-ls),right_missing_only_reps=sorted(ls-rs))
            for side,key in (("left",left),("right",right)):
                values = [nodes[key][i][0] for i in sorted(both)]
                ses = [nodes[key][i][1] for i in sorted(both) if nodes[key][i][1] is not None]
                truth = population_truth("bal_ps2",key[1])
                item.update({"truth_"+side:truth,"conditional_bias_"+side:statistics.mean(values)-truth if values else None,
                             "conditional_mean_se_"+side:statistics.mean(ses) if ses else None,"conditional_finite_se_"+side:len(ses)})
            comparisons.append(item)
    return sets,comparisons


def joint_metric(rows, dataset, regime, pkg, interval, repetitions):
    by_rep = {}
    for row in rows:
        if row["regime"] != regime or row["pkg"] != pkg:
            continue
        h = int(row["h"])
        if interval == "uniform_band":
            if h not in (400,401,402):
                continue
            lo, hi = number(row["est"]), number(row["se"])
            if lo is not None and hi is not None:
                by_rep.setdefault(int(row["rep"]), {})[h-400] = (lo,hi)
        elif h in (0,1,2):
            e, s = number(row["est"]), number(row["se"])
            if e is not None and s is not None and s > 0:
                by_rep.setdefault(int(row["rep"]), {})[h] = (e-1.959964*s,e+1.959964*s)
    complete = [v for v in by_rep.values() if set(v)=={0,1,2}]
    hit = sum(all(v[h][0] <= 2+.5*h <= v[h][1] for h in (0,1,2)) for v in complete)
    return dict(dataset_id=dataset, regime=regime, pkg=pkg, interval=interval,
                hit=hit,n=len(complete),attempted=repetitions,coverage=hit/len(complete) if complete else None)


def scalar_diagnostics(receipts):
    result = {}
    for receipt in receipts:
        if receipt["status"] != "pass":
            continue
        files = {Path(o["path"]).name: Path(o["path"]) for o in receipt.get("outputs", []) + receipt.get("derived_outputs", [])}
        def record(key, value, path):
            if value is None or not math.isfinite(value):
                raise RuntimeError(f"Nonfinite diagnostic: {key}")
            result[key] = dict(value=value, source_file=str(path), sha256=sha(path))
        if "diagnostic-values.csv" in files:
            path = files["diagnostic-values.csv"]
            for row in csv.DictReader(path.open()):
                record(row["key"], number(row["value"]), path)
        if "tnptest.csv" in files:
            path = files["tnptest.csv"]
            rows = [r for r in csv.DictReader(path.open()) if r["variant"] == "tnp_x1" and int(r["h"]) == 2]
            values = [number(r["est"]) for r in rows]
            values = [v for v in values if v is not None]
            if values:
                record("tnp_x1_e2_bias", statistics.mean(values)-3, path)
                result["tnp_x1_e2_bias"].update(attempted=100, finite_estimates=len(values))
        if "sa_se.csv" in files:
            path = files["sa_se.csv"]
            values = [number(r["max_absdiff_b"]) for r in csv.DictReader(path.open())]
            values = [v for v in values if v is not None]
            if values:
                record("sa_balanced_max_abs_point_difference", max(values), path)
        if "target-check.csv" in files:
            path = files["target-check.csv"]
            records = list(csv.DictReader(path.open()))
            agreements = 0
            for row in records:
                h = int(row["h"])
                population = number(row["population_target"])
                empirical = number(row["empirical_target"])
                for suffix, value in (("population",population),("empirical",empirical),("difference",number(row["difference"]))):
                    record(f"target_check_e{h}_{suffix}",value,path)
                agreements += f"{empirical:.3f}" == f"{population:.3f}"
            record("target_check_three_decimal_agreements",agreements,path)
            result["target_check_three_decimal_agreements"]["definition"] = "Number of horizons 0,1,2 whose exported empirical and population targets have equal three-decimal representations."
    return result


def dataset_arm(config, regime, manifest):
    dataset = config["dataset"]
    if dataset == "options":
        dataset = "covariates_panel" if regime.startswith("bal_") else "sampling_main"
    return dataset, manifest.get("dataset_aliases", {}).get(regime, regime)


def producer_roster(manifest, policy):
    roster = {}
    for job in manifest["jobs"]:
        if job["kind"] != "monte_carlo":
            continue
        for regime, pkg in expected_arms(job["id"]):
            dataset, regime = dataset_arm(job,regime,manifest)
            roster.setdefault((dataset,regime,pkg),set()).add(job["id"])
    registered = {}
    for entry in policy["overlaps"]:
        key = (entry["dataset_id"],entry["regime"],entry["pkg"])
        if key in registered or set(entry["registered_producers"]) != roster.get(key) or entry["canonical_producer"] not in roster[key]:
            raise RuntimeError(f"Invalid registered producer ownership: {key}")
        registered[key] = entry
    if set(registered) != {key for key,jobs in roster.items() if len(jobs)>1}:
        raise RuntimeError("Producer policy must register every and only prescribed overlap")
    owners = {key:registered[key]["canonical_producer"] if key in registered else next(iter(jobs)) for key,jobs in roster.items()}
    return roster, owners


def canonical_rows(receipts, manifest, policy):
    grouped = {}
    repetitions = {}
    contributors = {}
    produced = {}
    roster, owners = producer_roster(manifest,policy)
    for receipt in receipts:
        if receipt["status"] != "pass" or receipt["config"]["kind"] != "monte_carlo":
            continue
        config = receipt["config"]
        raw = Path(receipt["outputs"][0]["path"])
        for row in csv.DictReader(raw.open()):
            dataset,row["regime"] = dataset_arm(config,row["regime"],manifest)
            arm = (dataset,row["regime"],row["pkg"])
            if receipt["id"] not in roster.get(arm,set()):
                raise RuntimeError(f"Unregistered source producer: {arm}/{receipt['id']}")
            if dataset in repetitions and repetitions[dataset] != config["reps"]:
                raise RuntimeError(f"Mixed replication counts in {dataset}")
            repetitions[dataset] = config["reps"]
            key = (row["regime"], row["pkg"], int(row["rep"]), int(row["h"]))
            producer_key = (dataset,receipt["id"])
            if key in produced.setdefault(producer_key,{}):
                raise RuntimeError(f"Within-producer duplicate: {producer_key}/{key}")
            produced[producer_key][key] = row
            if receipt["id"] == owners[arm]:
                grouped.setdefault(dataset,{})[key] = row
                contributors.setdefault(dataset,set()).add(receipt["id"])
    comparisons = []
    for entry in policy["overlaps"]:
        dataset,regime,pkg = (entry[k] for k in ("dataset_id","regime","pkg"))
        canonical = entry["canonical_producer"]
        left = produced.get((dataset,canonical))
        if left is None:
            continue  # Partial assemblies never substitute the option driver's baseline.
        left = {k:r for k,r in left.items() if k[:2] == (regime,pkg)}
        for other in entry["registered_producers"]:
            if other == canonical or (dataset,other) not in produced:
                continue
            right = {k:r for k,r in produced[(dataset,other)].items() if k[:2] == (regime,pkg)}
            if not right.keys() <= left.keys():
                raise RuntimeError(f"Noncanonical producer has unmatched baseline keys: {dataset}/{regime}/{pkg}/{other}")
            keys = sorted(right)
            item = dict(dataset_id=dataset,regime=regime,pkg=pkg,canonical_producer=canonical,comparison_producer=other,
                compared_rows=len(keys),canonical_rows=len(left),comparison_rows=len(right),
                identical_numeric_rows=sum(all(numeric_identity(left[k][f])==numeric_identity(right[k][f]) for f in ("est","se")) for k in keys),metrics=[])
            for field in ("est","se"):
                finite = [(number(left[k][field]),number(right[k][field])) for k in keys]
                item[field+"_missingness_mismatches"] = sum((a is None)!=(b is None) for a,b in finite)
                differences = [abs(a-b) for a,b in finite if a is not None and b is not None]
                item[field+"_finite_pairs"] = len(differences)
                item[field+"_different_doubles"] = sum(numeric_identity(left[k][field]) != numeric_identity(right[k][field]) for k in keys)
                item[field+"_max_abs_difference"] = max(differences) if differences else None
                if item[field+"_missingness_mismatches"]:
                    raise RuntimeError(f"Cross-producer missingness requires adjudication: {dataset}/{regime}/{pkg}/{field}")
            lm = calculate_metrics([left[k] for k in keys],repetitions[dataset])
            rm = calculate_metrics([right[k] for k in keys],repetitions[dataset])
            for a,b in zip(lm,rm):
                if (a["regime"],a["pkg"],a["h"]) != (b["regime"],b["pkg"],b["h"]):
                    raise RuntimeError("Cross-producer summary horizon mismatch")
                fields = ("bias","sd","rmse","mean_se","coverage")
                rounded = lambda value: None if value is None else f"{value:.3f}"
                item["metrics"].append(dict(h=a["h"],canonical={f:a[f] for f in fields},comparison={f:b[f] for f in fields},
                    three_decimal_differences=[f for f in fields if rounded(a[f]) != rounded(b[f])]))
            comparisons.append(item)
    return grouped,repetitions,contributors,comparisons


def summary_postprocessors(campaign):
    result = {}
    for name in ("mcsum.py","bandsum.py"):
        original = (campaign/"published-scripts"/name).read_bytes()
        source = original
        role = "unchanged frozen collection postprocessor"
        if name == "mcsum.py":
            source = (ROOT/"tools/bench/field"/name).read_bytes()
            expected = original.replace(b"(2.516667, 0.633333)",b"(151 / 60, 19 / 30)")
            if source != expected:
                raise RuntimeError("Summary postprocessor differs beyond the exact closed-form target correction")
            if source != original:
                role = "exact closed-form master/cohorthet population targets; no raw-data or DGP change"
        digest = hashlib.sha256(source).hexdigest()
        path = campaign/"postprocessing-sources"/digest/name
        if path.exists():
            if path.read_bytes() != source:
                raise RuntimeError("Immutable summary postprocessor snapshot changed")
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(source)
        result[name] = dict(file=str(path),sha256=digest,collection_snapshot_sha256=hashlib.sha256(original).hexdigest(),definition=role)
    return result


def assemble_statistics(campaign, receipts, manifest, status, extra_diagnostics=None, source_differences=None):
    postprocessors = summary_postprocessors(campaign)
    policy = json.loads(PRODUCERS.read_text())
    grouped,repetitions,contributors,comparisons = canonical_rows(receipts,manifest,policy)
    diagnostic_jobs = {r["id"]:{"config":r["config"],"log_file":r["log"],"log_sha256":r["log_sha256"],"outputs":r["outputs"]+r.get("derived_outputs",[])}
                       for r in receipts if r["status"] == "pass" and r["config"]["kind"] != "monte_carlo"}
    outdir = campaign / "assembled"
    outdir.mkdir(exist_ok=True)
    groups = {}
    pairs = []
    decline_sets = []
    decline_comparisons = []
    for dataset, keyed in sorted(grouped.items()):
        rows = [keyed[key] for key in sorted(keyed)]
        path = outdir / (dataset + ".csv")
        with path.open("w",newline="") as f:
            writer = csv.DictWriter(f,fieldnames=["regime","pkg","rep","h","est","se"])
            writer.writeheader(); writer.writerows(rows)
        configs = [r["config"] for r in receipts if r["id"] in contributors[dataset]]
        sizes = {c["units"] for c in configs}
        if len(sizes) != 1:
            raise RuntimeError(f"Mixed sample sizes require distinct dataset identities: {dataset}")
        groups[dataset] = dict(design=dataset,n=sizes.pop(),reps=repetitions[dataset],
            raw_file=str(path),sha256=sha(path),rows=len(rows),source_jobs=sorted(contributors[dataset]),
            identical_duplicate_rows_collapsed=sum(c["identical_numeric_rows"] for c in comparisons if c["dataset_id"]==dataset),
            noncanonical_baseline_rows_retained_in_job_raw=sum(c["compared_rows"] for c in comparisons if c["dataset_id"]==dataset),
            metrics=calculate_metrics(rows,repetitions[dataset]))
        pairs.extend(paired_metrics(rows,dataset,repetitions[dataset]))
        if dataset == "covariates_panel":
            decline_sets,decline_comparisons = ps2_decline_metrics(rows,repetitions[dataset])
        summary = outdir / ("summary-"+dataset+".txt")
        proc = subprocess.run([sys.executable,postprocessors["mcsum.py"]["file"],str(path)],capture_output=True,text=True)
        summary.write_text(proc.stdout + proc.stderr)
        if proc.returncode or "Traceback" in proc.stderr:
            raise RuntimeError(f"Monte Carlo summary failed: {summary}")
    joints = []
    if "bands" in grouped:
        br = list(grouped["bands"].values())
        for interval in ("uniform_band","pointwise"):
            joints.append(joint_metric(br,"bands","bands","csdid_band",interval,repetitions["bands"]))
    if "sampling_main" in grouped:
        sr = list(grouped["sampling_main"].values())
        for pkg in sorted({r["pkg"] for r in sr if r["regime"]=="balanced"}):
            joints.append(joint_metric(sr,"sampling_main","balanced",pkg,"pointwise",repetitions["sampling_main"]))
    if {"bands","sampling_main"} <= groups.keys():
        proc = subprocess.run([sys.executable,postprocessors["bandsum.py"]["file"],groups["bands"]["raw_file"],groups["sampling_main"]["raw_file"]],capture_output=True,text=True)
        (outdir/"summary-bands.txt").write_text(proc.stdout+proc.stderr)
        if proc.returncode:
            raise RuntimeError("Joint coverage summary failed")
    aliases = {"reliability-summary.txt": "sampling_main", "summary-mc_cov.txt": "covariates_rc",
               "summary-mc_dr.txt": "covariates_panel", "summary-mc_master.txt": "master", "summary-mc_ur.txt": "unitroot"}
    for filename, dataset in aliases.items():
        if dataset in groups:
            shutil.copy2(outdir/("summary-"+dataset+".txt"),outdir/filename)
    if "covariates_panel" in grouped:
        rows = [row for row in grouped["covariates_panel"].values() if row["regime"] == "bal_ps2"]
        if rows:
            path = outdir/"covariates_panel_ps2.csv"
            with path.open("w",newline="") as stream:
                writer = csv.DictWriter(stream,fieldnames=["regime","pkg","rep","h","est","se"])
                writer.writeheader(); writer.writerows(rows)
            proc = subprocess.run([sys.executable,postprocessors["mcsum.py"]["file"],str(path)],capture_output=True,text=True)
            (outdir/"summary-mc_ps2.txt").write_text(proc.stdout+proc.stderr)
            if proc.returncode:
                raise RuntimeError("Propensity-score summary failed")
    provenance = json.loads((campaign/"campaign.json").read_text())
    provenance["postprocessing_runner_sha256"] = LOADED_RUNNER_SHA256
    provenance["summary_postprocessors"] = postprocessors
    if source_differences:
        provenance["assembly_current_source_differences"] = source_differences
    recovery_file = campaign/"collector-source-recovery.json"
    if recovery_file.exists():
        recovery = json.loads(recovery_file.read_text())
        if recovery["campaign_runner_sha256"] != provenance["runner_sha256"] or sha(recovery["loaded_source_file"]) != recovery["loaded_source_sha256"] or recovery["loaded_source_sha256"] != provenance["runner_sha256"]:
            raise RuntimeError("Recovered collection source does not match the recorded startup module")
        provenance["collection_runner_recovery"] = recovery
    diagnostics = scalar_diagnostics(receipts)
    for dataset,n in (("sampling_main",1000),("lp4000",4000)):
        if dataset not in groups:
            continue
        match = [r for r in groups[dataset]["metrics"] if (r["regime"],r["pkg"],r["h"]) == ("balanced","lpdid",0)]
        if len(match) == 1 and match[0]["bias"] is not None:
            for field in ("bias","bias_mcse"):
                if match[0][field] is not None:
                    diagnostics[f"lpdid_n{n}_{field}"] = dict(value=match[0][field],source_file=groups[dataset]["raw_file"],sha256=groups[dataset]["sha256"],definition=f"Balanced no-covariate LP event-time 0 at N={n}; bias is mean estimate minus target 2.0, bias MCSE is sample SD/sqrt(finite estimates).")
    if "master" in groups:
        match = [r for r in groups["master"]["metrics"] if (r["pkg"],r["h"]) == ("jwdid_uc",2)]
        if len(match) == 1 and match[0]["mean_se_to_sd_ratio"] is not None:
            diagnostics["master_jwdid_uc_e2_mean_se_sd_ratio"] = dict(value=match[0]["mean_se_to_sd_ratio"],source_file=groups["master"]["raw_file"],sha256=groups["master"]["sha256"],definition="Mean finite reported SE divided by sample SD of finite estimates for master/jwdid_uc/event-time2; component denominators are recorded in the metric.")
    diagnostic_campaigns = []
    if extra_diagnostics:
        envelope = json.loads(extra_diagnostics.read_text())
        supplement = envelope.get("provenance", {})
        if supplement.get("source_tree_sha256") != provenance["identity"]["source_tree_sha256"] or supplement.get("compiled_library_sha256") != provenance["compiled_library_sha256"]:
            raise RuntimeError("Supplemental diagnostic engine differs from the frozen campaign")
        for stem in ("script", "identity"):
            path = Path(supplement[stem+"_file"])
            if not path.is_absolute():
                path = (extra_diagnostics.parent/path).resolve()
            if not path.is_file() or sha(path) != supplement[stem+"_sha256"]:
                raise RuntimeError(f"Supplemental diagnostic {stem} identity changed")
            supplement[stem+"_file"] = str(path)
        supplement["identity"] = parse_identity(Path(supplement["identity_file"]), campaign / "engine")
        if int(supplement["identity"]["runtime"].get("stata_processors",-1)) != provenance["identity"]["processors"]:
            raise RuntimeError("Supplemental diagnostic processor setting differs from the campaign")
        for dependency in supplement.get("dependencies", []):
            if dependency["sha256"] != provenance["published_scripts"].get(dependency["name"]):
                raise RuntimeError(f"Supplemental published dependency differs: {dependency['name']}")
        for supporting in supplement.get("supporting_files", []):
            path = Path(supporting["file"])
            if not path.is_absolute():
                path = (extra_diagnostics.parent/path).resolve()
            if not path.is_file() or sha(path) != supporting["sha256"]:
                raise RuntimeError(f"Supplemental supporting evidence changed: {path.name}")
            supporting["file"] = str(path)
        supplement["envelope_sha256"] = sha(extra_diagnostics)
        diagnostic_campaigns.append(supplement)
        additions = envelope["diagnostics"]
        for key, value in additions.items():
            path = Path(value["source_file"])
            if not path.is_absolute():
                path = (extra_diagnostics.parent/path).resolve()
            if not path.is_file() or sha(path) != value["sha256"] or not isinstance(value["value"], (int,float)) or not math.isfinite(value["value"]):
                raise RuntimeError(f"Invalid externally collected fresh diagnostic: {key}")
            value["source_file"] = str(path)
            if key in diagnostics and diagnostics[key] != value:
                raise RuntimeError(f"Conflicting diagnostic sources: {key}")
            diagnostics[key] = value
    document = dict(schema_version=1,status=status,provenance=provenance,groups=groups,joint_metrics=joints,paired_metrics=pairs,decline_sets=decline_sets,decline_set_comparisons=decline_comparisons,diagnostics=diagnostics,diagnostic_jobs=diagnostic_jobs,diagnostic_campaigns=diagnostic_campaigns,
        diagnostic_repairs={r["id"]:r["diagnostic_repair"] for r in receipts if r.get("diagnostic_repair")},
        coverage_policy="Coverage conditions on finite estimates with finite positive standard errors, as in the published summarizer; attempted and declined counts retain every configured draw.",
        duplicate_policy=policy,producer_policy_sha256=sha(PRODUCERS),cross_producer_comparisons=comparisons,raw_jobs=receipts)
    write_json(campaign/"website-statistics.json",document)
    return document


def deterministic_gzip(source, destination):
    import gzip
    destination.parent.mkdir(parents=True,exist_ok=True)
    with source.open("rb") as inp, destination.open("wb") as raw:
        with gzip.GzipFile(filename="",mode="wb",fileobj=raw,mtime=0) as zipped:
            shutil.copyfileobj(inp,zipped)


def publish_diagnostic_support(source, destination):
    import gzip
    original = source.read_bytes()
    payload = original
    if source.suffix in {".log", ".do"}:
        text = original.decode()
        logical = re.sub(r"\n>\s?", "", text)
        public_lines = []
        license_block = False
        for line in logical.splitlines(keepends=True):
            if re.match(r"\s*(?:Stata license|Serial number|Licensed to)\s*:",line,re.I):
                if not license_block:
                    public_lines.append("[Stata license details removed]\n")
                license_block = True
                continue
            if license_block:
                if line.strip() and not line.lstrip().startswith("Notes:"):
                    continue
                license_block = False
            public_lines.append(line)
        without_license = "".join(public_lines)
        if without_license != logical or "/Users/" in logical or str(ROOT) in logical or str(Path.home()) in logical:
            logical = without_license
            logical = logical.replace(str(ROOT), "PROJECT_ROOT").replace(str(Path.home()), "USER_HOME")
            logical = re.sub(r"/Users/[^/\s\"']+", "USER_HOME", logical)
            payload = logical.encode()
    destination.parent.mkdir(parents=True,exist_ok=True)
    with destination.open("wb") as raw:
        with gzip.GzipFile(filename="",mode="wb",fileobj=raw,mtime=0) as zipped:
            zipped.write(payload)
    result = dict(sha256=sha(destination),uncompressed_sha256=hashlib.sha256(payload).hexdigest(),original_source_sha256=hashlib.sha256(original).hexdigest())
    if payload != original:
        result["publication_transform"] = "Portable text view: license details removed, Stata continuation lines joined and workstation directories replaced by PROJECT_ROOT/USER_HOME. Original bytes and digest remain in the private campaign record; numeric CSVs are unchanged."
    return result


def write_staged_statistics(campaign, document, results):
    if document["status"] != "pass" or document["provenance"]["identity"]["smoke"]:
        raise RuntimeError("Promotion requires a complete successful non-smoke campaign")
    if document["producer_policy_sha256"] != sha(PRODUCERS) or document["duplicate_policy"] != json.loads(PRODUCERS.read_text()):
        raise RuntimeError("Producer policy changed after statistical assembly")
    promoted = json.loads(json.dumps(document))
    locations = {}
    for group, spec in promoted["groups"].items():
        src = Path(spec["raw_file"])
        dest = results/"raw/groups"/(group+".csv.gz")
        deterministic_gzip(src,dest)
        locations[str(src)] = str(dest.relative_to(results))
        spec.update(raw_file=str(dest.relative_to(results)),sha256=sha(dest),uncompressed_sha256=sha(src))
    for receipt in promoted["raw_jobs"]:
        for output in receipt.get("outputs",[]) + receipt.get("derived_outputs",[]):
            src = Path(output["path"])
            dest = results/"raw/jobs"/receipt["id"]/(src.name+".gz")
            deterministic_gzip(src,dest)
            locations[str(src)] = str(dest.relative_to(results))
            output.update(path=str(dest.relative_to(results)),sha256=sha(dest),uncompressed_sha256=sha(src))
        # Paths in runtime receipts describe a workstation, not the experiment.
        receipt.pop("log",None)
        if "collection_runner_sha256" in receipt and "loaded_collection_runner_sha256" not in receipt:
            receipt["runner_file_sha256_at_receipt"] = receipt.pop("collection_runner_sha256")
            receipt["runner_hash_semantics"] = "Legacy receipt observes the on-disk runner at receipt time; actual single collector source is identified by campaign runner_sha256 and its audited recovery record."
        for package in receipt.get("identity",{}).get("packages",{}).values():
            package["path"] = Path(package["path"]).name
    for diagnostic in promoted["diagnostic_jobs"].values():
        diagnostic.pop("log_file",None)
        for output in diagnostic["outputs"]:
            old = output["path"]
            output["path"] = locations[old]
            output["sha256"] = sha(results/output["path"])
    for key, diagnostic in promoted["diagnostics"].items():
        src = Path(diagnostic["source_file"])
        if str(src) not in locations:
            dest = results/"raw/diagnostics"/(src.name+"-"+sha(src)[:12]+".gz")
            deterministic_gzip(src,dest)
            locations[str(src)] = str(dest.relative_to(results))
        dest = results/locations[str(src)]
        diagnostic.update(source_file=str(dest.relative_to(results)),sha256=sha(dest),uncompressed_sha256=sha(src))
    for supplement in promoted["diagnostic_campaigns"]:
        src = Path(supplement["script_file"])
        dest = results/"raw/diagnostic-sources"/(src.name+"-"+sha(src)[:12]+".gz")
        deterministic_gzip(src,dest)
        supplement.update(script_file=str(dest.relative_to(results)),script_sha256=sha(dest),script_uncompressed_sha256=sha(src))
        supplement.pop("identity_file")
        for package in supplement["identity"]["packages"].values():
            package["path"] = Path(package["path"]).name
        for supporting in supplement.get("supporting_files", []):
            src = Path(supporting["file"])
            dest = results/"raw/diagnostic-support"/(src.name+"-"+sha(src)[:12]+".gz")
            publication = publish_diagnostic_support(src,dest)
            supporting.update(file=str(dest.relative_to(results)),**publication)
    promoted["provenance"].pop("source_dirty_paths",None)
    for postprocessor in promoted["provenance"]["summary_postprocessors"].values():
        src = Path(postprocessor["file"])
        if sha(src) != postprocessor["sha256"]:
            raise RuntimeError("Summary postprocessor snapshot changed after assembly")
        dest = results/"raw/postprocessing-sources"/(src.name+"-"+sha(src)[:12]+".gz")
        deterministic_gzip(src,dest)
        postprocessor.update(file=str(dest.relative_to(results)),sha256=sha(dest),uncompressed_sha256=sha(src))
    if "collection_runner_recovery" in promoted["provenance"]:
        recovery = promoted["provenance"]["collection_runner_recovery"]
        src = Path(recovery["loaded_source_file"])
        dest = results/"raw/collection-sources"/(recovery["loaded_source_sha256"]+".py.gz")
        deterministic_gzip(src,dest)
        recovery.update(loaded_source_file=str(dest.relative_to(results)),loaded_source_sha256=sha(dest),loaded_source_uncompressed_sha256=sha(src))
    promoted["provenance"]["stata_binary"] = Path(promoted["provenance"]["stata_binary"]).name
    promoted["provenance"]["prior_record_reference"] = "Previous published records remain in Git history; original files are retained in the private campaign archive."
    promoted["provenance"]["promotion"] = "Fresh complete campaign."
    if "/Users/" in json.dumps(promoted) or str(ROOT) in json.dumps(promoted):
        raise RuntimeError("Public statistical provenance contains a private workstation path")
    for p in (campaign/"assembled").glob("summary-*.txt"):
        shutil.copy2(p,results/p.name)
    shutil.copy2(campaign/"assembled/reliability-summary.txt",results/"reliability-summary.txt")
    write_json(results/"website-statistics.json",promoted)
    shutil.copy2(MANIFEST,results/"website-simulation-designs.json")
    shutil.copy2(PRODUCERS,results/"website-simulation-producers.json")
    write_json(results/"reliability-metadata.json",dict(date=dt.datetime.now(dt.timezone.utc).date().isoformat(),
        source_commit=promoted["provenance"]["source_commit"],source_tree_sha256=promoted["provenance"]["identity"]["source_tree_sha256"],
        status="pass",jobs=len(promoted["raw_jobs"]),statistics="website-statistics.json",prior_record_reference=promoted["provenance"]["prior_record_reference"],
        engine=promoted["provenance"]["package_version_header"],
        designs={name:{k:g[k] for k in ("n","reps","rows","source_jobs")} for name,g in promoted["groups"].items()},
        raw_evidence="Every per-job raw output and each deduplicated design dataset is retained as a content-verified .csv.gz file.",
        runtimes=[json.loads(x) for x in sorted({json.dumps(r["identity"]["runtime"],sort_keys=True) for r in promoted["raw_jobs"]})],
        packages=promoted["raw_jobs"][0]["identity"]["packages"]))
    return promoted


def promote_statistics(campaign, document):
    if document["status"] != "pass" or document["provenance"]["identity"]["smoke"]:
        raise RuntimeError("Promotion requires a complete successful non-smoke campaign")
    results = ROOT/"tools/bench/field/results"
    def inventory(directory):
        return {str(p.relative_to(directory)):sha(p) for p in sorted(directory.rglob("*")) if p.is_file()}
    before = inventory(results)
    token = str(time.time_ns())
    stage = results.parent/(".results-staging-"+token)
    archive = campaign/"prior-results"/token
    try:
        shutil.copytree(results,stage)
        write_staged_statistics(campaign,document,stage)
        if inventory(results) != before:
            raise RuntimeError("Current results changed during staging; refusing to overwrite concurrent updates")
        archive.parent.mkdir(exist_ok=True)
        results.rename(archive)
        try:
            stage.rename(results)
        except BaseException:
            archive.rename(results)
            raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    print(f"promoted statistical results; original record preserved privately at {archive}",flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--processors", type=int, default=0, help="Stata/MP processors per job; 0 retains the interpreter default and forms a separate campaign identity")
    parser.add_argument("--only", help="comma-separated design IDs; use --resume later to add jobs")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--smoke", action="store_true", help="80-unit, one-draw wiring run; never results of record")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--promote", action="store_true", help="archive prior records and install a complete campaign's portable compressed evidence")
    parser.add_argument("--assemble-only", action="store_true", help="verify and summarize existing receipts without launching Stata")
    parser.add_argument("--collect-only", action="store_true", help="write only selected job receipts; permits disjoint collectors before one final assembly")
    parser.add_argument("--diagnostics", type=Path, help="fresh scalar evidence envelope with matching frozen-engine provenance and hashed script/runtime identities")
    parser.add_argument("--stata", default=os.environ.get("STATA_CMD") or os.environ.get("STATA") or "stata-mp")
    parser.add_argument("--timeout", type=float, default=86400, help="seconds per independent job")
    args = parser.parse_args()
    if args.workers < 1 or args.timeout <= 0 or args.processors < 0:
        parser.error("workers and timeout must be positive; processors must be nonnegative")
    if args.collect_only and (args.assemble_only or args.promote or not args.only):
        parser.error("--collect-only requires explicit --only and cannot assemble or promote")
    manifest = json.loads(MANIFEST.read_text())
    jobs = manifest["jobs"]
    if args.list:
        for job in jobs:
            print(job["id"], job["script"], job.get("units", "fixed"), job.get("reps", "fixed"), job["parameter_basis"])
        return 0
    chosen = set(args.only.split(",")) if args.only else None
    if chosen and chosen - {j["id"] for j in jobs}:
        parser.error("unknown IDs: " + ",".join(sorted(chosen - {j["id"] for j in jobs})))
    if args.smoke and not chosen:
        chosen = {"core", "cov", "dr", "ps2"}
    selected = [j for j in jobs if chosen is None or j["id"] in chosen]
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    campaign = (args.output or ROOT / "build/website-simulations" / (("smoke-" if args.smoke else "") + stamp)).resolve()
    if not (ROOT / "build").resolve() in campaign.parents:
        parser.error("campaign outputs must be below this repository's build/ directory")
    record = prepare_campaign(campaign, manifest, args)
    print(f"campaign {campaign}; {len(selected)} jobs; {args.workers} fixed-seed workers; no wall-clock benchmarks", flush=True)
    try:
        if args.assemble_only:
            results = []
        else:
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
                results = list(pool.map(lambda job: run_job(campaign, job, args), selected))
    except KeyboardInterrupt:
        with LOCK:
            for proc in list(PROCESSES):
                proc.kill()
        raise
    if args.collect_only:
        for receipt in results:
            verify_receipt(campaign, receipt, job_parameters(next(j for j in selected if j["id"] == receipt["id"]), args.smoke, args.processors))
        verify_campaign_snapshot(campaign, record)
        status = "pass" if all(r["status"] == "pass" for r in results) else "failed"
        destination = campaign / "collection-receipts" / (str(time.time_ns()) + ".json")
        destination.parent.mkdir(exist_ok=True)
        write_json(destination, dict(status=status, selected_jobs=[j["id"] for j in selected], jobs=results, runner_sha256=LOADED_RUNNER_SHA256))
        print(f"collection {status}: {len(results)} jobs; no shared assembly written", flush=True)
        return 0 if status == "pass" else 1
    existing = []
    for job in jobs:
        p = campaign / "jobs" / job["id"] / "receipt.json"
        if p.exists():
            receipt = read_prescribed_receipt(campaign,job,args.smoke,args.processors)
            existing.append(receipt)
    verify_campaign_snapshot(campaign, record)
    complete = len(existing) == len(jobs) and all(x["status"] == "pass" for x in existing)
    status = "failed" if any(x["status"] == "failed" for x in existing) else "smoke_complete" if args.smoke and all(x["status"] == "pass" for x in existing) else "pass" if complete else "partial"
    write_json(campaign / "run-summary.json", {"status": status, "jobs": existing, "completed_jobs": sum(x["status"] == "pass" for x in existing), "prescribed_jobs": len(jobs), "smoke": args.smoke})
    document = assemble_statistics(campaign, existing, manifest, status, args.diagnostics,record.get("assembly_current_source_differences"))
    if args.promote:
        promote_statistics(campaign, document)
    print(f"{status}: {sum(x['status']=='pass' for x in existing)}/{len(jobs)} jobs complete; {campaign}", flush=True)
    return 1 if status == "failed" else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
