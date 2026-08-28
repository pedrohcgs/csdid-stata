*! csdid_p 2.0.0 28aug2026
*
* predict has no meaning after csdid: e(b) holds ATT(g,t)
* treatment effects, not coefficients on regressors, so there is no linear
* index to score and no covariate profile to form a fitted value from.
*
* Before this program existed, csdid set no e(predict), so Stata's default
* predict fell through to `matrix score' and aborted with
*
*     variable g2004___2004_2003 not found
*     r(111);
*
* which names an internal coefficient and reads to the user like a missing
* variable in their data rather than an unsupported postestimation command --
* while csdid.sthlp already promised a designed refusal. didregress ships
* didregress_p for the same reason; csdid.ado now sets e(predict) = "csdid_p"
* so predict lands here and refuses by name.
*
* The refusal is unconditional and deliberately parses nothing: any syntax
* error in the user's predict call must not pre-empt the message that explains
* why no predict call can ever work.
program define csdid_p
    version 14
    if `"`e(cmd)'"' != "csdid" {
        error 301
    }
    display as error "predict is not supported after csdid"
    * the command examples are quoted with -char(96)-/-char(39)- kept OUT of
    * the string: a backtick pair inside a double-quoted display is macro
    * expansion, and both examples expanded to nothing (in-house review).
    display as error `"{p 4 4 2}e(b) holds ATT(g,t) treatment effects, not coefficients on regressors, so there is no linear index to predict from; e(sample) does mark the estimation sample, so {cmd:summarize ... if e(sample)} and {cmd:estat summarize} describe exactly the observations the estimation used.{p_end}"'
    display as error "{p 4 4 2}Use test, lincom or nlcom on the ATT(g,t) coefficient names, csdid_estat or csdid_stats for aggregations, or csdid_plot to export plot data; see {help csdid_postestimation}.{p_end}"
    exit 198
end
