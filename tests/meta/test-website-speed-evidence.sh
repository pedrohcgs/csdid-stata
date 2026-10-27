#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import copy
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = Path.cwd()
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, root / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
sys.path.insert(0, str(root / 'tools/bench'))
tables = module('speed_table_evidence', 'tools/bench/make-field-speed-tables.py')
checker = module('speed_publication_evidence', 'tools/release/check-website-speed-tables.py')
instrument = module('speed_original_instrument', 'tools/bench/run-legacy-candidate-ab.py')
source = root / 'tools/bench/field/historical-results/2026-08-21-speed/scalebench-results.csv'
with source.open(newline='') as stream:
    historical = list(csv.DictReader(stream))
def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
def refused(call, label):
    try:
        call()
    except (SystemExit, ValueError):
        return
    raise AssertionError(f'accepted invalid speed evidence: {label}')

with tempfile.TemporaryDirectory(prefix='csdid-speed-evidence-') as temporary:
    work = Path(temporary)
    path = work / 'timings.csv'
    write_csv(path, historical)
    assert tables.validate_complete_results(path) == 172
    cases = {}
    cases['partial campaign'] = historical[:-1]
    cases['duplicate cell'] = historical + [historical[0]]
    for label, field, value in [('wrong trials','trials','1'), ('wrong design','rows','999'),
                                ('nonfinite time','median_seconds','nan'),
                                ('failed candidate','ok','0')]:
        changed = copy.deepcopy(historical)
        changed[0][field] = value
        cases[label] = changed
    changed = copy.deepcopy(historical)
    next(row for row in changed if row['scan']=='F_scheme')['note'] = 'lost scheme'
    cases['missing scheme'] = changed
    for label, rows in cases.items():
        write_csv(path, rows)
        refused(lambda: tables.validate_complete_results(path), label)

    # No estimator runs here. A fake Stata returns the shell launcher's actual
    # batch-log and row interfaces, so a zero exit cannot certify a failed cell.
    fake = work / 'fake-stata'
    fake.write_text('''#!/usr/bin/env bash
set -eu
shift 3
impl=$1 scan=$2 n=$3 t=$4 g=$5 scheme=$6 trials=$7 csv=$8
log="${csv%.csv}.log"
if [ "${FAKE_MODE}" = nonzero ]; then exit 1; fi
if [ ! -f "$csv" ]; then printf '%s\\n' 'scan,n_units,T,cohorts,rows,pkg,median_seconds,trials,ok,note' > "$csv"; fi
rows=$((n*t))
[ "$scheme" != unbalanced ] || rows=85219
printf '%s,%s,%s,%s,%s,%s,1,%s,1,scheme=%s\\n' "$scan" "$n" "$t" "$g" "$rows" "$impl" "$trials" "$scheme" >> "$csv"
case "$FAKE_MODE" in
  stale_log) : ;;
  wrong_log) printf 'F ROW %s %s n=%s T=%s G=%s fake\\nend of do-file\\n' "$scan" "$impl" "$n" "$t" "$g" > scalebench_f_cell.log ;;
  truncated) printf 'F ROW %s %s n=%s T=%s G=%s fake\\n' "$scan" "$impl" "$n" "$t" "$g" > "$log" ;;
  missing_marker) printf 'end of do-file\\n' > "$log" ;;
  failure) printf 'r(459);\\nend of do-file\\n' > "$log" ;;
  *) printf 'F ROW %s %s n=%s T=%s G=%s fake\\nend of do-file\\n' "$scan" "$impl" "$n" "$t" "$g" > "$log" ;;
esac
''')
    fake.chmod(0o755)
    launcher = work / 'ladder.sh'
    text = (root / 'tools/bench/field/scalebench_f.sh').read_text()
    text = text.replace('STATA=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp', f'STATA="{fake}"')
    launcher.write_text(text)
    for mode in ('truncated', 'missing_marker', 'failure', 'nonzero', 'stale_log', 'wrong_log', 'complete'):
        cell = work / mode
        cell.mkdir()
        (cell/'scalebench-results.log').write_text('F ROW F_n csdid_200 n=1000 T=10 G=4 stale\nend of do-file\n')
        result = subprocess.run(['bash', str(launcher)], cwd=cell,
                                env=dict(os.environ, FAKE_MODE=mode), capture_output=True, text=True)
        assert (result.returncode == 0) == (mode == 'complete'), (mode, result.stdout, result.stderr)
        if mode == 'complete':
            assert len(list(cell.glob('scalebench-f-*.log'))) == 30

    # Invocation success is narrower than returning a requested horizon.
    complete_note = 'H=5; autosample dropped: tau0 tau1 tau2 tau3 tau4 tau5'
    assert tables.all_requested_horizons_dropped(complete_note)
    for note in ('H=5; autosample dropped: tau0 tau1 tau2 tau3 tau4',
                 'H=1; autosample dropped: tau0 tau10',
                 'autosample dropped: tau0 tau1', 'H=1; nothing dropped'):
        assert not tables.all_requested_horizons_dropped(note), note
    key = ('B_rcs',1000,10,4,10000,'')
    tiny_cells = {key:{'csdid':(.1,10000,''),'did_imputation':(.2,10000,complete_note)}}
    tiny_meta = {key:{'rows':10000}}
    rendered = tables.build_table(tiny_cells,tiny_meta,'B_rcs','RCS','n','')
    assert '0.20†' in rendered and 'no requested effects or inference' in rendered
    assert not tables.ratio_facts(tiny_cells,'B_rcs')
    tiny_cells[key]['did_imputation'] = (.2,10000,'H=5; autosample dropped: tau0')
    assert '†' not in tables.build_table(tiny_cells,tiny_meta,'B_rcs','RCS','n','')
    assert len(tables.ratio_facts(tiny_cells,'B_rcs')) == 1

    # Preserve the actual two collection phases across the log-discovery repair.
    phase_csv = work/'phase-results.csv'
    phase_csv.write_bytes((root/'tools/bench/field/results/scalebench-results.csv').read_bytes())
    phase_meta = json.loads((root/'tools/bench/field/results/metadata.json').read_text())
    checker.verify_collection_phases(phase_meta,phase_csv)
    phase_cases = []
    changed = copy.deepcopy(phase_meta); changed.pop('collection_phases'); phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed.pop('collection_phases'); changed['candidate_commit'] = '1'*40; phase_cases.append(changed)
    changed = copy.deepcopy(changed); changed.pop('log_discovery_only_repair'); changed.pop('collection_mode'); phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed['collection_phases'][0]['observations'] = 141; phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed['collection_phases'][0]['source_commit'] = changed['candidate_commit']; phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed['collection_phases'][1]['measurement_sha256'] = {}; phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed['collection_phases'][0]['measurement_sha256']['src/ado/csdid.ado'] = '0'*64; phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed['log_discovery_only_repair']['before_source'] += '\nchanged timed call\n'; phase_cases.append(changed)
    changed = copy.deepcopy(phase_meta); changed['log_discovery_only_repair']['unified_diff'] = ''; phase_cases.append(changed)
    for index,changed in enumerate(phase_cases):
        refused(lambda: checker.verify_collection_phases(changed,phase_csv),'collection phase '+str(index))
    original = phase_csv.read_bytes()
    phase_csv.write_bytes(original.replace(b',10000,',b',10001,',1))
    refused(lambda: checker.verify_collection_phases(phase_meta,phase_csv),'altered phase raw observation')
    phase_csv.write_bytes(original)

    # Synthetic seven-trial pairs exercise the publication math, including the
    # paired median rather than a ratio of separately rounded table timings.
    # Its source/artifact identities are isolated placeholders; the meta-test
    # must also run in a clean checkout without an ignored build directory.
    fixture_root = work/'fixture-root'
    for relative in ('src/ado/csdid.ado', 'tools/bench/run-legacy-candidate-ab.py',
                     'tools/bench/legacy-candidate-ab-workload.do'):
        destination = fixture_root/relative
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/relative,destination)
    # The synthetic records below describe 2.0.1 independently of the release
    # whose source tree runs this test.
    (fixture_root/'src/ado/csdid.ado').write_text('*! csdid 2.0.1 synthetic fixture\n')
    for name in ('csdid.ado','csdid.mata','csdid_stats.ado','lcsdid_v2.mlib'):
        destination=fixture_root/'build'/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes((fixture_root/'src/ado/csdid.ado').read_bytes() if name == 'csdid.ado' else b'synthetic artifact\n')
        payload=fixture_root/'pkg'/name
        payload.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(destination,payload)
    checker.ROOT = fixture_root
    instrument.ROOT = fixture_root
    library = fixture_root/'pkg/lcsdid_v2.mlib'
    packages=[]
    for name in 'jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn flexdid hdidregress xthdidregress drdid reghdfe ftools lmoremata'.split():
        dependency=work/(name+('.mlib' if name == 'lmoremata' else '.ado'))
        dependency.write_text('*! synthetic version\n')
        packages.append('package|'+name+'|'+str(dependency))
    records=['19.5|MP|Unix|test machine|test build|4','engine_stamp|2.0.1|17',
             'engine_library|'+str(library),*packages]
    launcher_text=(root/'tools/bench/run-website-speed-benchmarks.sh').read_text()
    preflight=next(block for block in re.findall(r"<<'PY'\n(.*?)\nPY",launcher_text,re.S)
                   if 'identity = pathlib.Path(sys.argv[1])' in block)
    identity=work/'identity.txt'
    output=work/'runtime.json'
    def runtime_check(lines):
        identity.write_text('\n'.join(lines)+'\n')
        return subprocess.run([sys.executable,'-c',preflight,str(identity),str(output),str(fixture_root)],
                              capture_output=True,text=True)
    good=runtime_check(records)
    assert good.returncode==0,good.stderr
    assert json.loads(output.read_text())['processors']==4
    absent=[line if not line.startswith('package|lmoremata|') else 'package|lmoremata|MISSING' for line in records]
    assert runtime_check(absent).returncode==0
    assert json.loads(output.read_text())['packages']['lmoremata']=={'status':'not installed'}
    wrong_family=work/'another-library.mlib'
    wrong_family.write_text('synthetic wrong library\n')
    for label,changed in [('source fallback',[line.replace('2.0.1|17','2.0.1|source') for line in records]),
                          ('wrong version',[line.replace('2.0.1|17','2.0.0|17') for line in records]),
                          ('newer compiler',[line.replace('2.0.1|17','2.0.1|99') for line in records]),
                          ('invalid processors',[line.replace('test build|4','test build|0') for line in records]),
                          ('missing dependency',records[:-1]),
                          ('missing mandatory ado',[line if not line.startswith('package|jwdid|') else 'package|jwdid|MISSING' for line in records]),
                          ('unknown package identity',[line.replace('package|jwdid|','package|unlisted|') for line in records]),
                          ('malformed optional absence',[line if not line.startswith('package|lmoremata|') else 'package|lmoremata|missing' for line in records]),
                          ('wrong optional library family',[line if not line.startswith('package|lmoremata|') else 'package|lmoremata|'+str(wrong_family) for line in records])]:
        assert runtime_check(changed).returncode!=0,label
    evidence = work / 'fixed'
    evidence.mkdir()
    runs = []
    for scenario, config in instrument.SCENARIOS.items():
        for implementation in ('candidate', 'legacy'):
            for trial in range(1,8):
                runs.append(dict(implementation=implementation, scenario=scenario,
                    seconds=str((1 if implementation=='candidate' else 20)+trial*.001),
                    observations='50000', inner=str(config['inner']), accelerator='not-applicable',
                    stata_version='17', stata_flavor='MP', stata_processors='4', os='Unix', machine_type='test',
                    trial=str(trial), peak_rss_mb='100' if implementation=='candidate' else '200',
                    rss_samples='2', comparison='like-for-like'))
    summaries = [instrument.summarize(name, config, [r for r in runs if r['scenario']==name])
                 for name, config in instrument.SCENARIOS.items()]
    write_csv(evidence/'runs.csv', runs)
    write_csv(evidence/'summary.csv', summaries)
    metadata = dict(generated_date='2026-10-23',candidate_version='2.0.1',trials=7,
        legacy_commit=instrument.LEGACY_COMMIT, measurement_sha256=instrument.candidate_fingerprints(),
        runtime=dict(version='17',edition='MP',processors='4',os='Unix',machine_type='test'),
        runs_sha256=hashlib.sha256((evidence/'runs.csv').read_bytes()).hexdigest(),
        summary_sha256=hashlib.sha256((evidence/'summary.csv').read_bytes()).hexdigest())
    def save(meta):
        (evidence/'metadata.json').write_text(json.dumps(meta))
    save(metadata)
    labels = dict(candidate_version='2.0.1', date='2026-10-23', stata='Stata/MP 17', platform='test machine',processors=4)
    for article in (checker.FIELD, checker.LADDER):
        original = article.read_text()
        labeled = checker.article_record_labels(original, article, labels)
        assert '23 October 2026 with Stata/MP 17\non test machine' in labeled
        assert checker.article_record_labels(labeled, article, labels) == labeled
        if article == checker.LADDER:
            assert 'trials for 2.0.1' in labeled and 'before 2.0.0 (November 2025)' in labeled
    readme = work/'README.md'
    readme_source = root / ('packaging/README.md' if (root/'packaging').is_dir() else 'README.md')
    readme.write_text(readme_source.read_text())
    public = work/'public-layout'
    (public/'tools/release').mkdir(parents=True)
    for filename in ('check-website-speed-tables.py','check-website-speed-prose.py'):
        shutil.copyfile(root/'tools/release'/filename,public/'tools/release'/filename)
    shutil.copyfile(readme_source,public/'README.md')
    public_checker=module('public_speed_checker',public/'tools/release/check-website-speed-tables.py')
    assert public_checker.README.resolve() == (public/'README.md').resolve()
    fragments=work/'fragments'
    fragments.mkdir()
    cells,meta=tables.load(source)
    for scan,filename,title,unit in tables.F_SPECS:
        (fragments/filename).write_text(tables.build_gain_table(cells,meta,scan,title,unit))
    public_results=public/'tools/bench/field/results'
    public_results.mkdir(parents=True)
    shutil.copyfile(source,public_results/'scalebench-results.csv')
    for relative in ('src/ado/csdid.ado','pkg/csdid.ado'):
        destination=public/relative
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/'src/ado/csdid.ado',destination)
    for metadata_record in ({'date':'2026-08-21'}, {'date':'2026-08-21','candidate_version':'2.0.0'}):
        (public_results/'metadata.json').write_text(json.dumps(metadata_record))
        stale=subprocess.run([sys.executable,str(public/'tools/release/check-website-speed-tables.py')],
                             capture_output=True,text=True)
        assert stale.returncode != 0 and 'current timing evidence does not identify the packaged release' in stale.stderr
    public_prose=module('public_speed_prose',public/'tools/release/check-website-speed-prose.py')
    assert public_prose.allowed_numbers(fragments)
    rendered = checker.fixed_size_readme(evidence, readme)
    assert '| Workload | Version 1.82 | 2.0.1 | |' in rendered
    assert '23 October 2026' in rendered and 'on Stata/MP 17 using 4 processors.' in rendered
    assert '100MB\nagainst 200MB' in rendered and 'in 0 of these 15 workloads' in rendered
    readme.write_text(rendered)
    assert checker.fixed_size_readme(evidence, readme) == rendered
    # The public source distribution has root README.md and no ignored build
    # directory. Its payload bytes carry the same measured artifact identity.
    shutil.rmtree(fixture_root/'build')
    assert checker.fixed_size_readme(evidence, readme) == rendered
    for key, value in [('trials',3), ('candidate_version','2.0.0'), ('runs_sha256','0'*64),
                       ('measurement_sha256',{}), ('runtime',dict(version='19.5',edition='MP',os='Unix',machine_type='test'))]:
        changed=copy.deepcopy(metadata)
        changed[key]=value
        save(changed)
        refused(lambda: checker.fixed_size_record(evidence), key)
    save(metadata)
    tampered=copy.deepcopy(summaries)
    tampered[0]['candidate_median_seconds']='0.000000001'
    write_csv(evidence/'summary.csv',tampered)
    metadata['summary_sha256']=hashlib.sha256((evidence/'summary.csv').read_bytes()).hexdigest()
    save(metadata)
    refused(lambda: checker.fixed_size_record(evidence),'forged summary with updated hash')
print('speed evidence OK: full 172-row grid, seven malformed grids, seven fake batch outcomes, '
      'all-horizon invocation qualifiers and ten collection-phase forgeries, '
      'compiled-library/runtime identity, optional absence and nine forgeries, all 210 paired observations, '
      'idempotent README renderer and six evidence forgeries')
PY
