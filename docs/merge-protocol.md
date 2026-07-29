# Merge protocol

Nothing merges into `csdid-stata` unless everything below is satisfied. This
applies to every change — a one-line help fix included.

The mechanical part is a single command:

```sh
bash tools/release/preflight.sh
```

It must print `all preflight checks passed` and exit 0. The rest of this
document covers what a script cannot check.

---

## 0. The rule that makes the rest work

**A check that could not run is not a passing check.**

This repository has been bitten by that repeatedly:

- `test-public-help-surface.sh` ran `grep PATTERN src/help` with no `-r`. On a
  directory `grep` errors and returns non-zero, so the `if` never fired. The
  gate meant to keep help files user-facing had never inspected a single file.
- `run-smoke.sh` aborted on a missing JEL checkout *before* reaching any Stata
  test, while still looking like it had run a suite.
- `RT016` was marked `parity-verified` on the strength of a test that asserted
  two spreadsheets had the right number of rows and never invoked `csdid`.

`preflight.sh` therefore reports `PASS` / `FAIL` / `BLOCKED` and treats
`BLOCKED` as failure. If a prerequisite is missing, install it and run the
check — or record the gap under §5 and get it signed off. Never assume.

---

## 1. Mechanical gates (`preflight.sh`)

| Tier | What it runs | Why |
| --- | --- | --- |
| `spec` | `validate-contract.py` + `check-upstream-coverage.py` + all 13 `tests/meta/*.sh` | Catches the project misdescribing itself: a manifest naming untracked files, a ledger row claiming evidence it lacks, versions that disagree, an upstream `did` test no inheritance map claims |
| `build` | `src/build.do` | The `.mlib` must build; a stale library silently shadows source edits |
| `unit` | the whole Stata suite: 117 tests across `tests/stata/test-*.do`, `smoke-basic.do`, `tests/stata/r/` and `tests/stata/python/` | The tests of `csdid` itself, including every test inherited from the R and Python suites |
| `docs` | `check-doc-examples.py` — runs every Stata block in `README.md` and every website guide | A documented example that does not run is worse than no example: the reader assumes the failure is theirs |
| `parity` | `check-r-oracles.sh` | The installed `did`/`DRDID` must match the pinned versions the frozen oracles were generated against |
| `jel` | `run-jel-smoke.sh` | Empirical reproduction |

`preflight.sh --fast` runs the `spec` tier only. It is a pre-commit
convenience and **never a merge verdict**.

Stata exits 0 even when a do-file aborts, so `preflight.sh` scans each log for
`r(NNN);` rather than trusting the exit status. Do not "simplify" that.

---

## 2. Numeric changes

Any change touching `src/mata/`, or any `.ado` path that alters a number:

1. **Establish what R does by reading its source or running it.** Not by
   inference from our code or docs. Two defects this session were found only
   that way: `pscoretrim()` rejected `1.0` when `DRDID` accepts it, and the
   panel estimators skipped the `pmin(ps.fit, 1 - 1e-06)` cap that
   `DRDID::drdid_panel` applies.
2. **Report parity as a measured number** — max `|dATT|`, max `|dSE|` against R
   on the affected designs. Never as a claim.
3. **A pure-performance change must be bit-identical.** State it: "max |dATT| =
   0, max |dSE| = 0". If it is not bit-identical, it is not a performance
   change and belongs in §3.
4. **Do not improve on R.** A more stable algorithm that returns different
   numbers breaks the contract. Cholesky is kept over QR for exactly this
   reason.

## 3. Divergences from R

Matching R is binding. A divergence merges only when:

- the owner has explicitly approved it, and
- it has a row in `inst/spec/feature-matrix.csv` with an approved terminal
  status and a named divergence id, and
- `test-feature-matrix-integrity.sh` passes with it recorded.

Undocumented divergence is a defect, not a decision.

## 4. Tests and the ledger

- **Changing a test to make it pass requires justifying that the test was
  wrong.** Two assertions were rewritten this session because they encoded
  defects (`pscoretrim(1)` → rc 198; the generic `from()` message). Both are
  argued in the commit message. "The test failed" is not a reason.
- **A new or fixed gate must be qualified**: seed the fault it targets, confirm
  it goes red, remove the fault, confirm green. An unqualified gate is not weak
  evidence — it is none.
- **`numeric_parity` is derived, never hand-edited.** Run
  `tools/spec/classify-numeric-parity.py --write`. The integrity gate fails if
  the column disagrees with what the tests actually do.

## 5. Environment gaps

If a tier is `BLOCKED`, the change does not merge on the strength of the tiers
that did run. Either resolve the prerequisite, or record in the PR: which tier
was blocked, why, what risk that leaves, and the owner's explicit acceptance.

Known standing gaps at the time of writing:

- **Stata 14/15 floor is declared but untested.** `csdid.pkg` says
  `Requires: Stata version 14`; no run on 14 or 15 has happened.
- **Windows and Linux platform rows** are unfilled.
- **JEL reproduction** resolves `$JEL_DID_REFERENCE`, else the sibling
  `GitHub/JEL-DiD` checkout. Verified present at the pinned commit
  `50f4f18` on the maintainer's machine, so this tier runs; it will be
  BLOCKED on any machine without that checkout.

### When `did` releases a new version

`inst/spec/upstream-did-tests.csv` pins every `test_that` block in the `did`
test suite, with the sha256 of the file it came from. The `spec` tier fails if
any pinned test is unclaimed by an inheritance map, or if a map cites a sha
other than the pinned one. Point `CSDID_DID_UPSTREAM` at a `did` checkout and
it additionally reports tests the checkout has and the pin does not.

So on a new `did` release:

1. `git -C <did checkout> pull`, then reinstall so the R oracle *is* that
   version — `check-r-oracles.sh` fingerprints the loaded code rather than
   trusting `packageVersion()`, because a local build once reported 2.5.1 while
   running 2.5.0 arithmetic and produced a convincing false divergence.
2. `python3 tools/spec/check-upstream-coverage.py --upstream <checkout>` to list
   what moved.
3. Inherit the new tests, refresh the pin, regenerate the affected oracles, and
   diff them. A regeneration that changes nothing is the expected outcome; a
   fixture that moves is either a real upstream behaviour change to mirror or a
   divergence to record.

## 6. User-facing text

Manuals and help files present `csdid` as a stand-alone Stata implementation
and must not mention R, `did`, `DRDID`, or parity. This is enforced by the
negative check in `test-release-productization.sh`. It does **not** relax §2 or
§3: R remains the oracle everywhere else — tests, `docs/`, `reports/`,
`inst/spec/`, code comments, and `NEWS.md`.

## 7. Human review

- Two independent reviewers: one Stata/Mata, one econometrics.
- Every breaking change appears in `NEWS.md` and
  `docs/legacy-migration-guide.md`.
- Anything the owner must decide is listed explicitly in the PR body rather
  than resolved silently.

---

## Pre-merge checklist

```
[ ] tools/release/preflight.sh  ->  all preflight checks passed
[ ] no tier BLOCKED (or gap recorded and signed off, §5)
[ ] numeric change: parity measured and reported, or bit-identical stated (§2)
[ ] any divergence approved and recorded in the feature matrix (§3)
[ ] any changed test justified as previously wrong (§4)
[ ] any new/changed gate qualified by seeding its fault (§4)
[ ] user-facing text free of R (§6)
[ ] NEWS.md and migration guide updated for breaking changes (§7)
[ ] owner decisions listed in the PR body, not silently resolved (§7)
[ ] two independent reviewers (§7)
```
