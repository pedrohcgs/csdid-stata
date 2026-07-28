# PY019: R oracle for the Python csdid r_ref parity scenarios.
#
# These five reference files used to be copied verbatim out of the Python csdid
# package (csdid/test_csdid/r_ref). They were built on another machine against
# did 2.5.0, and ref_fixweights.csv carried the 2.5.0 fix_weights = "varying"
# bug: every "varying" standard error in it is exactly 2x too large. That went
# unnoticed because the Stata comparison passed `nose` and never checked those
# SEs at all.
#
# They are now generated here, from the inputs frozen in this fixture, against
# the did the rest of the suite is pinned to. Recipes follow the upstream
# scripts: generate_reference.R, generate_fixweights_reference.R,
# generate_factor_reference.R and generate_gaps_reference.R.
suppressMessages(library(did))

IN  <- "tests/fixtures/parity/py019/inputs"
OUT <- "tests/fixtures/parity/py019/expected/r"
dir.create(file.path(OUT, "sim"), recursive = TRUE, showWarnings = FALSE)
q <- function(e) suppressWarnings(suppressMessages(e))

mpdta <- read.csv(file.path(IN, "mpdta.csv"))
simdt <- read.csv(file.path(IN, "sim_data.csv"))

# ---- ref_attgt.csv and ref_aggte.csv ---------------------------------------
attgt_rows <- list()
aggte_rows <- list()
pretest_rows <- list()
run_scenario <- function(scn, data, yname, tname, idname, gname,
                         xformla = ~1, control_group = "nevertreated",
                         est_method = "dr", base_period = "varying",
                         panel = TRUE) {
  out <- q(att_gt(yname = yname, tname = tname, idname = idname, gname = gname,
                  xformla = xformla, data = data, control_group = control_group,
                  est_method = est_method, base_period = base_period,
                  bstrap = FALSE, cband = FALSE, panel = panel))
  attgt_rows[[scn]] <<- data.frame(scenario = scn, group = out$group, t = out$t,
                                   att = out$att, se = out$se)
  # Parallel-trends Wald pre-test. R reports W and its chi-square p-value on the
  # MP object, and stores Wpval already rounded to 5 dp.
  pretest_rows[[scn]] <<- data.frame(
    scenario = scn,
    w     = if (is.null(out$W))     NA_real_ else as.numeric(out$W),
    wpval = if (is.null(out$Wpval)) NA_real_ else as.numeric(out$Wpval))
  for (tp in c("simple", "group", "dynamic", "calendar")) {
    ag <- q(aggte(out, type = tp, bstrap = FALSE))
    aggte_rows[[paste(scn, tp)]] <<- data.frame(
      scenario = scn, type = tp,
      egt     = if (is.null(ag$egt))     NA else ag$egt,
      att_egt = if (is.null(ag$att.egt)) NA else ag$att.egt,
      se_egt  = if (is.null(ag$se.egt))  NA else ag$se.egt,
      overall_att = ag$overall.att, overall_se = ag$overall.se)
  }
}
run_scenario("mpdta_nev_dr", mpdta, "lemp", "year", "countyreal", "first.treat",
             xformla = ~1, control_group = "nevertreated", est_method = "dr")
run_scenario("mpdta_nyt_dr", mpdta, "lemp", "year", "countyreal", "first.treat",
             xformla = ~1, control_group = "notyettreated", est_method = "dr")
run_scenario("mpdta_nev_reg_cov", mpdta, "lemp", "year", "countyreal", "first.treat",
             xformla = ~lpop, control_group = "nevertreated", est_method = "reg")
run_scenario("mpdta_nev_ipw", mpdta, "lemp", "year", "countyreal", "first.treat",
             xformla = ~1, control_group = "nevertreated", est_method = "ipw")
run_scenario("sim_nev_dr", simdt, "Y", "period", "id", "G",
             xformla = ~X, control_group = "nevertreated", est_method = "dr")
write.csv(do.call(rbind, attgt_rows), file.path(OUT, "ref_attgt.csv"), row.names = FALSE, na = "")
write.csv(do.call(rbind, aggte_rows), file.path(OUT, "ref_aggte.csv"), row.names = FALSE, na = "")
write.csv(do.call(rbind, pretest_rows), file.path(OUT, "ref_pretest.csv"), row.names = FALSE, na = "")

# ---- ref_fixweights.csv ----------------------------------------------------
tvw <- read.csv(file.path(IN, "mpdta_tvw.csv"))
fw_rows <- list()
for (fw in list(NULL, "base_period", "first_period", "varying")) {
  tag <- if (is.null(fw)) "none" else fw
  out <- q(att_gt(yname = "lemp", tname = "year", idname = "countyreal",
                  gname = "first.treat", xformla = ~1, data = tvw,
                  control_group = "nevertreated", est_method = "reg",
                  weightsname = "wt", fix_weights = fw,
                  bstrap = FALSE, cband = FALSE))
  fw_rows[[tag]] <- data.frame(fix_weights = tag, group = out$group, t = out$t,
                               att = out$att, se = out$se)
}
write.csv(do.call(rbind, fw_rows), file.path(OUT, "ref_fixweights.csv"), row.names = FALSE, na = "")

# ---- sim/ref_factor.csv ----------------------------------------------------
fc <- read.csv(file.path(IN, "factor_cov.csv"))
fc$cat <- factor(fc$cat)
out <- q(att_gt(yname = "Y", tname = "period", idname = "id", gname = "G",
                xformla = ~cat, data = fc, control_group = "nevertreated",
                est_method = "reg", bstrap = FALSE))
write.csv(data.frame(group = out$group, t = out$t, att = out$att, se = out$se),
          file.path(OUT, "sim/ref_factor.csv"), row.names = FALSE, na = "")

# ---- sim/ref_gaps.csv ------------------------------------------------------
ex <- read.csv(file.path(IN, "mpdta_extra.csv"))
common <- list(yname = "lemp", tname = "year", idname = "countyreal",
               gname = "first.treat", data = ex, bstrap = FALSE, cband = FALSE)
run <- function(scn, ...) {
  o <- q(do.call(att_gt, c(common, list(...))))
  data.frame(scenario = scn, group = o$group, t = o$t, att = o$att, se = o$se)
}
write.csv(rbind(
  run("rc",            panel = FALSE, control_group = "nevertreated", est_method = "reg"),
  run("universal",     base_period = "universal", control_group = "nevertreated", est_method = "reg"),
  run("anticipation1", anticipation = 1, control_group = "nevertreated", est_method = "reg"),
  run("weighted",      weightsname = "wt", control_group = "nevertreated", est_method = "reg"),
  run("clustered",     clustervars = "clust", control_group = "nevertreated", est_method = "reg")
), file.path(OUT, "sim/ref_gaps.csv"), row.names = FALSE, na = "")

cat(sprintf("PY019 oracle: 6 reference files regenerated (did %s)\n",
            as.character(packageVersion("did"))))
