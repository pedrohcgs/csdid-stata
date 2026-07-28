# Final Release Certification

Status: required for final `v2.0.0`.

The `2.0.0-rc1` build is a release candidate. Final `v2.0.0` is a public
statistical-product release and must be certified as such. The standard is not
"tests passed on one machine"; the standard is reproducible correctness,
maintainability, supportability, and platform behavior.

## Certification Board

Final release requires explicit sign-off from:

- Release owner.
- Stata/Mata implementation reviewer.
- Econometrics reviewer.
- Platform-matrix coordinator.
- Documentation/support reviewer.

No reviewer may sign off on their own implementation work as the sole evidence.

## Blocking Gates

Final `v2.0.0` requires:

- Contract validation.
- All meta gates.
- Full smoke.
- JEL smoke.
- Full JEL reproduction.
- Opt-in performance.
- Pinned legacy-to-candidate time and process-RSS certification.
- F026 stored-version check.
- F049 R-relative performance gate.
- F050 isolated install gate.
- F051 defaults/API/UX gate.
- Release hardening gate.
- Failure-mode gate.
- Adversarial differential gate.
- Clean Stata batch-log tail scans.
- `git diff --check`.
- Clean handoff install verification from the generated zip.

## External Evidence

Final `v2.0.0` also requires:

- macOS platform row.
- Windows platform row.
- Linux platform row.
- Stata/Mata independent code-review sign-off.
- Independent econometrics review sign-off.
- Recorded disposition of every review finding.

Each review sign-off must explicitly set:

```text
Final release approved: yes
Blocking findings remaining: none
```

Each platform row must include `release_gates_status=pass`.

External rows may be waived only by the release owner, and the waiver must
state the reason, risk, and follow-up issue.

## Release Decision

Approve final release only when every blocking item is one of:

- `pass`
- `waived-by-release-owner`
- `not-applicable-with-recorded-reason`

Any numerical mismatch with R `did` 2.5.1 is a blocker unless already recorded
as an approved divergence in the frozen contract.

## Post-Release Rule

After `v2.0.0`, estimator, inference, aggregation, plotting, storage, parser,
and performance changes must go through `docs/model-improvement-required-tests.md`.
The release owner may accept documentation-only changes without the full
statistical gate only when no executable package behavior changes.
