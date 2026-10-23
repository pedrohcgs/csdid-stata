#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy
import csv
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('runner',root/'tools/bench/run-website-simulations.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
manifest = json.loads(r.MANIFEST.read_text())
policy = json.loads(r.PRODUCERS.read_text())
roster, owners = r.producer_roster(manifest,policy)
assert len(policy['overlaps']) == 15
assert owners[('sampling_main','balanced','bjs')] == 'core'
assert owners[('covariates_panel','bal_ps2','lpdid')] == 'ps2'
assert owners[('covariates_panel','bal_ok','jwdid')] == 'dr'

def refuses(call, text):
    try:
        call()
    except RuntimeError as exc:
        assert text in str(exc), str(exc)
    else:
        raise AssertionError('required refusal did not occur: '+text)

with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    def receipt(job, rows):
        config = copy.deepcopy(next(j for j in manifest['jobs'] if j['id']==job))
        config['reps'] = 1
        path = base/(job+'.csv')
        with path.open('w',newline='') as f:
            writer = csv.DictWriter(f,fieldnames=['regime','pkg','rep','h','est','se'])
            writer.writeheader()
            writer.writerows(dict(regime='balanced',pkg=pkg,rep=rep,h=0,est=est,se=se) for pkg,rep,est,se in rows)
        return dict(id=job,status='pass',config=config,outputs=[dict(path=str(path))])
    core = receipt('core',[('bjs',1,'2','.2')])
    option = receipt('bjs',[('bjs',1,'3','.3'),('bjs_wtr',1,'4','.4')])
    groups,_,_,comparisons = r.canonical_rows([option,core],manifest,policy)
    assert groups['sampling_main'][('balanced','bjs',1,0)]['est']=='2'
    assert groups['sampling_main'][('balanced','bjs_wtr',1,0)]['est']=='4'
    assert comparisons[0]['est_max_abs_difference']==1
    assert comparisons[0]['identical_numeric_rows']==0
    # An option fit never backfills an unavailable canonical baseline.
    groups,_,_,_ = r.canonical_rows([option],manifest,policy)
    assert ('balanced','bjs',1,0) not in groups['sampling_main']
    assert ('balanced','bjs_wtr',1,0) in groups['sampling_main']
    missing = receipt('core',[('bjs',1,'.','.')])
    refuses(lambda:r.canonical_rows([option,missing],manifest,policy),'missingness requires adjudication')
    both_missing = receipt('bjs',[('bjs',1,'.','.')])
    groups,_,_,_ = r.canonical_rows([both_missing,missing],manifest,policy)
    assert groups['sampling_main'][('balanced','bjs',1,0)]['est']=='.'
    duplicate = receipt('core',[('bjs',1,'2','.2'),('bjs',1,'2','.2')])
    refuses(lambda:r.canonical_rows([duplicate],manifest,policy),'Within-producer duplicate')
    unknown = receipt('bjs',[('unknown',1,'2','.2')])
    refuses(lambda:r.canonical_rows([unknown],manifest,policy),'Unregistered source producer')
    incomplete = copy.deepcopy(policy)
    incomplete['overlaps'].pop()
    refuses(lambda:r.producer_roster(manifest,incomplete),'register every')
    wrong = copy.deepcopy(policy)
    wrong['overlaps'][0]['registered_producers'].append('bjs')
    refuses(lambda:r.producer_roster(manifest,wrong),'Invalid registered')
    core = receipt('core',[('bjs',1,'2','.2')])
    extra = receipt('bjs',[('bjs',2,'2','.2')])
    refuses(lambda:r.canonical_rows([core,extra],manifest,policy),'unmatched baseline keys')
print('Website producer ownership and adversarial refusal checks pass.')
PY
