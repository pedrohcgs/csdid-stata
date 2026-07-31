#!/usr/bin/env Rscript

# F054 -- bal(pair): balance each 2x2 on its own.
#
# Version 1.82 kept, for each comparison, the units observed in BOTH of that
# comparison's periods, and did it without saying so. bal(pair) is that mode.
#
# The oracle here deliberately does NOT call did::att_gt. Under pair balancing
# every cell has its own unit set, and an oracle earns its name by deriving the
# answer a second way rather than asking the same library the same question.
# Each cell is therefore the plain two-period difference-in-differences it is
# defined to be, with the analytical standard error built from the influence
# function directly:
#
#   ATT(g,t) = mean(dy | g) - mean(dy | controls)          over units in both periods
#   IF_i     = (n/|T|)(dy_i - mean(dy_T))   for treated i
#            = -(n/|C|)(dy_i - mean(dy_C))  for control i
#            = 0                            for every other unit in the sample
#   SE       = sqrt(sum IF^2) / n
#
# That n is the SAMPLE unit count, not the cell's -- which is the one thing
# about pair balancing that cannot be settled by reading the kernel, so it is
# settled here instead.

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f054/generate.R"
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f054")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

# A panel that is unbalanced in a way that bites: the holes are spread across
# periods and cohorts, so different cells lose different units. If every hole
# sat in one period, pair and full would coincide on most cells.
cohorts <- c(3, 4, 0)
units <- do.call(rbind, lapply(seq_along(cohorts), function(j) {
  data.frame(id = (j - 1) * 12 + 1:12, g = cohorts[j])
}))
units$alpha <- 0.4 * ((units$id * 3) %% 5) - 0.8

d <- do.call(rbind, lapply(1:5, function(t) {
  treat <- ifelse(units$g > 0 & t >= units$g, 0.55 + 0.18 * (t - units$g), 0)
  data.frame(id = units$id, time = t, g = units$g,
             y = units$alpha + 0.3 * t + treat + 0.21 * sin(1.9 * units$id + 2.6 * t))
}))
# punch holes deterministically: every 7th unit-period, spread over the grid
d <- d[!((d$id * 3 + d$time * 5) %% 7 == 0), ]
d <- d[order(d$id, d$time), ]
rownames(d) <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

tlist <- sort(unique(d$time))
glist <- sort(unique(d$g[d$g > 0]))
prev_time <- function(x) { lt <- tlist[tlist < x]; if (!length(lt)) NA else max(lt) }
n_all <- length(unique(d$id))

# mode "pair": units observed in both of THIS comparison's periods.
# mode "full": units observed in EVERY period, one fixed set for all cells.
complete_ids <- names(which(table(d$id) == length(tlist)))
cell <- function(g, t, notyet, mode) {
  pret <- if (t >= g) prev_time(g) else prev_time(t)
  if (is.na(pret)) return(NULL)
  ctime <- max(t, pret)
  ids <- if (mode == "pair") intersect(d$id[d$time == t], d$id[d$time == pret])
         else as.numeric(complete_ids)
  sub <- d[d$id %in% ids & d$time %in% c(pret, t), ]
  w <- reshape(sub[, c("id", "time", "y", "g")], idvar = c("id", "g"),
               timevar = "time", direction = "wide")
  dy <- w[[paste0("y.", t)]] - w[[paste0("y.", pret)]]
  gi <- w$g
  treat <- gi == g
  ctrl <- if (notyet) (gi != g) & ((gi == 0) | (gi > ctime)) else (gi == 0)
  if (!any(treat) || !any(ctrl) || anyNA(dy[treat]) || anyNA(dy[ctrl])) return(NULL)
  att <- mean(dy[treat]) - mean(dy[ctrl])
  inf <- rep(0, nrow(w))
  inf[treat] <- (n_all / sum(treat)) * (dy[treat] - mean(dy[treat]))
  inf[ctrl] <- -(n_all / sum(ctrl)) * (dy[ctrl] - mean(dy[ctrl]))
  data.frame(group = g, time = t, pret = pret,
             n_treat = sum(treat), n_control = sum(ctrl),
             att = att, se = sqrt(sum(inf^2)) / n_all)
}

rows <- list()
for (g in glist) for (t in tlist) {
  r <- cell(g, t, TRUE, "pair")
  if (!is.null(r)) rows[[length(rows) + 1]] <- r
}
out <- do.call(rbind, rows)
stopifnot(nrow(out) > 0)

# The fixture must discriminate: if pair coincided with keeping every unit, the
# test built on it would pass on a build where bal(pair) did nothing.
full <- do.call(rbind, Filter(Negate(is.null),
  lapply(seq_len(nrow(out)), function(i) cell(out$group[i], out$time[i], TRUE, "full"))))
stopifnot(nrow(full) == nrow(out))
gap <- max(abs(out$att - full$att))
if (!(gap > 1e-6)) {
  stop(sprintf("F054 fixture is not discriminating: pair and full agree to %g", gap))
}
n_shrunk <- sum(out$n_treat + out$n_control != full$n_treat + full$n_control)
if (n_shrunk == 0) stop("F054 fixture is not discriminating: no cell has a different unit set")

out$att <- sprintf("%.17g", out$att)
out$se <- sprintf("%.17g", out$se)
write.csv(out, file.path(fixture, "expected/r/attgt-pair.csv"), row.names = FALSE)

manifest <- list(
  matrix_id = "F054",
  fixture_family = "pair-balanced-2x2",
  normative_source = "Stata csdid Version 1.82 per-comparison balancing; oracle derived independently, not from did::att_gt",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D008"),
  tolerance_ids = c("TOL001", "TOL002"),
  inputs = list(list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d))),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f054/generate.R", path = "tools/parity/generators/f054/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."))),
  rng = NULL,
  expected_outputs = list(list(path = "expected/r/attgt-pair.csv", schema = "attgt-pair")),
  comparison_plan = list(list(actual = "Stata bal(pair) ATT(g,t)", expected = "expected/r/attgt-pair.csv", tolerance_id = "TOL001", key_columns = c("group", "time"))),
  approved_divergence = NULL,
  scope_note = "Per-cell unit sets: each 2x2 keeps only units observed in both of its periods. Oracle is an independent two-period DiD with the influence function built by hand, so the n_units/cell scaling is verified rather than assumed."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
cat(sprintf("F054: %d rows, %d cells, %d cells lose units under pair, max |pair-unrestricted| = %.4g\n",
            nrow(d), nrow(out), n_shrunk, gap))
