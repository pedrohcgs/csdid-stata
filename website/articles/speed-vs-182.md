---
title: "Speed against Version 1.82"
---

# Speed against Version 1.82

Version 1.82 is the `csdid` that SSC distributes today. The
[upgrading guide](upgrading-from-182.html) covers what changed in the
estimates; this page reports how long each version takes to produce them.
Our protocol is the median of 7 timed trials with one discarded warmup,
with each version invoked in its own syntax in its own fresh Stata
process, on identical data with one covariate. To keep the comparison
about speed alone, we pin 2.0.0 to Version 1.82's defaults in every cell
(never-treated comparison group, varying base
period, and pair balancing on unbalanced panels), so that both versions
compute the same numbers and differ only in how long they take. The
workload is a doubly robust event study with clustered standard errors
throughout (the same specification in every table below). Timings depend
on the machine they were taken on, so the ratios travel better than the
seconds do.

<div class="note" markdown="1">
Because 2.0.0 is pinned to the old defaults here, the times in the
2.0.0 column are not comparable to the shipped-defaults times in the
[main speed tables](csdid-against-the-field.html#speed), which run the
same engine under different estimand settings.
</div>

## By sample size

| n (T=10, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 1.81s | 0.05s | 35x |
| 5,000 | 50,000 | 5.34s | 0.16s | 33x |
| 20,000 | 200,000 | 23.7s | 0.61s | 39x |
| 50,000 | 500,000 | 74.8s | 1.23s | **61x** |
| 100,000 | 1,000,000 | not run | 2.34s | — |

The gain grows with the sample size, and then the comparison stops: at a
million rows, Version 1.82 projected past two and a half minutes per run,
so we did not run it and the last row reports 2.0.0 alone, which does the
same cell in 2.3 seconds.

## By number of periods

The number of periods is where the two versions differ most. Version
1.82's cost grows faster than linearly in the number of ATT(g,t) cells,
while 2.0.0's grows about linearly in them:

| T (n=5,000, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 5 | 25,000 | 1.44s | 0.09s | 16x |
| 10 | 50,000 | 5.35s | 0.17s | 32x |
| 20 | 100,000 | 24.4s | 0.31s | 80x |
| 40 | 200,000 | 129.4s | 0.62s | **208x** |

At forty periods (a monthly panel over three and a half years), Version
1.82 takes over two minutes and 2.0.0 takes six tenths of a second.

## By number of cohorts

| G (n=5,000, T=20) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 3 | 100,000 | 19.1s | 0.30s | 63x |
| 6 | 100,000 | 37.7s | 0.39s | 96x |
| 12 | 100,000 | 82.1s | 0.64s | **129x** |

Only the number of adoption dates changes here. The data size is the same
in every row, so the growth down the 1.82 column is the cost of the extra
ATT(g,t) cells that more cohorts imply.

## By sampling scheme

| scheme (n=10,000, T=10, G=4) | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: |
| balanced panel | 10.7s | 0.31s | 34x |
| unbalanced panel (pair balancing, both) | 8.53s | 0.38s | 22x |
| repeated cross sections | 7.77s | 1.47s | 5.3x |

Repeated cross sections were Version 1.82's fastest path, so the gain
there is the smallest on this page: 5x at one end of the comparison and
208x at the other (the two extremes across all four tables).

## Where the workload gains were certified

The per-workload comparison at fixed size (analytical, bootstrap,
weighted, clustered, and event-study variants, 5x to 28x) ships in the
package README with per-trial records, and it was produced by a
seven-trial A/B harness run against an installed copy of Version 1.82 at
its released commit. This page extends that comparison across sizes and
designs, and it does not replace those numbers or restate them. Neither
set of timings says anything about which version is more accurate, since
both compute the same estimates here.

[Back to the guides](../guides.html)
