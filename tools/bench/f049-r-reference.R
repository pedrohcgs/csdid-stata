#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args) >= 1) args[[1]] else getwd()
root <- normalizePath(root, mustWork = TRUE)
source(file.path(root, "tools/parity/generators/oracle-check.R"))

fixture <- file.path(root, "tests/fixtures/parity/f049")
outdir <- file.path(root, "build/f049")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

read_input <- function(name) {
  read.csv(file.path(fixture, "inputs", name))
}

elapsed <- function(name, expr, reps = 1L, best_of = FALSE) {
  expr_sub <- substitute(expr)
  gc()
  if (best_of) {
    timing <- Inf
    for (i in seq_len(reps)) {
      gc()
      this_timing <- system.time(eval(expr_sub, parent.frame()))[["elapsed"]]
      if (this_timing < timing) timing <- this_timing
    }
  }
  else {
    timing <- system.time({
      for (i in seq_len(reps)) eval(expr_sub, parent.frame())
    })[["elapsed"]] / reps
  }
  data.frame(benchmark = name, r_seconds = as.numeric(timing))
}

small <- read_input("small-smoke.csv")
medium <- read_input("medium-panel.csv")
unbalanced <- read_input("medium-unbalanced.csv")
aggregation <- read_input("aggregation-medium.csv")

rows <- list()

rows[[length(rows) + 1]] <- elapsed("small_smoke", {
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = small,
    est_method = "reg", xformla = ~1, bstrap = FALSE, cband = FALSE
  )
})

rows[[length(rows) + 1]] <- elapsed("medium_panel", {
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "reg", xformla = ~1, bstrap = FALSE, cband = FALSE
  )
})

rows[[length(rows) + 1]] <- data.frame(
  benchmark = "medium_panel_fast_lean",
  r_seconds = rows[[length(rows)]]$r_seconds
)
rows[[length(rows) + 1]] <- data.frame(
  benchmark = "medium_panel_performance_auto",
  r_seconds = rows[[length(rows) - 1]]$r_seconds
)

rows[[length(rows) + 1]] <- elapsed("medium_panel_covariate_dr", {
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "dr", xformla = ~x1 + x2, bstrap = FALSE, cband = FALSE
  )
})

rows[[length(rows) + 1]] <- elapsed("medium_panel_weighted_ipw", {
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "ipw", xformla = ~1, weightsname = "wt",
    bstrap = FALSE, cband = FALSE
  )
}, reps = 3L)

rows[[length(rows) + 1]] <- elapsed("medium_panel_clustered_reg", {
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "reg", xformla = ~1, clustervars = "cl",
    bstrap = FALSE, cband = FALSE
  )
})

rows[[length(rows) + 1]] <- elapsed("medium_panel_bootstrap_reg", {
  set.seed(20260627)
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "reg", xformla = ~1, bstrap = TRUE, biters = 1000,
    cband = FALSE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_panel_bootstrap_cband_reg", {
  set.seed(20260627)
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "reg", xformla = ~1, bstrap = TRUE, biters = 1000,
    cband = TRUE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_panel_bootstrap_default", {
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "dr", xformla = ~1, bstrap = TRUE, biters = 1000,
    cband = TRUE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_panel_bootstrap_covariate_dr", {
  set.seed(20260627)
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "dr", xformla = ~x1 + x2, bstrap = TRUE, biters = 1000,
    cband = FALSE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_panel_bootstrap_weighted_ipw", {
  set.seed(20260627)
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "ipw", xformla = ~1, weightsname = "wt",
    bstrap = TRUE, biters = 1000, cband = FALSE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_panel_bootstrap_clustered_reg", {
  set.seed(20260627)
  att_gt(
    yname = "y", tname = "time", idname = "id", gname = "g", data = medium,
    est_method = "reg", xformla = ~1, clustervars = "cl",
    bstrap = TRUE, biters = 1000, cband = FALSE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_unbalanced_bootstrap_cov_weight_dr", {
  set.seed(20260627)
  att_gt(
    yname = "y", tname = "time", idname = NULL, gname = "g",
    data = unbalanced, panel = FALSE, est_method = "dr",
    xformla = ~x1 + x2, weightsname = "wt",
    bstrap = TRUE, biters = 1000, cband = FALSE
  )
}, reps = 3L, best_of = TRUE)

rows[[length(rows) + 1]] <- elapsed("medium_unbalanced_cov_weight_dr", {
  att_gt(
    yname = "y", tname = "time", idname = NULL, gname = "g",
    data = unbalanced, panel = FALSE, est_method = "dr",
    xformla = ~x1 + x2, weightsname = "wt", bstrap = FALSE, cband = FALSE
  )
})

att_agg <- att_gt(
  yname = "y", tname = "time", idname = "id", gname = "g",
  data = aggregation, est_method = "reg", xformla = ~1,
  bstrap = FALSE, cband = FALSE
)
att_agg_boot <- att_gt(
  yname = "y", tname = "time", idname = "id", gname = "g",
  data = aggregation, est_method = "reg", xformla = ~1,
  bstrap = TRUE, biters = 1000, cband = FALSE
)
agg_dynamic <- aggte(att_agg, type = "dynamic", bstrap = FALSE, cband = FALSE)
agg_group <- aggte(att_agg, type = "group", bstrap = FALSE, cband = FALSE)
agg_calendar <- aggte(att_agg, type = "calendar", bstrap = FALSE, cband = FALSE)
rows[[length(rows) + 1]] <- elapsed("aggregation_bootstrap_dynamic_medium", {
  aggte(att_agg_boot, type = "dynamic")
}, reps = 3L, best_of = TRUE)
rows[[length(rows) + 1]] <- elapsed("aggregation_medium", {
  aggte(att_agg, type = "dynamic", bstrap = FALSE, cband = FALSE)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("aggregation_simple_medium", {
  aggte(att_agg, type = "simple", bstrap = FALSE, cband = FALSE)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("aggregation_group_medium", {
  aggte(att_agg, type = "group", bstrap = FALSE, cband = FALSE)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("aggregation_calendar_medium", {
  aggte(att_agg, type = "calendar", bstrap = FALSE, cband = FALSE)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("plot_attgt_medium", {
  ggdid(att_agg)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("plot_dynamic_medium", {
  ggdid(agg_dynamic)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("plot_group_medium", {
  ggdid(agg_group)
}, reps = 20L)
rows[[length(rows) + 1]] <- elapsed("plot_calendar_medium", {
  ggdid(agg_calendar)
}, reps = 20L)

results <- do.call(rbind, rows)
write.csv(results, file.path(outdir, "r-results.csv"), row.names = FALSE)
print(results)
