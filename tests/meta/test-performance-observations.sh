#!/usr/bin/env bash
# CSV-reader qualification only: no Stata process or timing measurement.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "${1:-$ROOT}" "${2:-}" <<'PYCODE'
import contextlib
import copy
import csv
import importlib.util
import io
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(sys.argv[1]).resolve()
only = sys.argv[2]
sys.path.insert(0, str(root / 'tools/bench'))

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, root / 'tools/bench' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

campaign = module('campaign', 'run-perf-campaign.py')
warmup = module('warmup', 'run-session-warmup.py')
passed = []

def check(name, action, reject=False):
    if only and name != only:
        return
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try:
            action()
        except SystemExit as error:
            if not reject or error.code in (None, 0):
                raise AssertionError(f'{name}: unexpected exit {error.code}') from error
        else:
            if reject:
                raise AssertionError(f'{name}: corrupted observations were accepted')
    passed.append(name)

# Explicit expected orders for settle round 0 and the first two rounds. These
# are fixtures, not a call to the reader's rotation implementation.
orders = {
    'routes': [['dr', 'ipw', 'reg', 'dr_rc'],
               ['reg', 'ipw', 'dr', 'dr_rc'],
               ['reg', 'dr_rc', 'dr', 'ipw']],
    'extended': [['dr_w', 'reg_w', 'reg_rc', 'dr_rc', 'dr', 'ipw', 'reg', 'dr_rc_w'],
                 ['reg', 'ipw', 'dr', 'dr_rc', 'reg_rc', 'reg_w', 'dr_w', 'dr_rc_w'],
                 ['reg', 'dr_rc_w', 'dr_w', 'reg_w', 'reg_rc', 'dr_rc', 'dr', 'ipw']],
    'agg': [['agg_storeall', 'agg_calendar', 'agg_simple', 'agg_group', 'agg_dynamic'],
            ['agg_simple', 'agg_group', 'agg_dynamic', 'agg_calendar', 'agg_storeall'],
            ['agg_storeall', 'agg_group', 'agg_dynamic', 'agg_calendar', 'agg_simple']],
}
buckets = ['setup', 'cell_extract', 'model_fit', 'if_assembly', 'cache_post',
           'cluster', 'bootstrap', 'aggregation', 'unprofiled', 'total']

def observations(kind):
    rows = []
    for round_, cells in enumerate(orders[kind]):
        for arm in ('head', 'base'):
            for position, cell in enumerate(cells, 1):
                if kind == 'agg':
                    for block in (1, 2, 3):
                        rows.append(['fixture', arm, str(round_), cell, str(position),
                                     str(block), '5000', '6' if cell == 'agg_storeall' else '25', '1'])
                else:
                    rc = '_rc' in cell
                    route = (cell.split('_')[0] + '|' +
                             ('fast-repeated-cross-section|repeated-cross-section' if rc
                              else 'fast-balanced-panel|panel'))
                    for bucket in buckets:
                        rows.append(['fixture', arm, str(round_), cell, route, str(position),
                                     '400', '50', bucket, '-0.001' if bucket == 'unprofiled' else '1'])
    return rows

with tempfile.TemporaryDirectory(prefix='csdid-perf-observations-') as tmp:
    work = Path(tmp)
    campaign.OUTDIR = work
    def run_campaign(rows, kind='routes'):
        with (work / 'fixture.csv').open('w', newline='') as stream:
            csv.writer(stream).writerows(rows)
        sys.argv = ['run-perf-campaign.py', '--instrument',
                    'perf-agg-warm' if kind == 'agg' else 'perf-inproc-routes',
                    '--tag', 'fixture', '--arms', 'head=HEAD,base=HEAD',
                    '--rounds', '2', '--report-only']
        if kind == 'extended':
            sys.argv.append('--include-qr-routes')
        campaign.main()

    base = observations('routes')
    check('campaign-complete', lambda: run_campaign(base))
    check('campaign-missing-cell', lambda: run_campaign([r for r in base if r[3] != 'reg']), True)
    check('campaign-missing-bucket', lambda: run_campaign(base[:-1]), True)
    check('campaign-duplicate', lambda: run_campaign(base + [base[0]]), True)
    check('campaign-malformed', lambda: run_campaign(base + [['truncated']]), True)
    # Each column except the value carries part of the observation's identity.
    for column, value, label in [(0, 'stale', 'tag'), (1, 'other', 'arm'),
                                 (2, '3', 'round'), (3, 'other', 'cell'),
                                 (4, 'reg|slow|panel', 'route'), (5, '9', 'position'),
                                 (6, '399', 'nunits'), (7, '49', 'reps'),
                                 (8, 'unknown', 'bucket')]:
        bad = copy.deepcopy(base)
        bad[0][column] = value
        check('campaign-' + label, lambda bad=bad: run_campaign(bad), True)
    for value in ('NaN', 'inf', '-inf', '-1', '0', 'no-number'):
        bad = copy.deepcopy(base)
        bad[9][-1] = value  # A total, which must be strictly positive.
        check('campaign-total-' + value, lambda bad=bad: run_campaign(bad), True)
    bad = copy.deepcopy(base)
    bad[0][-1] = '-1'
    check('campaign-negative-profile', lambda: run_campaign(bad), True)
    check('campaign-extended-complete', lambda: run_campaign(observations('extended'), 'extended'))
    check('campaign-extended-missing-weighted-route',
          lambda: run_campaign([r for r in observations('extended') if r[3] != 'dr_w'], 'extended'), True)
    agg = observations('agg')
    check('campaign-aggregation-complete', lambda: run_campaign(agg, 'agg'))
    check('campaign-aggregation-missing-block', lambda: run_campaign(agg[:-1], 'agg'), True)
    bad = copy.deepcopy(agg)
    bad[0][5] = '4'
    check('campaign-aggregation-wrong-block', lambda: run_campaign(bad, 'agg'), True)
    bad = copy.deepcopy(agg)
    bad[0][-1] = '0'
    check('campaign-aggregation-zero', lambda: run_campaign(bad, 'agg'), True)

    # Stub only external execution. main() still removes stale artifacts,
    # requires a new library, reads the produced CSV and makes the real verdict.
    warmup.ROOT = work
    warmup.OUT = work / 'build/warmup.csv'
    warmup.RIF = work / 'build/warmup-rif.dta'
    (work / 'build').mkdir()
    def build_stub(command):
        if command != ['bash', 'tools/release/build-package.sh']:
            raise AssertionError(f'unexpected external command: {command}')
        (work / 'build/lcsdid_v2.mlib').touch()
    warmup.run = build_stub
    complete = [[phase, label, '1'] for _ in range(2)
                for phase in ('cold', 'agg', 'rif')
                for label in ('first', 'steady', 'steady')]
    def run_warmup(rows):
        def phase_stub(name, *args):
            if name == 'rifbuild':
                with warmup.OUT.open('w', newline='') as stream:
                    csv.writer(stream).writerows(rows)
        warmup.phase = phase_stub
        sys.argv = ['run-session-warmup.py', '--reps', '2']
        warmup.main()
    check('warmup-complete', lambda: run_warmup(complete))
    check('warmup-missing-steady', lambda: run_warmup(complete[:-1]), True)
    check('warmup-duplicate', lambda: run_warmup(complete + [complete[0]]), True)
    check('warmup-malformed', lambda: run_warmup([['cold', 'first']] + complete[1:]), True)
    bad = copy.deepcopy(complete)
    bad[0], bad[1] = bad[1], bad[0]
    check('warmup-wrong-order', lambda: run_warmup(bad), True)
    bad = copy.deepcopy(complete)
    bad[0][0] = 'other'
    check('warmup-wrong-phase', lambda: run_warmup(bad), True)
    for value in ('NaN', 'inf', '-inf', '-1', '0', 'no-number'):
        bad = copy.deepcopy(complete)
        for row in bad:
            if row[:2] == ['cold', 'first']:
                row[2] = value
        check('warmup-value-' + value, lambda bad=bad: run_warmup(bad), True)

if not passed:
    raise AssertionError('no requested observation case ran')
print(f'Performance observations: {len(passed)} CSV qualification cases passed; no timing jobs run')
PYCODE
