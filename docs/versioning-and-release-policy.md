# Versioning And Release Policy

Status: frozen release-candidate policy for the modern Stata `csdid` rebuild.

## Current Public Build

The build is stamped `2.0.0` (release-owner decision, 2026-07-26). Every
version site is stamped from one place by `tools/release/stamp-version.py`, and
`tests/meta/test-version-consistency.sh` fails if they drift.

`2.0.0` succeeds the legacy 1.8x Stata `csdid` line. Note that neither the
legacy GitHub repository nor the SSC distribution carries a package-level
version: the repository versions individual files (`csdid.ado` reached
`v1.82`) and SSC signals updates only through `Distribution-Date`. `2.0.0` is
therefore the first package-level version in this lineage.

### Outstanding against the tag rule below

The version string is set, but these Final Tag Rule conditions are **not yet
satisfied** and are tracked as release blockers, not waived:

- Platform matrix records **macOS only**; Windows and Linux have no recorded
  pass and no signed waiver.
- **No independent Stata/Mata or econometrics reviewer** has signed the packet.
- The legacy-to-candidate A/B certification (`CSDID_RUN_LEGACY_AB=1`), which
  `inst/spec/bench-budgets.yml` marks "required release certification", has
  never been run.
- The R-relative performance budgets in `inst/spec/bench-budgets.yml` predate
  the parity engine; 11 of 24 exceed them on a quiet machine and the budgets
  need re-setting deliberately.

## Final Tag Rule

Tag `v2.0.0` only after all of the following are true:

- The required release checks in `docs/release-checklist.md` pass.
- The platform matrix in `docs/platform-matrix.md` has at least one recorded
  pass on macOS, Windows, and Linux, or an explicit release-owner waiver.
- At least one independent Stata/Mata reviewer and one independent econometrics
  reviewer have reviewed the packet in `docs/independent-review-packet.md`.
- Any difference from R `did` 2.5.1 is either fixed or recorded as an approved
  divergence in the frozen contract.
- The release notes state the exact R `did` oracle source, the Stata version
  surface, bootstrap scope, default behavior, and legacy migration policy.

## Version Semantics

- `2.0.0-rcN`: public release candidate for collaborator and external testing.
- `2.0.0`: first world-facing replacement release for the modern R-parity
  Stata implementation.
- Patch releases after `2.0.0` may fix bugs, documentation, performance, and
  compatibility warnings, but may not change R-matching defaults.
- Any estimator, inference, aggregation, plotting, or storage behavior change
  requires the gate in `docs/model-improvement-required-tests.md`.

## Stored Version Surface

`csdid version` and `e(version)` must report the package version. F026 checks
the stored result version surface, and future releases must update that fixture
when the public version changes.
