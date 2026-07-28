# RT030: R oracle for the point-estimate scenarios the Stata test exercises.
#
# The inherited test previously asserted only that at least one ATT(g,t) cell
# was within 0.75 of 1 -- a sanity check a badly wrong implementation would
# pass. This produces R's actual ATT and SE for every scenario the Stata test
# runs, so the comparison can be tight.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN  <- "tests/fixtures/parity/rt030/inputs"
OUT <- "tests/fixtures/parity/rt030/expected/r"

panel <- read.csv(file.path(IN, "panel.csv"))
twop  <- read.csv(file.path(IN, "two-period.csv"))
rcs   <- read.csv(file.path(IN, "repeated-cross-section.csv"))
unb   <- read.csv(file.path(IN, "unbalanced.csv"))

grab <- function(tag, r) data.frame(scenario = tag, group = r$group, time = r$t,
                                    att = r$att, se = r$se)
rows <- list()
add  <- function(tag, r) rows[[length(rows) + 1]] <<- grab(tag, r)

for (m in c("dr", "reg", "ipw")) {
  add(paste0("panel_x_", m), q(att_gt(yname="y", tname="period", idname="id",
      gname="g", xformla=~x, data=panel, est_method=m, bstrap=FALSE, cband=FALSE)))
  add(paste0("panel_nox_", m), q(att_gt(yname="y", tname="period", idname="id",
      gname="g", data=panel, est_method=m, bstrap=FALSE, cband=FALSE)))
  add(paste0("rcs_x_", m), q(att_gt(yname="y", tname="period", gname="g",
      xformla=~x, data=rcs, est_method=m, panel=FALSE, bstrap=FALSE, cband=FALSE)))
}
add("twoperiod_reg", q(att_gt(yname="y", tname="period", idname="id", gname="g",
    xformla=~x, data=twop, est_method="reg", bstrap=FALSE, cband=FALSE)))
add("unbalanced_dr", q(att_gt(yname="y", tname="period", idname="id", gname="g",
    xformla=~x, data=unb, est_method="dr", allow_unbalanced_panel=TRUE,
    bstrap=FALSE, cband=FALSE)))
add("panel_notyet_rcs_dr", q(att_gt(yname="y", tname="period", gname="g",
    xformla=~x, data=panel, est_method="dr", panel=FALSE,
    control_group="notyettreated", bstrap=FALSE, cband=FALSE)))

# treated-only sample with not-yet-treated controls (Stata test line 85-88)
add("panel_treatedonly_notyet_dr", q(att_gt(yname="y", tname="period", gname="g",
    xformla=~x, data=panel[panel$g > 0, ], est_method="dr", panel=FALSE,
    control_group="notyettreated", bstrap=FALSE, cband=FALSE)))

attgt <- do.call(rbind, rows)
write.csv(attgt, file.path(OUT, "attgt.csv"), row.names = FALSE, na = "")

# aggregations on the two-period design, which the Stata test also checks
base <- q(att_gt(yname="y", tname="period", idname="id", gname="g", xformla=~x,
    data=twop, est_method="reg", bstrap=FALSE, cband=FALSE))
agg <- do.call(rbind, lapply(c("simple","group","dynamic","calendar"), function(ty) {
  a <- q(aggte(base, type = ty, na.rm = TRUE))
  data.frame(type = ty, overall_att = a$overall.att, overall_se = a$overall.se)
}))
write.csv(agg, file.path(OUT, "aggte.csv"), row.names = FALSE, na = "")
cat(sprintf("RT030 oracle: %d attgt rows across %d scenarios, %d aggregations\n",
            nrow(attgt), length(unique(attgt$scenario)), nrow(agg)))
