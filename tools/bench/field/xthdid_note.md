# A small note on `xthdidregress` and unbalanced panels

*Pedro H. C. Sant'Anna — August 2026. Companion do-file: `xthdid_note_repro.do` (self-contained, simulated data, runs in a few seconds).*

Dear friends at StataCorp,

I have been putting together a guide comparing the DiD commands available in
Stata, and naturally I ran `xthdidregress` through the wringer alongside
everything else. Two things came out of that exercise that I wanted to share
with you directly — one of them is praise, and the other one I think you will
want to know about. Everything below is reproduced by the attached do-file,
so you do not have to take my word for anything!

## First, the praise

On balanced panels, `xthdidregress` is an exact implementation of the
Callaway–Sant'Anna estimator. We verified the `ra`, `ipw`, and `aipw` arms
against our own `csdid` across both control groups, with and without
covariates: event-study point estimates *and* clustered standard errors agree
to nine decimal places or better in every configuration — the `ra` arm to
machine epsilon. Part 1 of the do-file shows the flavor of it: one ATET cell
reproduced by a six-line paired comparison, to 1e-12. This is careful work,
and as you can imagine, I am happy the estimator is in such good hands.

## The observation

On *unbalanced* panels, the derived cohort variable does something your users
may not expect, and it is silent when it happens. The cohort is derived from
each unit's first **observed** treated period. So when a unit's actual first
treated period happens to be a missing row, the unit changes cohorts — and
every one of its cells moves with it.

The smallest possible version (Parts 2–3 of the do-file): take a balanced
panel, delete exactly one row — a cohort-4 unit's period-4 observation.
`gencohort` now classifies that unit into cohort 5, and ATET(4,5) moves from
0.7245 to 0.7406. The striking part is that the unit's remaining data were
perfectly capable of answering the cohort-4 question: run the same damaged
panel with `usercohort()` supplying the true cohort, and ATET(4,5) comes back
as 0.7245324 — *exactly* the full-panel value, to the last digit. The
information was all there; only the label was wrong.

At a survey-like missingness rate this is not an edge case (Part 4): with 15%
of rows deleted completely at random, 222 of 1,500 treated units land in the
wrong cohort, and the dynamic ATETs move by up to 0.05 — on effects of about
1.3, a shift a referee would ask about. In our checks, the default's cells
are reproduced exactly (1e-16) by the paired comparison computed on the
derived cohort, so this is the whole story — the estimator itself is doing
exactly what it should, on labels that missing data have quietly rewritten.

## Why I am writing

Here is the thing: you clearly already know about this! The `usercohort()`
documentation says, admirably candidly, that it "is useful, for instance,
when there are gaps in the estimation sample, but you know a group was
treated at the time when the gap is present in the data." That sentence is
exactly right — but it lives in the fine print of the remedy, where the
users who need it most (the ones running the default, who do not know they
have a problem) will never see it. Two small suggestions, either of which
would close the gap:

1. A runtime note when it bites — something like "*k* units' cohort was
   inferred next to a gap in the panel; see `usercohort()`" — analogous to
   the notes the command already prints about base periods. `gencohort` has
   everything needed to detect it.
2. Failing that, a sentence in the main entry and in Methods and formulas
   saying the derivation uses the first *observed* treated period, so gaps
   can reassign cohorts.

One tiny extra while I am here: `usercohort()` with never-treated units coded
as missing — the convention `did_imputation` users will reach for — exits
with an internal error (`_HETDID::set_b(): 3301`) rather than an error
message. Coding never-treated as 0 works fine. A friendly message would save
your users a confusing afternoon.

Our guide will document the behavior as part of a broader section on how DiD
commands handle missing rows (nobody documents this well, ourselves included
until recently, and the conventions genuinely differ across commands). I
wanted you to have it first, with the reproduction, and I am of course happy
to talk about any of it.

Warmly,

Pedro
