#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
from fractions import Fraction as F
import importlib.util
from pathlib import Path
import sys

root = Path(sys.argv[1])
def module(name,path):
    spec = importlib.util.spec_from_file_location(name,path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
runner = module('runner',root/'tools/bench/run-website-simulations.py')
summary = module('summary',root/'tools/bench/field/mcsum.py')
# Independent cohort means from the published DGP, retaining decimal inputs
# as exact fractions until the final conversion to the exported double.
base = F(2)+(F('.3')*F('.45')+F('.8')*F('.55')+F('1.5')*F('.65'))/3
slope = F('.5')+(F('.2')*F('-.4')+F('.6')*0+F('1.2')*F('.4'))/3
assert base==F(151,60) and slope==F(19,30)
for regime in ('master','cohorthet'):
    for h in (0,1,2):
        want = float(base)+float(slope)*h
        assert runner.population_truth(regime,h)==want
        assert summary.es_truth(regime,h)==want
# A confidence endpoint between the former rounded and exact targets is a
# non-vacuous witness: the wrong target flips coverage for this fixed draw.
exact = float(base)
rounded = 2.516667
endpoint = (exact+rounded)/2
se = .1
est = endpoint+1.959964*se
row = dict(regime='master',pkg='csdid_dr',rep='1',h='0',est=str(est),se=str(se))
assert runner.calculate_metrics([row],1)[0]['coverage_hits']==0
assert abs(est-rounded)<=1.959964*se
assert exact!=rounded
# Unaffected scientific targets retain their original definitions.
assert runner.population_truth('balanced',0)==2
assert runner.population_truth('balanced',2)==3
assert runner.population_truth('breakC',0)==2.0945
assert runner.population_truth('balanced',99)==2.5
assert runner.population_truth('balanced',5006)==3.5
print('Exact cohort-mean population targets and coverage-boundary witness pass.')
PY
