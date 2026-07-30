---
title: "Speed against Version 1.82"
---

# Speed against Version 1.82

Version 1.82 is the `csdid` that SSC distributes today. The
[upgrading guide](upgrading-from-182.html) covers what changed in the
results; this page measures what changed in the waiting. Protocol: the
median of 7 timed trials with one discarded warmup, each version invoked
in its own syntax in its own fresh Stata process, on identical data with
one covariate. To keep the comparison about speed rather than about
estimands, 2.0.0 is pinned to Version 1.82's defaults in every cell —
never-treated comparison group, varying base period, and pair balancing
on unbalanced panels — so both versions compute the same numbers and
differ only in how long they take. The workload is a doubly robust event
study with clustered standard errors throughout.

<div class="note" markdown="1">
Because 2.0.0 is pinned to the old defaults here, the times in the
2.0.0 column are not comparable to the shipped-defaults times in the
[main speed tables](csdid-against-the-field.html#speed) — same engine,
different estimand settings.
</div>

## By sample size

| n (T=10, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 1.81s | 0.05s | 35x |
| 5,000 | 50,000 | 5.34s | 0.16s | 33x |
| 20,000 | 200,000 | 23.7s | 0.61s | 39x |
| 50,000 | 500,000 | 74.8s | 1.23s | **61x** |
| 100,000 | 1,000,000 | not run | 2.34s | — |

The gain grows with size, and then the comparison ends: at a million rows
Version 1.82 projected past two and a half minutes per run and was not
run — the honest way to say that the design outgrew it. 2.0.0 does the
same cell in 2.3 seconds.

## By number of periods

This is where the two engines separate most. Version 1.82's cost explodes
in the number of ATT(g,t) cells; 2.0.0's grows linearly:

| T (n=5,000, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 5 | 25,000 | 1.44s | 0.09s | 16x |
| 10 | 50,000 | 5.35s | 0.17s | 32x |
| 20 | 100,000 | 24.4s | 0.31s | 80x |
| 40 | 200,000 | 129.4s | 0.62s | **208x** |

At forty periods — a monthly panel over three and a half years — Version
1.82 takes over two minutes; 2.0.0 takes six tenths of a second.

## By number of cohorts

| G (n=5,000, T=20) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 3 | 100,000 | 19.1s | 0.30s | 63x |
| 6 | 100,000 | 37.7s | 0.39s | 96x |
| 12 | 100,000 | 82.1s | 0.64s | **129x** |

Same data size in every row; only the number of adoption dates changes.
More cohorts means more cells, and cells are what Version 1.82 pays for.

## By sampling scheme

| scheme (n=10,000, T=10, G=4) | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: |
| balanced panel | 10.7s | 0.31s | 34x |
| unbalanced panel (pair balancing, both) | 8.53s | 0.38s | 22x |
| repeated cross sections | 7.77s | 1.47s | 5.3x |

Repeated cross sections were Version 1.82's least slow path, and the gain
there is the smallest on this page — 5x is the floor of the whole
comparison, and the ceiling is 208x.

## Where the workload gains were certified

The per-workload comparison at fixed size — analytical, bootstrap,
weighted, clustered, and event-study variants, 5x to 28x — ships in the
package README with per-trial records, produced by a seven-trial A/B
harness against an installed copy of Version 1.82 at its released commit.
This page extends that certification across sizes and designs; nothing on
it replaces those numbers.

[Back to the guides](../guides.html)
