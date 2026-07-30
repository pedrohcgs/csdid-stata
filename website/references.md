---
title: References
---

# References

## The estimator

The method `csdid` implements, and the one to cite when you use it:

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

The efficiency theory for these designs — which estimator is tightest depends
on the covariance structure of the outcomes, and none of the packaged
estimators attains the bound in general:

> Chen, Xiaohong, Pedro H. C. Sant'Anna, and Haitian Xie. 2025. "Efficient
> Difference-in-Differences and Event Study Estimators."
> [arXiv:2506.17729](https://arxiv.org/abs/2506.17729)

## Reviews

Start here if you want the landscape rather than one estimator. The first
provides the organizing framework for DiD designs and their estimators; every
example on this site uses its replication data.

> Baker, Andrew, Brantly Callaway, Scott Cunningham, Andrew Goodman-Bacon, and
> Pedro H. C. Sant'Anna. 2026. "Difference-in-Differences Designs: A
> Practitioner's Guide." *Journal of Economic Literature* 64 (2): 498–557.
> [doi:10.1257/jel.20251650](https://doi.org/10.1257/jel.20251650)

> Roth, Jonathan, Pedro H. C. Sant'Anna, Alyssa Bilinski, and John Poe. 2023.
> "What's Trending in Difference-in-Differences? A Synthesis of the Recent
> Econometrics Literature." *Journal of Econometrics* 235 (2): 2218–2244.
> [doi:10.1016/j.jeconom.2023.03.008](https://doi.org/10.1016/j.jeconom.2023.03.008)

## Two-way fixed effects under staggered timing

Why a TWFE coefficient is not the average treatment effect on the treated when
timing is staggered and effects are heterogeneous. See
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
Cite **both** the method and the software. For the method, Callaway and
Sant'Anna (2021) above, plus Sant'Anna and Zhao (2020) if you use `method(dr)`.
For the software, cite the version you ran — report it with `csdid version`:
</div>

```
@misc{csdidStata,
  title  = {csdid: Difference-in-Differences with Multiple Time Periods in Stata},
  note   = {Stata module, version 2.0.0},
  year   = {2026},
  url    = {https://github.com/pedrohcgs/csdid-stata}
}
```
