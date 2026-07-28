# Econometrics Review Sign-Off

Reviewer:

Date:

Repository commit:

R did source:

Stata version/edition:

Operating system:

## Scope Reviewed

- DR/IPW/REG ATT(g,t)
- covariates
- weights
- unbalanced panels
- repeated cross sections
- clustering
- bootstrap
- aggregation
- plotting data
- JEL reproduction

## Required Comparisons

Record at least three reviewer-selected designs that were compared directly
against R `did` 2.5.1:

| Design | Stata command/log | R script/log | Result |
| --- | --- | --- | --- |

## Required Commands Run

- `python3 tools/release/run-adversarial-differential.py`
- `bash tests/run-smoke.sh`
- `bash tests/run-jel-smoke.sh`
- `CSDID_RUN_JEL_FULL=1 bash tests/run-jel-full-reproduction.sh`

## Findings

| ID | Severity | Surface | Finding | Disposition |
| --- | --- | --- | --- | --- |

## Sign-Off

Final release approved: no

Blocking findings remaining: pending

I approve final `v2.0.0` from an econometrics/user-surface perspective:

Reviewer signature:

Release-owner disposition:
