#!/usr/bin/env bash
# Reader and comparator qualification; the parity tier runs the R collector test.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "${1:-$ROOT}" "${2:-}" <<'PYCODE'
import base64
import copy
import contextlib
import io
import hashlib
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(sys.argv[1]).resolve()
only = sys.argv[2]
spec = importlib.util.spec_from_file_location('conditioning_harness', root / 'tools/parity/run-differential-campaign.py')
m = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = m
spec.loader.exec_module(m)
passed = []

def check(name, action):
    if only and name != only:
        return
    action()
    passed.append(name)

with tempfile.TemporaryDirectory(prefix='csdid-conditioning-') as tmp:
    m.BUILD = Path(tmp)
    def fixture(ncov=0, gap=0, raw_collinear=False):
        for path in m.BUILD.iterdir():
            path.unlink()
        t = m.Trial(name='capture', seed=1, n_units=6, n_periods=2,
            time_start=1, time_step=1, cohort_spec='short', never_share=.5,
            unbalanced=False, n_covars=ncov, weighted=False, clustered=False,
            n_clusters=2, method='reg', control_group='nevertreated',
            base_period='universal', anticipation=0, panel_mode='balanced')
        rows = []
        for time in (1, 2):
            for id_ in range(1, 7):
                x1 = id_ / 4 + time / 8
                x2 = x1 + (id_ % 3 - 1) * 1e-5 if time == 1 or raw_collinear else (id_ % 4) / 3
                rows.append(dict(id=id_,time=time,g=0 if id_<=3 else 2,y=id_+time,x1=x1,x2=x2))
        data = m.pd.DataFrame(rows)
        input_ = m.BUILD / 'capture-data.csv'
        data.to_csv(input_, index=False)
        cells = m.pd.DataFrame(dict(group=[2,2], time=[1,2], att=[0.,2.], se=[0.,.1]))
        cells.to_csv(m.BUILD/'capture-r-cells.csv',index=False)
        cells.loc[1,'att'] += gap
        cells.to_csv(m.BUILD/'capture-stata-cells.csv',index=False)
        (m.BUILD/'capture-stata-rc.txt').write_text('0')
        meta = m.pd.DataFrame(dict(wpval=[float('nan')],n_cells=[2],n_units=[6]))
        for arm in ('r','stata'):
            meta.to_csv(m.BUILD/f'capture-{arm}-meta.csv',index=False)
        aggregates = {}
        for kind, effects in [('simple',[float('nan')]),('dynamic',[-1,0]),('group',[2]),('calendar',[2])]:
            records = m.pd.DataFrame(dict(egt=effects,att=[2.]*len(effects),se=[.1]*len(effects),
                overall_att=[2.]*len(effects),overall_se=[.1]*len(effects),pointwise=[1.95996398454005]*len(effects)))
            for arm in ('r','stata'):
                records.to_csv(m.BUILD/f'capture-{arm}-agg-{kind}.csv',index=False)
            (m.BUILD/f'capture-stata-aggrc-{kind}.txt').write_text('0')
            supports = {'overall':['2:2']}
            if kind != 'simple':
                supports.update({f'egt:{e}':['2:1' if e==-1 else '2:2'] for e in effects})
            aggregates[kind] = dict(status='complete',supports=supports)
        x = m.np.ones((6,1)) if ncov==0 else m.np.column_stack([m.np.ones(6),data.loc[:5,['x1','x2']].values])
        captured = dict(group=2,time=2,pre=1,status='fitted',rows=6,columns=ncov+1,route='panel',
            X_f64le=base64.b64encode(x.astype('<f8').tobytes(order='F')).decode(),
            ids=list(range(1,7)),periods=[1]*6,D=[0,0,0,1,1,1],weights=[1]*6)
        capture = dict(schema=1,trial=t.name,spec=m.asdict(t),
            input_sha256=hashlib.sha256(input_.read_bytes()).hexdigest(),errors=[],
            cells=[dict(group=2,time=1,status='structural_zero'),captured],
            wald=dict(status='missing',support=[]),aggregations=aggregates)
        (m.BUILD/'capture-r-designs.json').write_text(json.dumps(capture))
        return t,capture

    def verdict(t, expected):
        result=m.compare_trial(t)
        channels={r['channel'] for r in result}
        assert channels==expected,(channels,expected,result)
    def complete():
        t,_=fixture();verdict(t,set())
    check('complete',complete)
    def automatic_panel():
        t,c=fixture();t.panel_mode='unbalanced_allowed';c['spec']=m.asdict(t)
        (m.BUILD/'capture-r-designs.json').write_text(json.dumps(c));verdict(t,set())
    check('automatic-balanced-route',automatic_panel)
    def refused_aggregation(contradictory=False):
        t,c=fixture()
        c['aggregations']['simple']=dict(status='refused',supports={},errors=['incomplete helper before reference refusal'])
        (m.BUILD/'capture-r-aggerr-simple.txt').write_text('reference refusal')
        (m.BUILD/'capture-stata-aggrc-simple.txt').write_text('459')
        if not contradictory:(m.BUILD/'capture-r-agg-simple.csv').unlink()
        (m.BUILD/'capture-r-designs.json').write_text(json.dumps(c))
        verdict(t,{'conditioning_unverified'} if contradictory else set())
    check('refused-aggregation-trace',refused_aggregation)
    check('refused-with-returned-estimates',lambda:refused_aggregation(True))
    def overstated():
        t,_=fixture(gap=1e-5,raw_collinear=True)
        verdict(t,{'attgt'})
    check('overstated-unused-covariates',overstated)
    def understated():
        t,_=fixture(ncov=2,gap=1e-5)
        verdict(t,set())
    check('understated-stacked-periods',understated)
    def missing():
        t,_=fixture();(m.BUILD/'capture-r-designs.json').unlink()
        verdict(t,{'conditioning_unverified'})
    check('missing-capture',missing)
    mutations = {
        'wrong-input':lambda c:c.update(input_sha256='0'*64),
        'wrong-spec':lambda c:c['spec'].update(n_covars=2),
        'observer-error':lambda c:c.update(errors=['trace failed']),
        'missing-cell':lambda c:c['cells'].pop(),
        'duplicate-cell':lambda c:c['cells'].append(copy.deepcopy(c['cells'][-1])),
        'absent-matrix':lambda c:c['cells'][-1].pop('X_f64le'),
        'truncated-matrix':lambda c:c['cells'][-1].update(X_f64le=''),
        'extra-covariate':lambda c:c['cells'][-1].update(columns=3),
        'wrong-route':lambda c:c['cells'][-1].update(route='rcs'),
        'duplicate-row':lambda c:c['cells'][-1]['ids'].__setitem__(0,2),
        'missing-row-id':lambda c:c['cells'][-1]['ids'].pop(),
        'bad-treatment':lambda c:c['cells'][-1]['D'].__setitem__(0,2),
        'negative-weight':lambda c:c['cells'][-1]['weights'].__setitem__(0,-1),
        'false-normalization':lambda c:c['cells'][-1].update(status='structural_zero'),
        'missing-wald':lambda c:c.pop('wald'),
        'false-wald-status':lambda c:c['wald'].update(status='complete'),
        'missing-aggregation':lambda c:c['aggregations'].pop('dynamic'),
        'malformed-aggregation':lambda c:c['aggregations'].update(dynamic=[]),
        'returned-aggregation-trace-error':lambda c:c['aggregations']['simple'].update(errors=['missing helper']),
        'missing-support-row':lambda c:c['aggregations']['dynamic']['supports'].pop('egt:0'),
        'unknown-support':lambda c:c['aggregations']['dynamic']['supports'].update(overall=['9:9']),
        'duplicate-support':lambda c:c['aggregations']['dynamic']['supports'].update(overall=['2:2','2:2']),
        'empty-finite-support':lambda c:c['aggregations']['simple']['supports'].update(overall=[]),
    }
    for label,mutation in mutations.items():
        def run(mutation=mutation):
            t,c=fixture();mutation(c)
            (m.BUILD/'capture-r-designs.json').write_text(json.dumps(c))
            verdict(t,{'conditioning_unverified'})
        check(label,run)
    def nan_matrix():
        t,c=fixture();c['cells'][-1]['X_f64le']=base64.b64encode(m.np.full((6,1),m.np.nan,dtype='<f8').tobytes()).decode()
        (m.BUILD/'capture-r-designs.json').write_text(json.dumps(c));verdict(t,{'conditioning_unverified'})
    check('nonfinite-matrix',nan_matrix)
    def nonfit_support():
        t,c=fixture();c['cells'][-1]['status']='missing'
        r=m.pd.read_csv(m.BUILD/'capture-r-cells.csv');r.loc[1,['att','se']]=m.np.nan
        for arm in ('r','stata'):r.to_csv(m.BUILD/f'capture-{arm}-cells.csv',index=False)
        (m.BUILD/'capture-r-designs.json').write_text(json.dumps(c));verdict(t,{'conditioning_unverified'})
    check('failed-cell-in-support',nonfit_support)
    def missing_se():
        t,_=fixture()
        for arm in ('r','stata'):
            p=m.BUILD/f'capture-{arm}-cells.csv';r=m.pd.read_csv(p);r.loc[1,'se']=m.np.nan;r.to_csv(p,index=False)
        verdict(t,set())
    check('finite-att-missing-se',missing_se)
    def svd_failure():
        t,_=fixture();previous=m.np.linalg.cond
        def failed(x):raise m.np.linalg.LinAlgError('seeded SVD failure')
        try:
            m.np.linalg.cond=failed;verdict(t,{'conditioning_unverified'})
        finally:m.np.linalg.cond=previous
    check('condition-failure',svd_failure)
    def duplicate_result():
        t,_=fixture();path=m.BUILD/'capture-r-cells.csv';r=m.pd.read_csv(path)
        m.pd.concat([r,r.iloc[[0]]]).to_csv(path,index=False)
        verdict(t,{'conditioning_unverified'})
    check('duplicate-reference-result',duplicate_result)
    def empty_aggregation():
        t,_=fixture();path=m.BUILD/'capture-r-agg-simple.csv'
        m.pd.read_csv(path).iloc[:0].to_csv(path,index=False)
        verdict(t,{'conditioning_unverified'})
    check('empty-aggregation-result',empty_aggregation)
    def fresh_reference():
        t,_=fixture();stale=m.BUILD/'capture-r-error.txt';stale.write_text('older refusal')
        m.write_r_script(m.BUILD/'new-campaign.R',[t])
        assert not list(m.BUILD.glob('capture-r-*'))
        assert (m.BUILD/'capture-data.csv').is_file()
        assert (m.BUILD/'capture-stata-cells.csv').is_file()
    check('fresh-reference-artifacts',fresh_reference)
    def unverified_exit():
        t,_=fixture();(m.BUILD/'capture-r-designs.json').unlink()
        argv,draw=sys.argv,m.draw_trial
        try:
            sys.argv=['campaign','--compare-only','--trials','1']
            m.draw_trial=lambda *args:t
            with contextlib.redirect_stdout(io.StringIO()):assert m.main()==2
            record=json.loads((m.BUILD/'campaign-result.json').read_text())
            assert record['divergences'][0]['channel']=='conditioning_unverified'
        finally:sys.argv,m.draw_trial=argv,draw
    check('unverified-process-exit',unverified_exit)
    def constant_bound():
        assert m.TOL==dict(att=1e-7,se=1e-6,crit=1e-9,pval=1e-7,exact=0.)
        assert m.conditioning_bound(1e-7,1)==1e-7
        assert m.conditioning_bound(1e-7,1e5)==10*2.220446049250313e-16*1e5*1e5
    check('unchanged-bound',constant_bound)
if not passed:raise AssertionError('no requested conditioning case ran')
print(f'Differential conditioning: {len(passed)} reader/comparator qualification cases passed')
PYCODE
