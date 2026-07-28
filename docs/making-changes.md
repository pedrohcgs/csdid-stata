# Making changes to csdid

What is required of any change, and what test it must carry. `docs/merge-protocol.md`
states what must pass before a merge; this says what to *do*, change by change.

One rule underpins the rest: **a check that could not run is not a passing
check.** `preflight.sh` reports `PASS` / `FAIL` / `BLOCKED` and treats `BLOCKED`
as failure, for reasons the protocol document records.

```sh
bash tools/release/preflight.sh          # everything; required before merge
bash tools/release/preflight.sh --fast   # spec tier only; a pre-commit convenience
bash tools/release/preflight.sh --list   # what would run, and why
```

---

## What each kind of change requires

### A change that can alter a number

Anything under `src/mata/`, or an `.ado` path that reaches an estimate.

1. **Establish what the reference implementation does by reading its source or
   running it** — not by inference from our code or docs. Two defects were found
   only that way: `pscoretrim()` rejected `1.0` where `DRDID` accepts it, and the
   panel estimators skipped a propensity cap that `DRDID::drdid_panel` applies.
2. **Report parity as a measured number**: max `|dATT|`, max `|dSE|` on the
   affected designs. Never as a claim.
3. **A pure-performance change must be bit-identical.** Say so explicitly:
   "max |dATT| = 0, max |dSE| = 0". If it is not bit-identical it is not a
   performance change.
4. **Do not improve on the reference.** A more stable algorithm that returns
   different numbers breaks the contract. Cholesky is kept over QR for this
   reason alone.

**Test required:** a fixture comparison against a regenerated oracle, pinned at
the tolerance in `docs/tolerance-registry-v1.md`. Not a smoke test.

### A new option, or a change to one

1. Add it to `inst/spec/feature-matrix.csv` with a fixture id, a test file and an
   allowed terminal status.
2. Add a generator under `tools/parity/generators/<id>/` that produces the
   expected values from the reference implementation.
3. Add a Stata test that compares every cell, not a summary.
4. Document it in the relevant `.sthlp` and, if a user would reasonably choose
   between it and something else, in a website guide.

**Test required:** the option's behaviour *and* its refusal. An option that
silently accepts nonsense is a defect even when the happy path is right.

### A refusal, a warning, or a message

**Test required:** assert the return code and that the message names the
offending option. A refusal nothing asserts is a refusal that will be removed by
accident later.

### A change to anything shared

A return value, a signature, a schema, a label set, a config default, a
constant, a file format.

Enumerate the consumers first, name the contract (arity, names, order, units,
defaults), run the consumers end to end, and diff previously-reported outputs.
The dangerous change is the one that looks purely additive.

`e()` is a frozen public surface: see `docs/stored-results-api.md`. Adding to it
is a commitment.

### Documentation

Every Stata example in `README.md` and under `website/` is executed by
`tools/docs/check-doc-examples.py` in the `docs` tier. Write examples that run
from a clean session — each guide is self-contained on purpose, because readers
arrive from search engines rather than from page one.

A block that genuinely cannot run gets `<!-- norun -->` on the line before it.
Use it sparingly: a skipped block is an unverified one.

### A new or changed gate

**Qualify it**: seed the fault it targets, confirm it goes red, remove the
fault, confirm green. Record that you did. An unqualified gate is not weak
evidence, it is none. Several gates in this repository were fail-open when
written, including one that had never inspected a single file.

---

## Requirements on tests themselves

- **Compare values, not shapes.** A test asserting that two tables have the same
  number of rows, without invoking `csdid`, was once recorded as parity-verified.
- **Changing a test to make it pass requires justifying that the test was
  wrong** — in the commit message, argued. "The test failed" is not a reason.
- **`numeric_parity` is derived, never hand-edited.** Run
  `tools/spec/classify-numeric-parity.py --write`.
- **Expected outputs are generated, never edited by hand.** Each fixture's
  `metadata/manifest.json` names the command that produces it. Regenerating
  should be a no-op.
- **Every upstream test must be claimed.** All 292 `test_that` blocks in the
  reference implementation and all 392 in the Python port are pinned in
  `inst/spec/`, and the `spec` tier fails when one is unclaimed by an
  inheritance map or when a map cites a stale file hash. A test that has no
  Stata analogue is recorded as inapplicable *with a stated reason*, not left
  out.

---

## When the reference implementation releases a new version

This is the maintenance path that decays silently if ignored: `did` releases,
nobody notices, and every oracle here becomes a faithful record of what an old
version did — with all the parity claims still green.

```sh
bash tools/maint/sync-upstream-did.sh --check     # am I behind? changes nothing
bash tools/maint/sync-upstream-did.sh --upgrade   # reinstall, regenerate, report
```

`--upgrade` reinstalls from upstream, regenerates every oracle, reports exactly
which fixtures moved and which upstream tests are new, and refreshes the pinned
inventory. It commits nothing and decides nothing.

Then, by hand:

1. **Inherit every newly reported test.** Add the map row, and a Stata assertion
   where the behaviour is observable.
2. **Adjudicate every fixture that moved.** Either it is a real upstream
   behaviour change to mirror in the engine, or it is a divergence needing an
   approved row in the feature matrix with a decision reference. A regeneration
   that moves nothing is the expected outcome.
3. **Read the upstream `NEWS.md`.** Not every behaviour change moves a fixture we
   happen to cover; the 2.5.1 notes described a `notyettreated` fix that no
   existing fixture exercised.
4. **Run the full preflight.**

### Why the version string alone is not enough

`check-r-oracles.sh` fingerprints the *loaded code*, not `packageVersion()`. A
local install once reported 2.5.1 while its `compute.att_gt` lacked the
unit-folding factor real 2.5.1 applies. Every comparison against it was against
2.5.0 behaviour wearing a 2.5.1 label, and it produced a convincing 2x
divergence that did not exist. If a comparison shows a clean integer ratio
between two implementations, suspect the comparator before the code under test.

---

## Before merge

`docs/merge-protocol.md` holds the checklist. In short: a fully green
`preflight.sh` with no `BLOCKED` tier, parity reported as a measured number,
every divergence approved and recorded, every changed test justified, every new
gate qualified, and user-facing text free of implementation-comparison language.

There is no hosted CI — Stata is licence-locked, so a hosted runner cannot
execute the unit, docs, deep or JEL tiers. Enforcement is a receipt that
preflight writes only on a complete, fully green run, pinned to a digest of the
code exercised, plus a pre-push hook that refuses a push without one. Do not
route around it.
