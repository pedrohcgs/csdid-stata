# RT015: R oracle for the inference scenarios the Stata test exercises.
# The inherited test ran csdid across panel/RCS x methods x clustering but never
# compared a standard error against R.
suppressMessages(library(did))
q <- function(e) suppressWarnings(suppressMessages(e))
IN  <- "tests/fixtures/parity/rt015/inputs"
OUT <- "tests/fixtures/parity/rt015/expected/r"
panel <- read.csv(file.path(IN, "panel.csv"))
rcs   <- read.csv(file.path(IN, "repeated-cross-section.csv"))
# unbalanced.csv is panel.csv with every 37th observation (0-based index 2)
# deleted -- 70 of 2592 rows, leaving all 648 units present but 70 of them
# observed in only 3 of the 4 periods. Upstream deletes a single row
# (data[-3, ]); one deletion barely exercises the unbalanced path.
unbal <- read.csv(file.path(IN, "unbalanced.csv"))
stopifnot(nrow(unbal) == 2522L,
          length(unique(unbal$id)) == length(unique(panel$id)))

rows <- list()
add <- function(tag, r) rows[[length(rows)+1]] <<-
  data.frame(scenario=tag, group=r$group, time=r$t, att=r$att, se=r$se)

for (m in c("dr","reg","ipw")) {
  add(paste0("panel_",m), q(att_gt(yname="y", tname="period", idname="id", gname="g",
      xformla=~x, data=panel, est_method=m, bstrap=FALSE, cband=FALSE)))
  # clustered ANALYTICAL: did builds the cluster-robust variance only when
  # bstrap = FALSE, which is the configuration the Stata test uses.
  add(paste0("panel_cluster_",m), q(att_gt(yname="y", tname="period", idname="id", gname="g",
      xformla=~x, data=panel, est_method=m, clustervars="cluster",
      bstrap=FALSE, cband=FALSE)))
  add(paste0("rcs_",m), q(att_gt(yname="y", tname="period", gname="g",
      xformla=~x, data=rcs, est_method=m, panel=FALSE, bstrap=FALSE, cband=FALSE)))
  add(paste0("rcs_cluster_",m), q(att_gt(yname="y", tname="period", gname="g",
      xformla=~x, data=rcs, est_method=m, panel=FALSE, clustervars="cluster",
      bstrap=FALSE, cband=FALSE)))
  # Unbalanced panel, with and without clustering. Upstream's two unbalanced
  # inference tests assert agreement with a historical did 2.1.2 install, which
  # is out of scope here -- this repo tracks current did only. Pinning the same
  # scenarios against the current package is the stronger claim: it fixes the
  # numbers rather than checking two versions agree.
  add(paste0("unbal_",m), q(att_gt(yname="y", tname="period", idname="id", gname="g",
      xformla=~x, data=unbal, est_method=m, panel=TRUE, allow_unbalanced_panel=TRUE,
      bstrap=FALSE, cband=FALSE)))
  add(paste0("unbal_cluster_",m), q(att_gt(yname="y", tname="period", idname="id", gname="g",
      xformla=~x, data=unbal, est_method=m, panel=TRUE, allow_unbalanced_panel=TRUE,
      clustervars="cluster", bstrap=FALSE, cband=FALSE)))
}
out <- do.call(rbind, rows)
write.csv(out, file.path(OUT, "attgt.csv"), row.names=FALSE, na="")
cat(sprintf("RT015 oracle: %d rows across %d scenarios\n", nrow(out), length(unique(out$scenario))))
