# Proposed default changes: `notyet` and `base_period(universal)`

**Status: proposed, not implemented. Owner decision required before it lands.**

You proposed two changes to Stata's defaults relative to R:

1. `base_period(universal)` instead of `varying`
2. not-yet-treated instead of never-treated as the comparison group

I did not implement them overnight, for one specific reason: your autonomy
instruction was *"you can fix things, as long as you audit and match R."* These
changes are, by construction, a departure from R on the path almost everyone
takes. That is your call to make explicitly, not mine to infer from a proposal.

Here is what I found, so the decision is one read rather than an investigation.

## Blast radius, measured

| | |
| --- | --- |
| `csdid` invocations in the Stata suite | 667 |
| …that rely on **both** current defaults | **541 (81%)**, across 97 files |
| `att_gt()` calls in the R oracle generators | 155 |
| …that rely on R's defaults | **155 (100%)** |

Every R oracle in the repository was generated with never-treated + varying.
Nothing pins those options because, today, they are also Stata's defaults, so
"compare defaults to defaults" was the same as "compare like to like".

The moment Stata's defaults differ from R's, all 541 default-relying
invocations stop testing what they claim to test.

## What each change costs

**Not-yet-treated as default.** This is the larger change of the two.

- It alters the *estimand's identifying assumption* by default: parallel trends
  must hold against later-treated cohorts, not only against never-treated ones.
  A user who never reads the docs gets an answer resting on a stronger
  assumption than they may realise.
- It interacts with anticipation. Later-treated cohorts inside their own
  anticipation window are not clean controls, which is why `anticipation()`
  exists — but the default would now lean on those cohorts.
- It changes results silently for anyone upgrading from Version 1.82 *and* for anyone
  cross-checking against R or the Python package. The README currently says
  results "are comparable across all three." That would no longer be true by
  default.

**Universal base period as default.** Smaller, but with a documentation
conflict.

- Post-treatment effects are unchanged. Only pre-treatment cells move, plus one
  extra row per cohort (the g-1 normalisation, which is 0 by construction).
- It is the better default for the most common *presentation* — event-study
  plots with a single normalised reference period.
- It is the worse default for *pre-testing*, because pre-treatment estimates
  become serially correlated: one bad early period shifts every later point, so
  a single deviation can look like a systematic trend.
- The package's own new guide says, in `website/articles/base-periods.md`:
  "For pre-testing, prefer `varying`." If `universal` becomes the default, that
  guidance and the default point in opposite directions. One of them has to
  change.

## Three ways to implement, if you want them

**A. Pin the old options in every parity test (recommended).**
Add explicit `base_period(varying)` and never-treated to the 541 invocations
that currently rely on defaults, so they keep comparing like with like against
the existing oracles. Then add a smaller set of new tests asserting the new
defaults are what the docs say. Parity coverage is preserved on both paths and
no oracle is regenerated.
*Cost: a large mechanical edit across 97 files, verifiable because the suite
must stay green with byte-identical oracles.*

**B. Regenerate every oracle under the new defaults.**
Change the R generators to pass `control_group="notyettreated",
base_period="universal"`, regenerate all 155 calls, and leave the Stata tests
alone.
*Cost: every expected value in the repository changes at once, so the
regeneration cannot be verified by "nothing moved" — the strongest check we
have. I would not do it this way.*

**C. Change the recommendation, not the default.**
Keep R's defaults; make the guides and help files recommend `notyet` and
`universal` prominently, with the reasoning. Costs nothing, breaks nothing, and
loses only the convenience of not typing two options.

## My recommendation

Take **`universal` via option A**, and think harder about **`notyet`**.

The base-period change is defensible: it does not touch post-treatment
estimates, it matches how nearly everyone presents results, and the cost is
confined to pre-treatment cells and one extra row. If you take it, the
pre-testing guidance needs rewriting so the package does not contradict itself —
I would say plainly that the default suits presentation and that `varying` is
better when you are pre-testing, rather than leaving the current wording.

The comparison-group change worries me more, not because `notyet` is wrong —
it is often the better estimator — but because it changes the identifying
assumption silently for every user who does not pass an option, and it is the
one place where a Stata user comparing against R or Python would get different
numbers with no indication why. If you want it, I would want the output to
state the comparison group prominently (it is already in `e(control_group)`),
and `NEWS.md` to lead with it.

Either way both changes are breaking, need approved-divergence rows in
`inst/spec/feature-matrix.csv` with decision references, and belong at the top
of `NEWS.md` as deviations from both R and Version 1.82 — which is exactly what you
said.
