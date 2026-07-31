---
title: References
---

# References

## The estimator

The method `csdid` implements, and the paper to cite for it:

> Callaway, Brantly, and Pedro H. C. Sant'Anna. 2021. "Difference-in-Differences
> with Multiple Time Periods." *Journal of Econometrics* 225 (2): 200–230.
> [doi:10.1016/j.jeconom.2020.12.001](https://doi.org/10.1016/j.jeconom.2020.12.001)

The two-period doubly robust estimator applied to each (g,t) cell, used by
`method(dr)`, the default:

> Sant'Anna, Pedro H. C., and Jun Zhao. 2020. "Doubly Robust
> Difference-in-Differences Estimators." *Journal of Econometrics* 219 (1):
> 101–122.
> [doi:10.1016/j.jeconom.2020.06.003](https://doi.org/10.1016/j.jeconom.2020.06.003)

The semiparametric foundation for conditioning on covariates:

> Abadie, Alberto. 2005. "Semiparametric Difference-in-Differences Estimators."
> *Review of Economic Studies* 72 (1): 1–19.
> [doi:10.1111/0034-6527.00321](https://doi.org/10.1111/0034-6527.00321)

The efficiency theory for these designs, which shows that the tightest
estimator depends on the covariance structure of the outcomes:

> Chen, Xiaohong, Pedro H. C. Sant'Anna, and Haitian Xie. 2025. "Efficient
> Difference-in-Differences and Event Study Estimators."
> [arXiv:2506.17729](https://arxiv.org/abs/2506.17729)

None of the estimators `csdid` offers attains that bound outside special cases.
Thus `method(dr)` is a sensible default, and it is not an efficient estimator in
general.

## Reviews

These two reviews cover the DiD literature more broadly than any single
estimator does, and either is a reasonable place to start. The first gives the
organizing framework for DiD designs and the estimators built on them, and
every example on this site uses its replication data. The second surveys the
recent econometrics literature and the estimators it has produced.

> Baker, Andrew, Brantly Callaway, Scott Cunningham, Andrew Goodman-Bacon, and
> Pedro H. C. Sant'Anna. 2026. "Difference-in-Differences Designs: A
> Practitioner's Guide." *Journal of Economic Literature* 64 (2): 498–557.
> [doi:10.1257/jel.20251650](https://doi.org/10.1257/jel.20251650)

> Roth, Jonathan, Pedro H. C. Sant'Anna, Alyssa Bilinski, and John Poe. 2023.
> "What's Trending in Difference-in-Differences? A Synthesis of the Recent
> Econometrics Literature." *Journal of Econometrics* 235 (2): 2218–2244.
> [doi:10.1016/j.jeconom.2023.03.008](https://doi.org/10.1016/j.jeconom.2023.03.008)

## Two-way fixed effects under staggered timing

These papers show why a TWFE coefficient is not the average treatment effect on
the treated when timing is staggered and effects are heterogeneous, and they
differ in how they decompose the resulting bias into comparisons that are and
are not valid. We work through the argument in
[Why not two-way fixed effects](articles/why-not-twfe.html).

> Goodman-Bacon, Andrew. 2021. "Difference-in-Differences with Variation in
> Treatment Timing." *Journal of Econometrics* 225 (2): 254–277.
> [doi:10.1016/j.jeconom.2021.03.014](https://doi.org/10.1016/j.jeconom.2021.03.014)

> de Chaisemartin, Clément, and Xavier D'Haultfœuille. 2020. "Two-Way Fixed
> Effects Estimators with Heterogeneous Treatment Effects." *American Economic
> Review* 110 (9): 2964–2996.
> [doi:10.1257/aer.20181169](https://doi.org/10.1257/aer.20181169)

> Sun, Liyang, and Sarah Abraham. 2021. "Estimating Dynamic Treatment Effects in
> Event Studies with Heterogeneous Treatment Effects." *Journal of Econometrics*
> 225 (2): 175–199.
> [doi:10.1016/j.jeconom.2020.09.006](https://doi.org/10.1016/j.jeconom.2020.09.006)

## Citing csdid

<div class="tip" markdown="1">
We ask that you cite *both* the method and the software: for the method,
Callaway and Sant'Anna (2021) above, plus Sant'Anna and Zhao (2020) if you use
`method(dr)`; for the software, cite the version you ran, which `csdid version`
reports for you:
</div>

```
@misc{csdidStata,
  title  = {csdid: Difference-in-Differences with Multiple Time Periods in Stata},
  note   = {Stata module, version 2.0.0},
  year   = {2026},
  url    = {https://github.com/pedrohcgs/csdid-stata}
}
```
