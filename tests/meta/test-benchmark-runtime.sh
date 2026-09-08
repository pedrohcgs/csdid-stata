#!/usr/bin/env bash
# Mandatory benchmark gates must observe the requested process and fresh evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

source = Path.cwd()
checks = 0

# c(flavor) reports IC even in an MP process; match the platform-row contract.
workload = (source / 'tools/bench/legacy-candidate-ab-workload.do').read_text()
result_block = workload.split('file open result', 1)[1].split('file close result', 1)[0]
if "`c(edition_real)'" not in result_block or "`c(flavor)'" in result_block:
    raise SystemExit('legacy benchmark must record the actual Stata edition')
checks += 1

def load(path):
    spec = importlib.util.spec_from_file_location(path.stem.replace('-', '_'), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

with tempfile.TemporaryDirectory(prefix='csdid-benchmark-check-') as directory:
    root = Path(directory).resolve()
    for name in ('tools/bench', 'tools/release', 'tools/plugin', 'tests/stata',
                 'tests/fixtures/parity/f049/expected/contract', 'build', 'reports', 'bin', 'pkg'):
        (root / name).mkdir(parents=True)
    runners = ('run-optin-performance.py', 'run-f049-ratio.py', 'run-memory-gate.py', 'run-legacy-candidate-ab.py')
    for name in (*runners, 'run-session-warmup.py', 'stata_runtime.py'):
        shutil.copy2(source / 'tools/bench' / name, root / 'tools/bench' / name)
    shutil.copy2(source / 'tools/bench/f049-r-reference.R', root / 'tools/bench')
    shutil.copy2(source / 'tests/stata/test-f049.do', root / 'tests/stata')
    shutil.copy2(source / 'tools/release/check-stata-log-tail.sh', root / 'tools/release')
    budget_path = 'tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv'
    shutil.copy2(source / budget_path, root / budget_path)
    (root / 'pkg/manifest-sentinel').write_text('macOS payload only\n')
    (root / 'tools/plugin/build-bootstrap-plugin.sh').write_text('''#!/usr/bin/env bash
set -eu
printf 'native:%s\n' "${CSDID_PLUGIN_OUTDIR:-unset}" >> calls.txt
[ "${CSDID_PLUGIN_OUTDIR:-}" = "$PWD/build" ] || exit 81
printf 'native-test-binary\n' > "$CSDID_PLUGIN_OUTDIR/csdid_bootstrap_unix.plugin"
''')
    (root / 'tools/release/build-package.sh').write_text('''#!/usr/bin/env bash
set -eu
printf 'build:%s\n' "${CSDID_BUILD_STATA_CMD:-${STATA_CMD:-stata-mp}}" >> calls.txt
[ "${CSDID_BUILD_STATA_CMD:-}" = "$PWD/bin/build-stata" ] || exit 82
''')
    consumer = root / 'bin/consumer-stata'
    consumer.write_text('''#!/usr/bin/env python3
import csv, json, os, shlex, sys, time
from pathlib import Path
root = Path.cwd()
mode = os.environ.get('CSDID_TEST_MODE', 'complete')
with Path('calls.txt').open('a') as stream: stream.write('consumer:' + json.dumps(sys.argv) + '\\n')
assert len(sys.argv) == 4, 'benchmark arguments must live inside the driver'
dofile = Path(sys.argv[3])
log = root / (dofile.name.split('.', 1)[0] + '.log')
if mode != 'missing-log':
    log.write_text('' if mode == 'empty-log' else 'end of do-file\\n. do unfinished.do\\n' if mode == 'truncated-log' else
                   'r(9);\\nend of do-file\\n' if mode == 'error-log' else 'end of do-file\\n')
if mode == 'process-failure': sys.exit(42)
def output(path, rows):
    if mode == 'missing-result': return
    if mode == 'empty-result': rows = []
    if mode == 'duplicate-result': rows = rows + rows[:1]
    fields = list(rows[0]) if rows else ['benchmark']
    if rows and mode == 'nan-result': rows[0]['seconds'] = 'nan'
    if rows and mode == 'zero-result': rows[0]['seconds'] = '0'
    if rows and mode == 'wrong-identity': rows[0][next(iter(rows[0]))] = 'wrong'
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader(); writer.writerows(rows)
if dofile.name == 'run-optin-performance.do':
    rows = [dict(benchmark=name, rows=n, reps=reps, seconds=1, max_seconds=limit,
                 memory_mb=0, max_memory_mb=memory, passed_time=1, passed_memory=1,
                 memory_measure='stata_c_memory_setting')
            for name,n,reps,limit,memory in [('large_panel',500000,'.',900,6000),('bootstrap_medium',25000,999,180,2000)]]
    if mode == 'over-budget': rows[0]['seconds'] = 901
    if mode == 'wrong-count': rows[0]['rows'] = 499999
    if mode == 'false-pass': rows[0]['passed_time'] = 0
    if mode == 'invalid-memory': rows[0]['memory_mb'] = 'inf'
    output(root / 'build/optin-performance/results.csv', rows)
elif dofile.name.startswith('session-warmup-'):
    runtime, output_path, phase, rif = shlex.split(dofile.read_text())[2:]
    assert Path(runtime) == root / 'build'
    assert Path(output_path) == root / 'build/session-warmup.csv'
    assert phase in ('rifbuild', 'cold', 'agg', 'rif')
    if phase == 'rifbuild':
        Path(rif).write_text('fixture RIF artifact')
    elif mode != 'missing-result':
        rows = [[phase, label, '1'] for label in ('first', 'steady', 'steady')]
        if mode == 'duplicate-result': rows.append(rows[-1])
        if mode == 'nan-result': rows[0][-1] = 'nan'
        if mode == 'zero-result': rows[0][-1] = '0'
        with Path(output_path).open('a', newline='') as stream: csv.writer(stream).writerows(rows)
elif dofile.name == 'test-f049.do':
    with (root / 'tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv').open() as stream:
        rows = [dict(benchmark=row['benchmark'], seconds=1) for row in csv.DictReader(stream)]
    if mode == 'over-budget': rows[0]['seconds'] = 100
    output(root / 'build/f049/results.csv', rows)
else:
    args = shlex.split(dofile.read_text())[2:]
    if 'legacy-candidate' in dofile.read_text():
        implementation, scenario, _, _, inner, result, customlog = args
        Path(customlog).write_text('inner diagnostic log\\n')
        rows = [dict(implementation=implementation, scenario=scenario, seconds=1, observations=5000,
                     inner=inner, accelerator='not-applicable', stata_version='19.5', stata_flavor='MP',
                     os='Unix', machine_type='Macintosh (Intel 64-bit)')]
        if mode == 'wrong-inner': rows[0]['inner'] = 999
        output(Path(result), rows)
    time.sleep(0.05)
''')
    consumer.chmod(0o755)
    (root / 'bin/stata-mp').write_text('#!/usr/bin/env bash\nexit 97\n')
    (root / 'bin/stata-mp').chmod(0o755)
    ps = root / 'bin/ps'
    ps.write_text('''#!/usr/bin/env bash
case "${CSDID_TEST_RSS:-positive}" in
 positive) printf '4096\\n' ;;
 zero) printf '0\\n' ;;
 nan) printf 'nan\\n' ;;
 negative) printf '%s\\n' '-1' ;;
 absent) exit 1 ;;
 empty) exit 0 ;;
 malformed) printf 'unknown\\n' ;;
esac
''')
    ps.chmod(0o755)
    rscript = root / 'bin/Rscript'
    rscript.write_text('''#!/usr/bin/env python3
import csv, os, sys
from pathlib import Path
mode = os.environ.get('CSDID_TEST_MODE', 'complete')
if mode == 'r-failure': sys.exit(42)
if 'f049-r-reference' not in sys.argv[1] or mode == 'missing-r': sys.exit(0)
with Path('tests/fixtures/parity/f049/expected/contract/r-relative-budgets.csv').open() as stream:
    rows = [dict(benchmark=row['benchmark'], r_seconds=1) for row in csv.DictReader(stream)]
if mode == 'nan-r': rows[0]['r_seconds'] = 'nan'
if mode == 'zero-r': rows[0]['r_seconds'] = '0'
if mode == 'empty-r': rows = []
if mode == 'duplicate-r': rows.append(rows[0])
with Path('build/f049/r-results.csv').open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=['benchmark','r_seconds']); writer.writeheader(); writer.writerows(rows)
''')
    rscript.chmod(0o755)
    env = dict(os.environ, PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'],
               STATA_CMD=str(consumer), CSDID_BUILD_STATA_CMD=str(root / 'bin/build-stata'),
               CSDID_RUN_OPTIN_PERF='1', CSDID_TEST_RSS='positive')

    def run(name, mode, good=False, rss='positive', build_mode='complete'):
        global checks
        result = subprocess.run([sys.executable, str(root / 'tools/bench' / name)], cwd=root,
                                env=dict(env, CSDID_TEST_MODE=mode, CSDID_TEST_RSS=rss, CSDID_TEST_BUILD_MODE=build_mode),
                                text=True, capture_output=True)
        if (result.returncode == 0) != good:
            raise SystemExit(f'{name}/{mode}/{rss}: rc={result.returncode}\n{result.stdout}{result.stderr}')
        checks += 1
        return result

    for runner, subdir, logname in ((runners[0], 'optin-performance', 'run-optin-performance.log'),
                                   (runners[1], 'f049', 'test-f049.log')):
        modes = ['complete', 'missing-log', 'empty-log', 'truncated-log', 'error-log', 'process-failure',
                 'missing-result', 'empty-result', 'duplicate-result', 'nan-result', 'zero-result',
                 'wrong-identity', 'over-budget']
        modes += ['wrong-count', 'false-pass', 'invalid-memory'] if subdir == 'optin-performance' else [
            'missing-r', 'empty-r', 'duplicate-r', 'nan-r', 'zero-r', 'r-failure']
        for mode in modes:
            # A prior valid result and complete log must not rescue a new failed run.
            run(runner, 'complete', good=True)
            (root / logname).write_text('end of do-file\n')
            if subdir == 'f049':
                (root / 'build/f049/relative-results.csv').write_text('stale paired observations\n')
            result = run(runner, mode, good=(mode == 'complete'))
            if subdir == 'f049' and (root / 'build/f049/relative-results.csv').exists():
                raise SystemExit('stale paired F049 observations survived the new process')
            if mode == 'missing-result' and (root / 'build' / subdir / 'results.csv').exists():
                raise SystemExit('stale benchmark result survived a run producing no output')
            if subdir == 'f049' and mode not in ('complete', 'over-budget') and (root / 'build/f049/r-stata-ratio.csv').exists():
                raise SystemExit('stale F049 ratio certificate survived an incomplete run')
            checks += 1
    run(runners[2], 'complete', good=True)
    for mode in ('missing-log', 'empty-log', 'truncated-log', 'error-log', 'process-failure'):
        run(runners[2], mode)
        if (root / 'build/memory-gate/results.csv').exists():
            raise SystemExit('stale memory certificate survived an incomplete run')
    for rss in ('zero', 'nan', 'negative', 'absent', 'empty', 'malformed'):
        run(runners[2], 'complete', rss=rss)
    with (root / 'calls.txt').open() as stream:
        calls = stream.read().splitlines()
    if not any(line == 'native:' + str(root / 'build') for line in calls):
        raise SystemExit('native plugin was not built into validation scratch')
    if not any(line == 'build:' + str(root / 'bin/build-stata') for line in calls):
        raise SystemExit('build runtime did not remain separate from the consumer')
    for line in calls:
        if line.startswith('consumer:'):
            argv = json.loads(line[len('consumer:'):])
            if argv[0] != str(consumer) or len(argv) != 4:
                raise SystemExit('requested consumer runtime or driver-only CLI was lost')
    if sorted(path.name for path in (root / 'pkg').iterdir()) != ['manifest-sentinel']:
        raise SystemExit('a native test binary entered the shipped payload')
    checks += 4

    sys.path.insert(0, str(root / 'tools/bench'))
    import stata_runtime
    ratio_runner = load(root / 'tools/bench/run-f049-ratio.py')
    budget = ratio_runner.indexed(root / budget_path)
    complete = [dict(round=i, process_order='r,stata' if i % 2 else 'stata,r',
                     benchmark=name, stata_seconds=1., r_seconds=1., stata_over_r=1.,
                     max_stata_over_r=float(limit['max_stata_over_r']))
                for i in range(1, 7) for name, limit in budget.items()]
    def summarize(values):
        return ratio_runner.summarize(values, budget)
    if not all(row['passed'] == '1' for row in summarize(complete)):
        raise SystemExit('six complete finite rounds should pass')
    checks += 1
    # The old single-observation decision rejects this isolated burst; the
    # fixed six-round median retains it without letting it select the verdict.
    isolated = [dict(row) for row in complete]
    isolated[0].update(stata_seconds=100., stata_over_r=100.)
    if isolated[0]['stata_over_r'] <= isolated[0]['max_stata_over_r']:
        raise SystemExit('single-draw negative qualification did not fail')
    if not all(row['passed'] == '1' for row in summarize(isolated)):
        raise SystemExit('one isolated observation incorrectly selects the median verdict')
    sustained = [dict(row, stata_seconds=100., stata_over_r=100.) for row in complete]
    if any(row['passed'] == '1' for row in summarize(sustained)):
        raise SystemExit('a sustained slowdown must fail the unchanged ceilings')
    checks += 3
    cases = [complete[:-1], complete + complete[:1], complete[24:]]
    for key, value in [('round', 7), ('process_order', 'stata,r'),
                       ('stata_seconds', float('nan')), ('r_seconds', 0),
                       ('stata_over_r', 2), ('max_stata_over_r', 100)]:
        rows = [dict(row) for row in complete]
        rows[0][key] = value
        cases.append(rows)
    for rows in cases:
        try:
            summarize(rows)
        except (SystemExit, ValueError):
            checks += 1
        else:
            raise SystemExit('malformed or incomplete six-round evidence passed')
    # A previous raw tree is preserved, but cannot fill the current run.
    run(runners[1], 'complete', good=True)
    original = root / 'build/f049/r-ratio-rounds'
    (original / 'prior-sentinel').write_text('previous evidence')
    run(runners[1], 'missing-result')
    if (original / 'prior-sentinel').exists() or not list(original.parent.glob('r-ratio-rounds.previous-*/prior-sentinel')):
        raise SystemExit('prior rounds were reused or discarded')
    if (original.parent / 'r-stata-ratio.csv').exists():
        raise SystemExit('incomplete rounds retained a success summary')
    if not (original / 'round-01/test-f049.log').is_file():
        raise SystemExit('failed-round raw log was not retained')
    checks += 3
    dotted = root / 'build/name.with.dots.do'
    stata_runtime.write_driver(root, dotted, 'tools/bench/memory-workload.do', ('default_cband', root))
    with patch.dict(os.environ, dict(env, CSDID_TEST_MODE='complete'), clear=True):
        _, _, samples = stata_runtime.measure_stata(root, str(consumer), dotted, root / 'build/dotted-batch.log')
    if samples < 1 or not (root / 'build/dotted-batch.log').is_file():
        raise SystemExit('batch log naming did not follow the first-dot convention')
    checks += 1
    legacy = load(root / 'tools/bench' / runners[3])
    legacy.OUTDIR.mkdir(parents=True)
    for mode in ('complete', 'missing-log', 'empty-log', 'truncated-log', 'error-log', 'process-failure',
                 'missing-result', 'empty-result', 'duplicate-result', 'nan-result', 'zero-result',
                 'wrong-identity', 'wrong-inner'):
        with patch.dict(os.environ, dict(env, CSDID_TEST_MODE=mode), clear=True):
            try:
                row = legacy.run_one(str(consumer), root / 'legacy', 'candidate', 'balanced_reg_analytical', 5, 1)
                good = True
            except (RuntimeError, ValueError, subprocess.CalledProcessError, FileNotFoundError, StopIteration):
                good = False
        if good != (mode == 'complete'):
            raise SystemExit(f'legacy row reader misclassified {mode}')
        if good and (row['rss_measure'] != 'ps_rss_kb' or int(row['rss_samples']) < 1 or float(row['peak_rss_mb']) != 4):
            raise SystemExit('legacy row lost actual RSS evidence')
        checks += 1
    for rss in ('zero', 'nan', 'negative', 'absent', 'empty', 'malformed'):
        with patch.dict(os.environ, dict(env, CSDID_TEST_MODE='complete', CSDID_TEST_RSS=rss), clear=True):
            try:
                legacy.run_one(str(consumer), root / 'legacy', 'candidate', 'balanced_reg_analytical', 5, 1)
            except (RuntimeError, ValueError):
                checks += 1
            else:
                raise SystemExit('legacy gate accepted unavailable or invalid RSS: ' + rss)
    for name in ('csdid.ado', 'csdid.mata', 'csdid_stats.ado'):
        (root / 'build' / name).write_text('fixture artifact\n')
    with patch.dict(os.environ, dict(env, STATA_CMD=str(root / 'bin/stata-mp'), CSDID_TEST_MODE='complete'), clear=True), \
         patch.object(legacy, 'verify_legacy_root', return_value=legacy.LEGACY_COMMIT), \
         patch.object(sys, 'argv', ['run-legacy-candidate-ab.py', '--trials', '3',
                                   '--scenario', 'balanced_reg_analytical', '--stata', str(consumer)]):
        legacy.main()
    with (legacy.OUTDIR / 'runs.csv').open() as stream:
        actual_rows = list(csv.DictReader(stream))
    if len(actual_rows) != 6 or {row['implementation'] for row in actual_rows} != {'candidate', 'legacy'}:
        raise SystemExit('legacy main lost the explicitly selected process or paired inventory')
    checks += 1
    # The report writer must never turn failing or partial rows into a passing certificate.
    summaries = [dict(scenario=name, comparison='like-for-like', trials=3, candidate_median_seconds=1,
                      legacy_median_seconds=2, median_paired_time_ratio=.5, time_ratio_upper95=.6,
                      candidate_median_peak_rss_mb=4, legacy_median_peak_rss_mb=5,
                      median_paired_rss_ratio=.8, rss_ratio_upper95=.9,
                      candidate_faster='1', candidate_lower_rss='1') for name in legacy.SCENARIOS]
    metadata = dict(generated_date='2026-09-07', legacy_commit=legacy.LEGACY_COMMIT, trials=3)
    # The public distribution intentionally omits generated reports.
    shutil.rmtree(root / 'reports')
    for status in ('pass', 'fail', 'partial'):
        rows = [dict(row) for row in summaries]
        if status == 'fail': rows[0]['candidate_faster'] = '0'
        if status == 'partial': rows = rows[:1]
        legacy.write_report(rows, metadata)
        report = (root / 'reports/legacy-candidate-performance-certification.md').read_text()
        if f'Status: `{status}`' not in report or '`1.05`' not in report or '`1.08`' not in report:
            raise SystemExit('legacy report misstates its actual verdict or budgets')
        checks += 1
    metadata['generated_date'] = '2026-07-01'
    metadata_file = legacy.OUTDIR / 'metadata.json'
    metadata_file.write_text(json.dumps(metadata) + '\n')
    old_metadata = metadata_file.read_bytes()
    with patch.object(sys, 'argv', ['run-legacy-candidate-ab.py', '--report-only']):
        legacy.main()
    if metadata_file.read_bytes() != old_metadata or 'Date: 2026-07-01' not in (root / 'reports/legacy-candidate-performance-certification.md').read_text():
        raise SystemExit('formatting an old report changed the date of its evidence')
    checks += 1
    legacy.write_report(summaries, metadata)
    with patch.object(sys, 'argv', ['run-legacy-candidate-ab.py', '--trials', '0']):
        try:
            legacy.main()
        except SystemExit:
            pass
    if (root / 'reports/legacy-candidate-performance-certification.md').exists():
        raise SystemExit('early legacy refusal left a passing report')
    checks += 1

    # The startup gate must compile with the pinned build runtime and launch
    # each unchanged workflow in the explicitly requested consumer. The real
    # build helper verifies fresh logs; only its Stata process is replaced.
    shutil.copy2(source / 'tools/release/build-package.sh', root / 'tools/release/build-package.sh')
    compiler = root / 'bin/build-stata'
    compiler.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
mode = os.environ.get('CSDID_TEST_BUILD_MODE', 'complete')
with Path('calls.txt').open('a') as stream: stream.write('compiler:' + json.dumps(sys.argv) + '\\n')
assert sys.argv[1:] == ['-b', 'do', 'src/build.do']
if mode != 'missing-log':
    Path('build.log').write_text('' if mode == 'empty-log' else 'end of do-file\\n. do unfinished.do\\n' if mode == 'truncated-log' else
        'r(9);\\nend of do-file\\n' if mode == 'error-log' else 'end of do-file\\n')
if mode == 'process-failure': sys.exit(42)
if mode != 'missing-library': Path('build/lcsdid_v2.mlib').write_text('fresh fixture library')
''')
    compiler.chmod(0o755)
    startup = 'run-session-warmup.py'
    (root / 'calls.txt').write_text('')
    run(startup, 'complete', good=True)
    with (root / 'build/session-warmup.csv').open() as stream:
        startup_rows = list(csv.reader(stream))
    expected = [[phase, label, '1'] for _ in range(3) for phase in ('cold','agg','rif')
                for label in ('first','steady','steady')]
    if startup_rows != expected:
        raise SystemExit('startup phase workload/schema/order changed')
    calls = (root / 'calls.txt').read_text().splitlines()
    compiler_calls = [json.loads(line[len('compiler:'):]) for line in calls if line.startswith('compiler:')]
    consumer_calls = [json.loads(line[len('consumer:'):]) for line in calls if line.startswith('consumer:')]
    if (len(compiler_calls) != 1 or compiler_calls[0][0] != str(compiler) or
            len(consumer_calls) != 10 or any(call[0] != str(consumer) or len(call) != 4 for call in consumer_calls)):
        raise SystemExit('startup lost build/consumer runtime separation or phase process count')
    checks += 2
    for mode in ('missing-log', 'empty-log', 'truncated-log', 'error-log', 'process-failure',
                 'missing-result', 'duplicate-result', 'nan-result', 'zero-result'):
        run(startup, 'complete', good=True)
        run(startup, mode)
    for mode in ('missing-log', 'empty-log', 'truncated-log', 'error-log', 'process-failure', 'missing-library'):
        run(startup, 'complete', good=True)
        (root / 'calls.txt').write_text('')
        run(startup, 'complete', build_mode=mode)
        if 'consumer:' in (root / 'calls.txt').read_text():
            raise SystemExit('startup consumer ran after a failed package build')
        checks += 1

print(f'benchmark runtime gate: {checks} cases passed')
PY
