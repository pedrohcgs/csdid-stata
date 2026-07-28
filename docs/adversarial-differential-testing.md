# Adversarial Differential Testing

Status: required final-release and model-improvement gate.

Fixed fixtures are necessary but not sufficient. The package also needs
randomized R-vs-Stata differential tests that generate valid designs and
compare the resulting public estimands.

## Required Coverage

The adversarial gate must include:

- balanced panels;
- unbalanced `ivar()` panels routed through R-compatible repeated-cross-section
  semantics;
- repeated cross sections;
- covariates;
- weights;
- `dr`, `ipw`, and `reg`;
- near-collinear covariates;
- extreme but positive weights;
- shuffled row order;
- postestimation aggregation smoke.

## Current Gate

Run:

```bash
python3 tools/release/run-adversarial-differential.py
```

The gate writes data, R references, Stata output, and a comparison CSV under
`build/adversarial-differential/`.

## Acceptance Rule

Every scenario must satisfy the configured ATT and standard-error tolerances.
Any failure is a release blocker unless the scenario is invalid and the invalid
reason is recorded in the gate output.

## Expansion Rule

Before final `v2.0.0`, reviewers should add at least three additional designs
that they did not share with the implementer in advance. Those designs should
be preserved as fixtures if they reveal bugs or materially increase coverage.
