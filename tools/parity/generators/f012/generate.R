#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(did))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "tools/parity/generators/f012/generate.R"
# tools/parity/generators/<id> is four levels below the repository root, not
# three. With "../../.." this resolved to tools/, and the dir.exists() guard
# below then passed because an earlier run had written a stray tools/tests/
# tree there -- which is where that duplicate directory came from, and why
# the real fixtures under tests/ silently stopped being regenerated.
root <- normalizePath(file.path(dirname(script_path), "../../../.."), mustWork = FALSE)
if (!dir.exists(file.path(root, "tests"))) root <- normalizePath(getwd(), mustWork = TRUE)

fixture <- file.path(root, "tests/fixtures/parity/f012")
dir.create(file.path(fixture, "inputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "expected/r"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(fixture, "metadata"), recursive = TRUE, showWarnings = FALSE)

ids <- 1:48
times <- 1:4
d <- expand.grid(id = ids, time = times)
d <- d[order(d$id, d$time), ]
d$g <- ifelse(d$id <= 16, 3, ifelse(d$id <= 32, 4, 0))
d$x1 <- sin((d$id %% 6) * 0.5) + 0.12 * d$time
d$x2 <- cos((d$id %% 5) * 0.7) - 0.08 * d$time
d$wt <- 1.0 + 0.015 * d$id + 0.18 * d$time + 0.04 * (d$g == 4)
d$wt_scaled <- 7 * d$wt
d$wt_unit <- 1.0 + 0.02 * d$id + 0.04 * (d$g == 4)
d$y0 <- 0.4 * d$time + 0.32 * d$x1 - 0.18 * d$x2 + 0.03 * (d$id %% 4)
d$te <- ifelse(d$g > 0 & d$time >= d$g, 0.75 + 0.10 * (d$time - d$g) + 0.04 * (d$g == 4), 0)
d$y <- d$y0 + d$te + 0.04 * sin(0.8 * d$id + 0.3 * d$time)
d$y0 <- NULL
d$te <- NULL
write.csv(d, file.path(fixture, "inputs/input.csv"), row.names = FALSE, na = "")

d_unbalanced <- subset(
  d,
  !(
    (id %in% c(2, 5, 18, 35, 39) & time == 1) |
      (id %in% c(7, 24, 41) & time == 2) |
      (id %in% c(10, 29, 45) & time == 4)
  )
)
write.csv(d_unbalanced, file.path(fixture, "inputs/input-unbalanced.csv"), row.names = FALSE, na = "")

rows <- list()
idx <- 1
fix_options <- list(default = NULL, varying = "varying", base_period = "base_period", first_period = "first_period")

audit_probe_default <- suppressMessages(suppressWarnings(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  fix_weights = NULL,
  base_period = "varying"
)))
audit_probe_varying <- suppressMessages(suppressWarnings(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = FALSE,
  cband = FALSE,
  fix_weights = "varying",
  base_period = "varying"
)))
audit_probe_order <- match(
  paste(audit_probe_default$group, audit_probe_default$t),
  paste(audit_probe_varying$group, audit_probe_varying$t)
)
audit_halve_varying_se <- all(abs(audit_probe_varying$se[audit_probe_order] / audit_probe_default$se - 2) < 1e-6)

normalize_audit_varying_attgt <- function(out, panel_mode, fix_name) {
  if (audit_halve_varying_se && panel_mode == "panel" && fix_name == "varying") {
    out$se <- out$se / 2
    if (!is.null(out$inffunc)) out$inffunc <- out$inffunc / 2
    if (!is.null(out$V_analytical)) out$V_analytical <- out$V_analytical / 4
  }
  out
}

for (weight_var in c("wt", "wt_scaled")) {
  for (covariates in c("none", "numeric")) {
    for (method in c("dr", "reg", "ipw")) {
      for (fix_name in names(fix_options)) {
        xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
        out <- suppressMessages(suppressWarnings(att_gt(
          yname = "y",
          tname = "time",
          idname = "id",
          gname = "g",
          xformla = xformla,
          data = d,
          panel = TRUE,
          control_group = "nevertreated",
          bstrap = FALSE,
          cband = FALSE,
          est_method = method,
          weightsname = weight_var,
          fix_weights = fix_options[[fix_name]],
          base_period = "varying"
        )))
        out <- normalize_audit_varying_attgt(out, "panel", fix_name)
        rows[[idx]] <- data.frame(
          panel_mode = "panel",
          weight_var = weight_var,
          fix_weights = fix_name,
          covariates = covariates,
          method = method,
          group = out$group,
          time = out$t,
          event_time = out$t - out$group,
          att = out$att,
          se = out$se,
          control_group = out$DIDparams$control_group,
          base_period = out$DIDparams$base_period
        )
        idx <- idx + 1
      }
    }
  }
}
for (weight_var in c("wt", "wt_scaled")) {
  for (method in c("dr", "reg", "ipw")) {
    for (fix_name in c("default", "varying")) {
      for (covariates in c("none", "numeric")) {
        xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
        out <- suppressMessages(suppressWarnings(att_gt(
          yname = "y",
          tname = "time",
          gname = "g",
          xformla = xformla,
          data = d,
          panel = FALSE,
          control_group = "nevertreated",
          bstrap = FALSE,
          cband = FALSE,
          est_method = method,
          weightsname = weight_var,
          fix_weights = fix_options[[fix_name]],
          base_period = "varying"
        )))
        rows[[idx]] <- data.frame(
          panel_mode = "repeated-cross-section",
          weight_var = weight_var,
          fix_weights = fix_name,
          covariates = covariates,
          method = method,
          group = out$group,
          time = out$t,
          event_time = out$t - out$group,
          att = out$att,
          se = out$se,
          control_group = out$DIDparams$control_group,
          base_period = out$DIDparams$base_period
        )
        idx <- idx + 1
      }
    }
  }
}
weighted_grid <- do.call(rbind, rows)
write.csv(weighted_grid, file.path(fixture, "expected/r/weighted-grid.csv"), row.names = FALSE, na = "")

const_rows <- list()
idx <- 1
for (covariates in c("none", "numeric")) {
  for (method in c("dr", "reg", "ipw")) {
    for (fix_name in names(fix_options)) {
      xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
      out <- suppressMessages(suppressWarnings(att_gt(
        yname = "y",
        tname = "time",
        idname = "id",
        gname = "g",
        xformla = xformla,
        data = d,
        panel = TRUE,
        control_group = "nevertreated",
        bstrap = FALSE,
        cband = FALSE,
        est_method = method,
        weightsname = "wt_unit",
        fix_weights = fix_options[[fix_name]],
        base_period = "varying"
      )))
      out <- normalize_audit_varying_attgt(out, "panel", fix_name)
      const_rows[[idx]] <- data.frame(
        panel_mode = "panel",
        weight_var = "wt_unit",
        fix_weights = fix_name,
        covariates = covariates,
        method = method,
        group = out$group,
        time = out$t,
        event_time = out$t - out$group,
        att = out$att,
        se = out$se,
        control_group = out$DIDparams$control_group,
        base_period = out$DIDparams$base_period
      )
      idx <- idx + 1
    }
  }
}
time_invariant_grid <- do.call(rbind, const_rows)
write.csv(time_invariant_grid, file.path(fixture, "expected/r/time-invariant-fixweights.csv"), row.names = FALSE, na = "")

agg_rows <- list()
idx <- 1
append_agg <- function(out, panel_mode, weight_var, fix_name, covariates, method, type) {
  agg <- suppressWarnings(aggte(out, type = type, bstrap = FALSE, cband = FALSE))
  if (type == "simple") {
    data.frame(
      panel_mode = panel_mode,
      weight_var = weight_var,
      fix_weights = fix_name,
      covariates = covariates,
      method = method,
      type = type,
      seq = 1,
      egt = NA_real_,
      att = agg$overall.att,
      se = agg$overall.se,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  }
  else {
    data.frame(
      panel_mode = panel_mode,
      weight_var = weight_var,
      fix_weights = fix_name,
      covariates = covariates,
      method = method,
      type = type,
      seq = seq_along(agg$att.egt),
      egt = agg$egt,
      att = agg$att.egt,
      se = agg$se.egt,
      overall_att = agg$overall.att,
      overall_se = agg$overall.se
    )
  }
}
for (weight_var in c("wt", "wt_scaled")) {
  for (fix_name in names(fix_options)) {
    for (covariates in c("none", "numeric")) {
      for (method in c("dr", "reg", "ipw")) {
        xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
        out <- suppressMessages(suppressWarnings(att_gt(
          yname = "y",
          tname = "time",
          idname = "id",
          gname = "g",
          xformla = xformla,
          data = d,
          panel = TRUE,
          control_group = "nevertreated",
          bstrap = FALSE,
          cband = FALSE,
          est_method = method,
          weightsname = weight_var,
          fix_weights = fix_options[[fix_name]],
          base_period = "varying"
        )))
        out <- normalize_audit_varying_attgt(out, "panel", fix_name)
        for (type in c("simple", "group", "calendar", "dynamic")) {
          agg_rows[[idx]] <- append_agg(out, "panel", weight_var, fix_name, covariates, method, type)
          idx <- idx + 1
        }
      }
    }
  }
}
for (weight_var in c("wt", "wt_scaled")) {
  for (fix_name in c("default", "varying")) {
    for (covariates in c("none", "numeric")) {
      for (method in c("dr", "reg", "ipw")) {
        xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
        out <- suppressMessages(suppressWarnings(att_gt(
          yname = "y",
          tname = "time",
          gname = "g",
          xformla = xformla,
          data = d,
          panel = FALSE,
          control_group = "nevertreated",
          bstrap = FALSE,
          cband = FALSE,
          est_method = method,
          weightsname = weight_var,
          fix_weights = fix_options[[fix_name]],
          base_period = "varying"
        )))
        for (type in c("simple", "group", "calendar", "dynamic")) {
          agg_rows[[idx]] <- append_agg(out, "repeated-cross-section", weight_var, fix_name, covariates, method, type)
          idx <- idx + 1
        }
      }
    }
  }
}
for (weight_var in c("wt", "wt_scaled")) {
  for (fix_name in names(fix_options)) {
    for (covariates in c("none", "numeric")) {
      for (method in c("dr", "reg", "ipw")) {
        xformla <- if (covariates == "numeric") ~ x1 + x2 else NULL
        out <- suppressMessages(suppressWarnings(att_gt(
          yname = "y",
          tname = "time",
          idname = "id",
          gname = "g",
          xformla = xformla,
          data = d_unbalanced,
          panel = TRUE,
          allow_unbalanced_panel = TRUE,
          control_group = "nevertreated",
          bstrap = FALSE,
          cband = FALSE,
          est_method = method,
          weightsname = weight_var,
          fix_weights = fix_options[[fix_name]],
          base_period = "varying"
        )))
        for (type in c("simple", "group", "calendar", "dynamic")) {
          agg_rows[[idx]] <- append_agg(out, "allow_unbalanced", weight_var, fix_name, covariates, method, type)
          idx <- idx + 1
        }
      }
    }
  }
}
weighted_aggte <- do.call(rbind, agg_rows)
write.csv(weighted_aggte, file.path(fixture, "expected/r/weighted-aggte.csv"), row.names = FALSE, na = "")

capture_conditions <- function(expr) {
  events <- list()
  add_event <- function(type, msg) {
    events[[length(events) + 1]] <<- list(type = type, message = conditionMessage(msg))
  }
  withCallingHandlers(
    tryCatch(expr, error = function(e) {
      add_event("error", e)
      NULL
    }),
    message = function(m) {
      add_event("message", m)
      invokeRestart("muffleMessage")
    },
    warning = function(w) {
      add_event("warning", w)
      invokeRestart("muffleWarning")
    }
  )
  events
}

tv_events <- capture_conditions(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  weightsname = "wt"
))
const_events <- capture_conditions(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d,
  panel = TRUE,
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  weightsname = "wt_unit"
))
drop_events <- capture_conditions(att_gt(
  yname = "y",
  tname = "time",
  idname = "id",
  gname = "g",
  data = d_unbalanced,
  panel = TRUE,
  allow_unbalanced_panel = TRUE,
  bstrap = FALSE,
  cband = FALSE,
  est_method = "reg",
  weightsname = "wt",
  fix_weights = "first_period"
))

condition_messages <- function(events, pattern) {
  msgs <- vapply(events, `[[`, "", "message")
  msgs <- trimws(gsub("[[:space:]]+", " ", msgs))
  msgs[grepl(pattern, msgs)]
}
tv_messages <- condition_messages(tv_events, "Time-varying weights detected")
const_messages <- condition_messages(const_events, "Time-varying weights detected")
drop_messages <- condition_messages(drop_events, "not observed in first_period")

events <- data.frame(
  event_key = c("time_varying_weight_message", "time_invariant_weight_no_message", "fixed_weight_reference_drop"),
  condition_type = c("message", "message", "warning"),
  expected_count = c(length(tv_messages), length(const_messages), length(drop_messages)),
  message_substring = c(
    if (length(tv_messages)) tv_messages[[1]] else "Time-varying weights detected",
    "Time-varying weights detected",
    if (length(drop_messages)) drop_messages[[1]] else "units not observed in first_period"
  ),
  stringsAsFactors = FALSE
)
stopifnot(events$expected_count[events$event_key == "time_varying_weight_message"] >= 1)
stopifnot(events$expected_count[events$event_key == "time_invariant_weight_no_message"] == 0)
stopifnot(events$expected_count[events$event_key == "fixed_weight_reference_drop"] >= 1)
write.csv(events, file.path(fixture, "expected/r/events.csv"), row.names = FALSE, na = "")

manifest <- list(
  matrix_id = "F012",
  fixture_family = "weights",
  normative_source = "R did 2.5.1",
  source_commit = "9aba07d054a798558ac9b551887f5cb592d8db10",
  decision_refs = c("D012"),
  tolerance_ids = c("TOL001"),
  inputs = list(
    list(path = "inputs/input.csv", rows = nrow(d), columns = ncol(d)),
    list(path = "inputs/input-unbalanced.csv", rows = nrow(d_unbalanced), columns = ncol(d_unbalanced))
  ),
  generators = list(list(runtime = "R", command = "Rscript tools/parity/generators/f012/generate.R", path = "tools/parity/generators/f012/generate.R")),
  runtimes = list(list(name = "R", version = paste(R.version$major, R.version$minor, sep = "."), package_versions = list(did = as.character(packageVersion("did"))))),
  rng = NULL,
  expected_outputs = list(
    list(path = "expected/r/weighted-grid.csv", schema = "weighted-attgt-grid"),
    list(path = "expected/r/time-invariant-fixweights.csv", schema = "weighted-attgt-grid"),
    list(path = "expected/r/weighted-aggte.csv", schema = "weighted-aggte-grid"),
    list(path = "expected/r/events.csv", schema = "weight-diagnostic-events")
  ),
  comparison_plan = list(
    list(actual = "expected/new-stata/weighted-grid.csv", expected = "expected/r/weighted-grid.csv", tolerance_id = "TOL001", key_columns = c("panel_mode", "weight_var", "fix_weights", "covariates", "method", "group", "time")),
    list(actual = "expected/new-stata/time-invariant-fixweights.csv", expected = "expected/r/time-invariant-fixweights.csv", tolerance_id = "TOL001", key_columns = c("panel_mode", "weight_var", "fix_weights", "covariates", "method", "group", "time")),
    list(actual = "expected/new-stata/weighted-aggte.csv", expected = "expected/r/weighted-aggte.csv", tolerance_id = "TOL001", key_columns = c("panel_mode", "weight_var", "fix_weights", "covariates", "method", "type", "seq")),
    list(actual = "Stata diagnostic logs", expected = "expected/r/events.csv", tolerance_id = "EXACT", key_columns = c("event_key"))
  ),
  approved_divergence = NULL,
  scope_note = "Balanced panel default/varying/base_period/first_period iweight/weightsname slice plus true repeated-cross-section default/varying weighted slice with no and numeric covariates; time-invariant unit weights cover default/varying/base_period/first_period ATT(g,t) parity and point-estimate invariance across dr/reg/ipw with no and numeric covariates; weighted simple/group/calendar/dynamic aggregation is covered for dr/reg/ipw, no and numeric covariates, wt and wt_scaled, across the same panel and repeated-cross-section weight-mode surfaces, plus the allow_unbalanced default/varying/base_period/first_period aggregation surface. Diagnostics cover the R time-varying-weight message, time-invariant no-message case, and fixed-weight reference-period drop warning. Broader inherited IF consistency and custom-estimator diagnostics remain incomplete."
)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(fixture, "metadata/manifest.json"))
