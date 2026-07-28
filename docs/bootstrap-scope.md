# Bootstrap Scope

Status: release-candidate scope statement for bootstrap support.

## What Is Supported

`csdid` supports multiplier bootstrap inference through `wboot()`.

Supported public surfaces:

- ATT(g,t) multiplier bootstrap for panel and repeated-cross-section workflows.
- Clustered ATT(g,t) multiplier bootstrap using cluster-summed influence
  functions.
- Aggregation bootstrap postprocessing through `csdid_stats` and `estat`.
- Pointwise and simultaneous-band interval metadata.
- Stata-style shorthand `wboot reps(#) seed(#)` and `wboot reps(#) rseed(#)`.
- R-compatible rademacher multiplier aliases. Unsupported `normal`,
  `gaussian`, and `mammen` multiplier names fail loudly rather than being
  silently coerced.

## Reproducibility Contract

Bootstrap point estimates must match the analytical point estimates. Bootstrap
standard errors and critical values are stochastic quantities and are tested
against the frozen tolerance registry rather than exact byte-for-byte equality.

The release contract checks exact seeded multiplier-stream probes where the R
test surface exposes a deterministic stream. It does not promise that every
raw exported draw matrix will match R byte-for-byte across Stata platforms.

## Performance Contract

Bootstrap is measured separately from analytical estimation because setup,
random draws, and replication count dominate runtime. The current release gate
keeps the required F049 bootstrap ratio at or below the frozen budget and keeps
large opt-in bootstrap evidence in the handoff validation directory.

No bootstrap optimization may change the R-parity point estimate, influence
function target, cluster-summing rule, interval algebra, or documented stored
result surface.

The release has two automatic execution engines:

- A vectorized Mata implementation that is always present and handles every
  supported bootstrap workflow.
- An optional compiled multiplier kernel for explicitly seeded ATT(g,t) and
  aggregation bootstrap draws. It receives only ordered or cluster-reduced
  influence functions and the exact BMisc-compatible RNG state. For
  aggregation it preserves the independent effect streams, common
  simultaneous-band stream, and final overall-effect stream. Sample
  construction, scale estimation, confidence-band algebra, and result posting
  remain in Mata.

The compiled kernel is shipped as a platform-specific file beside
`csdid.ado`. It is selected automatically, has no runtime package dependency,
and fails closed to Mata. macOS builds are universal for Apple Silicon and
Intel. Linux and Windows binaries are built as separate release artifacts.

Default unseeded simultaneous-band draws use a row-major vectorized Mata path
that preserves the prior Stata RNG sequence exactly. Seeded plugin-vs-Mata
tests compare ATT(g,t), bootstrap output, raw draws, covariance matrices, and
the final 625-word RNG state. Aggregation tests additionally compare pointwise
and simultaneous-band results and raw aggregate draws against the Mata fallback.

## User Guidance

Use analytical standard errors for routine work unless bootstrap inference is
needed. When bootstrapping clustered designs, set a seed and report the number
of repetitions. For publication-scale bootstrap jobs, preserve the command log,
the Stata version, and the `csdid version` output with replication materials.
