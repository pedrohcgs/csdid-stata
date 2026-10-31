#!/usr/bin/env Rscript
# RT080: observation IDs and settled-sample/name invariance after upstream fixes.
args <- commandArgs(FALSE)
script_path <- sub("^--file=", "", grep("^--file=", args, value = TRUE)[1L])
source(file.path(dirname(script_path), "../oracle-check.R"))
root <- normalizePath(file.path(dirname(script_path), "../../../.."))
out <- file.path(root, "tests/fixtures/parity/rt080")
for (sub in c("inputs", "expected/r", "metadata")) dir.create(file.path(out, sub), recursive = TRUE, showWarnings = FALSE)
sha <- function(p) digest::digest(file = p, algo = "sha256")
d <- expand.grid(id = 1:90, time = 1:5)
d <- d[order(d$id, d$time), ]; rownames(d) <- NULL
d$g <- c(0, 3, 4)[1L + (d$id - 1L) %/% 30L]
d$obsid <- seq_len(nrow(d)); d$cl <- 1L + d$id %% 15L
d$x <- ((d$id * 7 + d$time * 3) %% 19) / 16
d$w <- 1 + (d$id %% 5) / 4
d$y <- d$id / 64 + 0.3 * d$time + d$x / 2 +
  (d$g > 0 & d$time >= d$g) * (1 + (d$time - d$g) / 5) + sin(d$id * 1.7 + d$time) / 4
write.csv(d, file.path(out, "inputs/panel.csv"), row.names = FALSE)
fits <- infs <- list()
for (route in c("panel", "rc", "unbalanced")) for (method in c("reg", "ipw", "dr")) {
  z <- if (route == "unbalanced") d[!(d$id %% 13 == 0 & d$time == 2), ] else d
  a <- suppressWarnings(suppressMessages(did::att_gt(yname = "y", tname = "time", gname = "g",
    idname = if (route == "rc") "obsid" else "id", panel = route != "rc",
    allow_unbalanced_panel = route == "unbalanced", data = z, xformla = ~x,
    weightsname = "w", est_method = method, control_group = "notyettreated",
    base_period = "universal", bstrap = FALSE, cband = FALSE)))
  key <- paste(route, method, sep = "_")
  fits[[key]] <- data.frame(route, method, group = a$group, time = a$t, att = a$att, se = a$se)
  ids <- sort(unique(z[[if (route == "rc") "obsid" else "id"]]))
  inf <- as.matrix(a$inffunc)
  stopifnot(length(ids) == nrow(inf))
  reference_ids <- as.numeric(rownames(inf))
  stopifnot(length(reference_ids) == length(ids), setequal(reference_ids, ids))
  inf <- inf[match(ids, reference_ids), , drop = FALSE]
  infs[[key]] <- data.frame(route, method, unit = rep(seq_along(ids), ncol(inf)),
    group = rep(a$group, each = length(ids)), time = rep(a$t, each = length(ids)), value = as.vector(inf))
}
write.csv(do.call(rbind, fits), file.path(out, "expected/r/attgt.csv"), row.names = FALSE, na = "")
write.csv(do.call(rbind, infs), file.path(out, "expected/r/inffunc.csv"), row.names = FALSE, na = "")
errors <- lapply(c("across", "within"), function(shape) {
  z <- if (shape == "within") rbind(d, d[1L, ]) else d
  id <- if (shape == "within") "obsid" else "id"
  msg <- tryCatch({suppressWarnings(did::att_gt(yname="y", tname="time", gname="g",
    idname=id, panel=FALSE, data=z, bstrap=FALSE)); ""}, error = conditionMessage)
  stopifnot(grepl("must be unique when panel = FALSE", msg, fixed = TRUE))
  data.frame(shape, message = msg)
})
write.csv(do.call(rbind, errors), file.path(out, "expected/r/refusals.csv"), row.names = FALSE)
paths <- c("expected/r/attgt.csv", "expected/r/inffunc.csv", "expected/r/refusals.csv")
manifest <- list(matrix_id="RT080", fixture_family="r-upstream-settling-and-rc-identity",
  normative_source="did pre_process_did2.R observation-ID validation; att_gt panel/RC/unbalanced routes",
  source_commit="4bed75ef731cba2e6d4a28205111b311f892fab1", decision_refs=list(), tolerance_ids=c("EXACT","TOL002"),
  inputs=list(list(path="inputs/panel.csv", sha256=sha(file.path(out,"inputs/panel.csv")))),
  expected_outputs=lapply(paths, function(p) list(path=p, schema="keyed-reference", sha256=sha(file.path(out,p)))),
  generators=list(list(runtime="R", command="Rscript tools/parity/generators/rt080/generate.R", path="tools/parity/generators/rt080/generate.R", sha256=sha(script_path))),
  runtimes=list(list(name="R",version=as.character(getRversion()),package_versions=list(did=as.character(packageVersion("did")),DRDID=as.character(packageVersion("DRDID"))))),
  rng=NULL, comparison_plan=list(list(actual="Every ATT/SE and unit-level IF, both execution routes; RC refusals", expected=paths,tolerance_id="TOL002")), approved_divergence=NULL)
jsonlite::write_json(manifest,file.path(out,"metadata/manifest.json"),pretty=TRUE,auto_unbox=TRUE,null="null")
cat("RT080: nine full reference fits and two ID refusals\n")
