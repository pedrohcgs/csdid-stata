#!/usr/bin/env bash
# Every published statistical row needs fresh, complete simulation evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import copy
import csv
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

root = Path.cwd()
checker = root / 'tools/release/check-reliability-tables.py'
original_article = (root / 'website/articles/csdid-against-the-field.md').read_text()
with tempfile.TemporaryDirectory(prefix='csdid-reliability-evidence-') as temporary:
    work = Path(temporary)
    raw = work / 'raw.csv.gz'
    raw.write_bytes(gzip.compress(b'regime,pkg,rep,h,est,se\nbalanced,csdid,1,0,2,1\n', mtime=0))
    sha = hashlib.sha256(raw.read_bytes()).hexdigest()
    packages = ['csdid', 'csdidpair', 'csdid_dr', 'csdid_ipw', 'csdid_reg',
                'jwdid', 'jwdid_uc', 'bjs', 'bjs_wtr', 'dcdh', 'dcdh_tnp',
                'lpdid', 'lpdid_rw', 'lpdid_ctl', 'lpdid_rw_ctl', 'sa', 'sa_xt']
    regimes = {'sampling_main': ['balanced', 'varmiss', 'unbalanced', 'rcs', 'rcsvar'],
               'covariates_panel': ['bal_ok', 'bal_owrong', 'bal_pwrong', 'bal_ps2'], 'covariates_rc': ['rcs','rcsvar'],
               'master': ['master'], 'unitroot': ['unitroot'], 'ctvar': ['ctvar'],
               'cohorthet': ['cohorthet'], 'hero': ['varmiss']}
    groups = {}
    for dataset, settings in regimes.items():
        reps = 100 if dataset in ('master', 'ctvar') else 500
        metrics = []
        for regime in settings:
            for package in packages:
                for horizon in (0, 1, 2, 3003, 5006):
                    metrics.append(dict(regime=regime, pkg=package, h=horizon,
                        attempted=reps, finite_estimates=reps, finite_se=reps,
                        bias=-.001 if ((dataset,regime,package,horizon) == ('sampling_main','rcsvar','jwdid',0) or (dataset,package,horizon) == ('master','lpdid_ctl',2)) else .001 * (horizon + 1), sd=(.1 if package == 'csdid' else .2) if dataset == 'unitroot' else (.2 if package == 'csdid' else .1), truth=2.516667+.633333*horizon if dataset == 'master' else 2+.5*horizon,
                        rmse=.2, mean_se=.14 if package == 'jwdid_uc' else .12,
                        coverage=.9, coverage_denominator=reps))
        groups[dataset] = dict(design=dataset, n=2000 if dataset == 'master' else 1000,
                               reps=reps, raw_file=raw.name, sha256=sha, metrics=metrics)
    joint = [dict(dataset_id=dataset, pkg=package, interval=interval,
                  hit=450, n=500, attempted=500, coverage=.9)
             for dataset, package, interval in
             [('bands', 'csdid_band', 'uniform_band'), ('bands', 'csdid_band', 'pointwise')] +
             [('sampling_main', package, 'pointwise') for package in ('jwdid', 'bjs', 'dcdh', 'lpdid')]]
    diagnostics = {key: dict(value=value, source_file=raw.name, sha256=sha) for key, value in {
        'tnp_x1_e2_bias': .1, 'hetx_se_gap_e0_percent': 11, 'hetx_se_gap_e2_percent': 55,
        'dcdh_se_gap_min_percent': 8, 'dcdh_se_gap_max_percent': 10,
        'sa_balanced_max_abs_point_difference': 0, 'lpdid_n1000_bias': .001, 'lpdid_n4000_bias': .001, 'lpdid_n1000_bias_mcse': .001, 'lpdid_n4000_bias_mcse': .0005, 'master_jwdid_uc_e2_mean_se_sd_ratio': 1.02}.items()}
    missing_values = {
        **{f'missing_xthdid_P1_h{h}_abs_gap': 1e-16 for h in range(3)},
        'missing_lpdid_P1_h0_abs_gap': .000992, 'missing_lpdid_P1_h1_abs_gap': 1e-15,
        'missing_lpdid_P1_h2_abs_gap': 1e-15, 'missing_dcdh_P1_max_abs_dynamic_gap': .000838,
        'missing_derived_post_cells': 22, 'missing_derived_unavailable_post_cells': 6,
        'missing_derived_total_post_cells': 28, 'missing_derived_xthdid_finite_without_pair': 6,
        'missing_derived_pair_max_abs': 1.6e-15, 'missing_derived_csdid_max_abs': 1.1e-15,
        'missing_xthdid_relabelled_units': 242, 'missing_xthdid_treated_units': 1615,
        'missing_xthdid_min_signed_dynamic_shift': -.015, 'missing_xthdid_max_signed_dynamic_shift': .0521,
        'missing_xthdid_max_abs_dynamic_shift': .0521,
        'missing_usercohort_post_cells': 22, 'missing_usercohort_total_post_cells': 22,
        'missing_usercohort_unavailable_post_cells': 0, 'missing_usercohort_xthdid_finite_without_pair': 0,
        'missing_usercohort_pair_max_abs': 2e-15, 'missing_usercohort_csdid_max_abs': 1.1e-15,
        'missing_usercohort_never_missing_rc': 3301, 'missing_jwdid_removed_rows': 6,
        'missing_jwdid_predicted_removed_units': 1, 'missing_jwdid_predicted_removed_rows': 6,
        'missing_jwdid_data_rows_removed': 0}
    missing_values.update({
        'publication_hetx_e0_se_gap_percent':11,'publication_hetx_e2_se_gap_percent':55,
        'publication_hetx_max_abs_point_difference':6e-9,'publication_hetx_verified_horizons':3,
        'publication_dcdh_min_se_gap_percent':8,'publication_dcdh_max_se_gap_percent':10,
        'publication_dcdh_max_abs_point_difference':8e-8,'publication_dcdh_verified_horizons':3})
    target_csv = work / 'target-check.csv'
    targets = [(0,2.516667,2.517,.000333),(1,3.15,3.1501,.0001),(2,3.783333,3.782,-.001333)]
    with target_csv.open('w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['h','population_target','empirical_target','difference']);writer.writerows(targets)
    target_sha = hashlib.sha256(target_csv.read_bytes()).hexdigest()
    for h,population,empirical,difference in targets:
        for field,value in [('population',population),('empirical',empirical),('difference',difference)]:
            diagnostics[f'target_check_e{h}_{field}']=dict(value=value,source_file=target_csv.name,sha256=target_sha)
    diagnostics['target_check_three_decimal_agreements']=dict(value=2,source_file=target_csv.name,sha256=target_sha)
    paired = []
    for dataset,settings in [('sampling_main',['balanced','varmiss','unbalanced']),('covariates_panel',['bal_ok'])]:
        for regime in settings:
            pair_roster=[('jwdid','bjs'),('jwdid','jwdid_uc')]
            if (dataset,regime)==('sampling_main','balanced'):pair_roster.append(('csdid','dcdh'))
            for left,right in pair_roster:
                for h in range(3):
                    paired.append(dict(dataset_id=dataset,regime=regime,left_pkg=left,right_pkg=right,h=h,attempted=500,matched_estimates=500,missing_left_only=0,missing_right_only=0,missing_both=0,max_abs_estimate_difference=1e-8))
    declines = [dict(dataset_id='covariates_panel',regime='bal_ps2',pkg=pkg,h=1,attempted=500,finite_estimate_reps=list(range(1,465)),missing_estimate_reps=list(range(465,501))) for pkg in ['csdid_ipw','csdid_dr']]
    for metric in groups['covariates_panel']['metrics']:
        if metric['regime']=='bal_ps2' and metric['pkg'] in ['csdid_ipw','csdid_dr'] and metric['h']==1:
            metric['finite_estimates']=464
            metric['finite_se']=464
    eq_csv=work/'eqgate.csv'
    with eq_csv.open('w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['seed','arm','h','b_branch','b_inline','se_branch','se_inline'])
        for seed in (90001,90002,90003):
            for arm in 'csdid_reg csdid_dr csdid_reg_nt lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh_tnp sa_xt'.split():
                for h in (0,1,2):writer.writerow([seed,arm,h,1.,1.,.1,.1])
    eq_output=dict(path=eq_csv.name,sha256=hashlib.sha256(eq_csv.read_bytes()).hexdigest())
    missing_csv = work / 'missing.csv'
    diagnostics.update({key: dict(value=value, source_file=missing_csv.name, sha256=sha)
                        for key, value in missing_values.items()})
    baseline = dict(status='complete', provenance={'fixture': 'qualification only'},
                    groups=groups, joint_metrics=joint, diagnostics=diagnostics,paired_metrics=paired,decline_sets=declines,diagnostic_jobs={'eqgate':{'outputs':[eq_output]}})
    statistics, article, hero = work / 'statistics.json', work / 'article.md', work / 'figcheck.csv'
    with hero.open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['label', 'reps', 'bias', 'coverage'])
        for label in ('csdid', 'jwdid', 'did_imputation', 'did_multiplegt_dyn', 'lpdid', 'eventstudyinteract'):
            writer.writerow([label, 500, .001, .9])
    original_hero = hero.read_bytes()
    command = ['python3', str(checker), str(statistics), '--article', str(article), '--hero-check', str(hero)]
    def execute(data, text, write=False, forged_scalar=False):
        data = copy.deepcopy(data)
        values = missing_values if forged_scalar else {k: d['value'] for k, d in data['diagnostics'].items() if k.startswith(('missing_','publication_'))}
        with missing_csv.open('w', newline='') as stream:
            writer = csv.writer(stream)
            writer.writerow(['metric', 'value'])
            writer.writerows(values.items())
        missing_sha = hashlib.sha256(missing_csv.read_bytes()).hexdigest()
        for key, diagnostic in data['diagnostics'].items():
            if key.startswith(('missing_','publication_')):
                diagnostic['sha256'] = missing_sha
        statistics.write_text(json.dumps(data))
        article.write_text(text)
        result = subprocess.run(command + (['--write'] if write else []), text=True, capture_output=True)
        return result, article.read_text()
    result, rendered = execute(baseline, original_article, write=True)
    assert result.returncode == 0, result.stderr
    assert 'all 67 statistical rows and 58 numerical narrative claims' in result.stdout
    result, unchanged = execute(baseline, rendered)
    assert result.returncode == 0 and unchanged == rendered, result.stderr
    checks = 2
    mutations = []
    for name, edit in [
        ('partial campaign', lambda d: d.update(status='partial')),
        ('missing covariate evidence', lambda d: d['groups'].pop('covariates_panel')),
        ('missing master effect', lambda d: d['groups']['master'].update(metrics=[m for m in d['groups']['master']['metrics'] if (m['pkg'], m['h']) != ('csdid_dr', 0)])),
        ('duplicate statistic', lambda d: d['groups']['master']['metrics'].append(d['groups']['master']['metrics'][0])),
        ('missing fresh diagnostic', lambda d: d['diagnostics'].pop('missing_usercohort_post_cells')),
        ('missing paired comparison', lambda d: d['paired_metrics'].pop(0)),
        ('unmatched paired point draws', lambda d: d['paired_metrics'][0].update(matched_estimates=499)),
        ('jointly shrunken paired point draws', lambda d: d['paired_metrics'][0].update(attempted=1,matched_estimates=1)),
        ('noninteger paired count', lambda d: d['paired_metrics'][0].update(attempted=500.0)),
        ('changed target rounding count', lambda d: d['diagnostics']['target_check_three_decimal_agreements'].update(value=3)),
        ('target scalar detached from CSV', lambda d: d['diagnostics']['target_check_e0_difference'].update(value=.5)),
        ('missing literal-command gate', lambda d: d['diagnostic_jobs'].pop('eqgate')),
        ('inconsistent decline count', lambda d: d['decline_sets'][0].update(missing_estimate_reps=[])),
        ('wrong raw hash', lambda d: d['groups']['hero'].update(sha256='0' * 64)),
        ('smoke design', lambda d: d['groups']['sampling_main'].update(reps=2)),
    ]:
        altered = copy.deepcopy(baseline)
        edit(altered)
        mutations.append((name, altered, rendered))
    for name, key, value in [
        ('lost xthdid agreement', 'missing_xthdid_P1_h0_abs_gap', .001),
        ('lost lpdid later-horizon agreement', 'missing_lpdid_P1_h2_abs_gap', .001),
        ('erased lpdid counterexample', 'missing_lpdid_P1_h0_abs_gap', 0),
        ('erased dcdh counterexample', 'missing_dcdh_P1_max_abs_dynamic_gap', 0),
        ('unsupported derived cell hidden', 'missing_derived_xthdid_finite_without_pair', 5),
        ('usercohort cell lacks support', 'missing_usercohort_unavailable_post_cells', 1),
        ('usercohort arithmetic drift', 'missing_usercohort_pair_max_abs', 1e-5),
        ('event shift no longer changes sign', 'missing_xthdid_min_signed_dynamic_shift', 0),
        ('different usercohort refusal', 'missing_usercohort_never_missing_rc', 198),
        ('jwdid screen mismatch', 'missing_jwdid_predicted_removed_rows', 7),
        ('physical data deletion', 'missing_jwdid_data_rows_removed', 1),
        ('wrong heterogeneity horizon labels','publication_hetx_verified_horizons',2),
        ('negative Monte Carlo standard error','lpdid_n4000_bias_mcse',-.001),
        ('wrong dcdh horizon labels','publication_dcdh_verified_horizons',2),
    ]:
        altered = copy.deepcopy(baseline)
        altered['diagnostics'][key]['value'] = value
        mutations.append((name, altered, rendered))
    mutations.append(('omitted table', baseline, rendered.replace('Joint coverage of the post-treatment path</p>', 'Unmapped joint table</p>')))
    mutations.append(('omitted narrative', baseline, rendered.replace('The uniform band has joint coverage of', 'A differently worded unverified claim has value')))
    mutations.append(('forged narrative value', baseline, rendered.replace('The uniform band has joint coverage of 0.900', 'The uniform band has joint coverage of 0.901')))
    mutations.append(('forged master value', baseline, rendered.replace(' +0.001 / 0.90 ', ' +0.009 / 0.90 ', 1)))
    for name, data, text in mutations:
        result, _ = execute(data, text)
        assert result.returncode != 0, name + ' was accepted'
        checks += 1
    altered = copy.deepcopy(baseline)
    altered['diagnostics']['missing_xthdid_relabelled_units']['value'] = 243
    result, _ = execute(altered, rendered, write=True, forged_scalar=True)
    assert result.returncode != 0, 'diagnostic scalar detached from source CSV was accepted'
    checks += 1
    original_eq = eq_csv.read_bytes()
    records = list(csv.DictReader(eq_csv.open()))
    for name, left, right in [('missing matched gate values','nan','nan'),('unequal gate values','1.0','2.0')]:
        records[0]['b_branch'],records[0]['b_inline']=left,right
        with eq_csv.open('w',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
        altered=copy.deepcopy(baseline)
        altered['diagnostic_jobs']['eqgate']['outputs'][0]['sha256']=hashlib.sha256(eq_csv.read_bytes()).hexdigest()
        result,_=execute(altered,rendered)
        assert result.returncode != 0,name+' was accepted'
        checks += 1
    eq_csv.write_bytes(original_eq)
    hero.write_text(hero.read_text().replace('0.9', '0.8', 1))
    result, _ = execute(baseline, rendered)
    assert result.returncode != 0, 'forged hero label was accepted'
    checks += 1
    hero.write_bytes(original_hero)
    statistics.write_text('rows: 126000   reps: 500\nlegacy partial summary\n')
    result = subprocess.run(command, text=True, capture_output=True)
    assert result.returncode != 0, 'legacy partial text summary was accepted'
    checks += 1
    assert (root / 'website/articles/csdid-against-the-field.md').read_text() == original_article
print(f'Reliability evidence: {checks} render, completeness and mutation cases pass; production article untouched')
PY
