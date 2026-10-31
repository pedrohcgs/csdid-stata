#!/usr/bin/env bash
# The classification inventory must accept documented numerical boundaries and
# refuse missing, retired or undefined categories without obscuring summaries.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 tools/spec/check-divergence-kinds.py
python3 - <<'PY'
from pathlib import Path
import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile

root=Path.cwd()
checker=Path(os.environ.get('CSDID_DIVERGENCE_CHECKER',root/'tools/spec/check-divergence-kinds.py'))
record=os.environ.get('CSDID_DIVERGENCE_EVIDENCE_DIR')
evidence=Path(record) if record else None
if evidence is not None:evidence.mkdir(parents=True,exist_ok=False)
kinds=['behavioral-default','numerical-boundary','stata-surface','language-surface',
       'internal-api','test-placement','upstream-conflict','upstream-version','upstream-not-a-test']
cases=[('valid-existing',None),('valid-numerical',None),('valid-all-kinds',None),
       ('unclassified','is not classified'),
       ('retired','is classified but no fixture declares it; retire the row'),
       ('unknown',"has unrecognised kind 'undefined-kind'"),
       ('empty-kind',"has unrecognised kind ''"),('missing-registry','missing registry:')]
checked=1
with tempfile.TemporaryDirectory(prefix='csdid-divergence-kinds-') as temporary:
    work=Path(temporary)
    for label,wanted in cases:
        tree=work/label
        (tree/'tools/spec').mkdir(parents=True)
        (tree/'inst/spec').mkdir(parents=True)
        contract=tree/'tests/fixtures/parity/probe/expected/contract'
        contract.mkdir(parents=True)
        (tree/'tools/spec/check-divergence-kinds.py').write_bytes(checker.read_bytes())
        selected=['behavioral-default','stata-surface'] if label=='valid-existing' else ['behavioral-default','numerical-boundary']
        if label=='valid-all-kinds':selected=kinds
        declared=[f'PROBE-DIV{i:03d}' for i in range(1,len(selected)+1)]
        registry=[dict(divergence_id=did,divergence_kind=kind,summary='Isolated declared behavior') for did,kind in zip(declared,selected)]
        if label=='unclassified':registry.pop()
        elif label=='retired':registry.append(dict(divergence_id='RETIRED-DIV001',divergence_kind='stata-surface',summary='Retired declaration'))
        elif label=='unknown':registry[-1]['divergence_kind']='undefined-kind'
        elif label=='empty-kind':registry[-1]['divergence_kind']=''
        with (contract/'approved-divergence.csv').open('w',newline='') as f:
            writer=csv.writer(f,lineterminator='\n');writer.writerow(['divergence_id','status'])
            writer.writerows((did,'approved-divergence') for did in declared)
        registry_path=tree/'inst/spec/divergence-kinds.csv'
        with registry_path.open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['divergence_id','divergence_kind','summary'],lineterminator='\n')
            writer.writeheader();writer.writerows(registry)
        if label=='missing-registry':registry_path.unlink()
        result=subprocess.run([sys.executable,str(tree/'tools/spec/check-divergence-kinds.py')],capture_output=True,text=True)
        body=result.stdout+result.stderr
        if evidence is not None:
            shutil.copytree(tree,evidence/label)
            (evidence/(label+'.log')).write_text(body)
            (evidence/(label+'.json')).write_text(json.dumps({'case':label,'actual_exit':result.returncode,'expected_refusal':wanted},indent=2)+'\n')
        if wanted is None:
            assert result.returncode==0 and 'divergence kinds OK' in body,(label,'valid divergence classification rejected',body)
            if label!='valid-existing':
                assert 'Omitted-option default differences: 1; documented numerical-boundary exceptions: 1.' in result.stdout,(label,'numerical/default summary misclassified',body)
                assert 'the rest are surface' not in result.stdout,(label,'numerical exception hidden by surface-only summary',body)
        else:
            assert result.returncode!=0 and wanted in body,(label,'invalid classification accepted or wrong refusal',body)
        checked+=1
print(f'Divergence kinds: {checked} live-registry/isolated acceptance/refusal cases pass; no R or Stata launched.')
PY
