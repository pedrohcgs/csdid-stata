#!/usr/bin/env python3

import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "optin-performance"
DOFILE = BUILD / "run-optin-performance.do"
LOG = ROOT / "run-optin-performance.log"


STATA_DO = r'''
clear all
set more off
set seed 20260628

local root "__ROOT__"
adopath ++ "`root'/build"

capture mkdir "`root'/build"
capture mkdir "`root'/build/optin-performance"

tempname benchpost
postfile `benchpost' str32 benchmark double rows double reps double seconds ///
    double max_seconds double memory_mb double max_memory_mb byte passed_time ///
    byte passed_memory str8 stata_version str8 stata_flavor str16 os ///
    str32 machine_type str32 memory_measure ///
    using "`root'/build/optin-performance/results.dta", replace

local stata_version = string(c(stata_version))
local stata_flavor "`c(edition_real)'"
local os "`c(os)'"
local machine_type "`c(machine_type)'"

set obs 500000
generate long id = floor((_n - 1) / 5) + 1
generate byte time = mod(_n - 1, 5) + 1
generate double x1 = sin(id / 37) + time / 10
generate double x2 = cos(id / 53) + mod(id, 17) / 25
generate double wt = 1 + mod(id, 11) / 20 + time / 100
generate int cl = mod(id - 1, 250) + 1
generate byte g = 0
replace g = 3 if mod(id, 5) == 1
replace g = 4 if mod(id, 5) == 2
replace g = 5 if mod(id, 5) == 3
generate double y = .4 * x1 - .2 * x2 + .08 * time + .015 * id / 1000 + ///
    (time >= g & g > 0) * (.45 + .05 * (time - g)) + sin(id / 19)

timer clear 1
timer on 1
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) method(dr)
timer off 1
quietly timer list 1
scalar bench_seconds = r(t1)
scalar bench_memory_mb = c(memory)
if bench_memory_mb > 10000 scalar bench_memory_mb = bench_memory_mb / (1024 * 1024)
assert _N == 500000
assert e(fast_auto) == 1
assert e(fast_used) == 1
assert e(large_store) == 0
assert "`e(performance_resolved)'" == "lean"
assert bench_seconds <= 900
assert bench_memory_mb <= 6000
post `benchpost' ("large_panel") (_N) (.) (bench_seconds) ///
    (900) (bench_memory_mb) (6000) (bench_seconds <= 900) (bench_memory_mb <= 6000) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

clear
set obs 25000
generate long id = floor((_n - 1) / 5) + 1
generate byte time = mod(_n - 1, 5) + 1
generate byte g = 0
replace g = 3 if mod(id, 5) == 1
replace g = 4 if mod(id, 5) == 2
replace g = 5 if mod(id, 5) == 3
generate double y = .12 * time + .01 * id / 100 + ///
    (time >= g & g > 0) * (.5 + .04 * (time - g)) + cos(id / 23)

timer clear 1
timer on 1
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    wboot(reps(999) rseed(20260628)) pointwise
timer off 1
quietly timer list 1
scalar bench_seconds = r(t1)
scalar bench_memory_mb = c(memory)
if bench_memory_mb > 10000 scalar bench_memory_mb = bench_memory_mb / (1024 * 1024)
assert _N == 25000
assert e(fast_auto) == 1
assert e(fast_used) == 1
assert e(bstrap) == 1
assert e(biters) == 999
assert e(large_store) == 0
confirm matrix e(boot_attgt)
confirm matrix e(boot_draws)
assert bench_seconds <= 180
assert bench_memory_mb <= 2000
post `benchpost' ("bootstrap_medium") (_N) (999) (bench_seconds) ///
    (180) (bench_memory_mb) (2000) (bench_seconds <= 180) (bench_memory_mb <= 2000) ///
    ("`stata_version'") ("`stata_flavor'") ("`os'") ("`machine_type'") ("stata_c_memory_setting")

postclose `benchpost'
use "`root'/build/optin-performance/results.dta", clear
export delimited using "`root'/build/optin-performance/results.csv", replace
assert memory_measure == "stata_c_memory_setting"
assert passed_time == 1
assert passed_memory == 1
'''


def scan_stata_log() -> int:
    if not LOG.exists():
        print(f"missing Stata log: {LOG}")
        return 1
    bad = []
    for i, line in enumerate(LOG.read_text(errors="replace").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("r(") and stripped.endswith(";"):
            bad.append(f"{LOG}:{i}:{stripped}")
    if bad:
        print("Uncaught Stata error:\n" + "\n".join(bad[-20:]))
        return 1
    return 0


def main() -> int:
    if os.environ.get("CSDID_RUN_OPTIN_PERF") != "1":
        print(
            "opt-in performance gate skipped; set CSDID_RUN_OPTIN_PERF=1 "
            "to run large_panel and bootstrap_medium"
        )
        return 0

    BUILD.mkdir(parents=True, exist_ok=True)
    plugin = subprocess.run(
        ["bash", "tools/plugin/build-bootstrap-plugin.sh", "auto"], cwd=ROOT
    )
    if plugin.returncode != 0:
        return plugin.returncode
    build = subprocess.run(["stata-mp", "-b", "do", "src/build.do"], cwd=ROOT)
    if build.returncode != 0:
        return build.returncode
    DOFILE.write_text(STATA_DO.replace("__ROOT__", str(ROOT)))
    proc = subprocess.run(["stata-mp", "-b", "do", str(DOFILE)], cwd=ROOT)
    if proc.returncode != 0:
        return proc.returncode
    return scan_stata_log()


if __name__ == "__main__":
    raise SystemExit(main())
