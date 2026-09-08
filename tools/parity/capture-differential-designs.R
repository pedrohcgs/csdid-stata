# Observe the matrices passed to the pinned reference's fitters. This collector
# does not change fitter arguments, results or errors. Reader failures remain
# separate from estimator refusals.
.csdid_design_capture <- new.env(parent = emptyenv())

csdid_design_begin <- function(trial, input, spec) {
  .csdid_design_capture$trial <- trial
  .csdid_design_capture$spec <- spec
  .csdid_design_capture$input_sha256 <- digest::digest(file = input, algo = "sha256")
  .csdid_design_capture$cells <- list()
  .csdid_design_capture$errors <- character()
  .csdid_design_capture$aggregations <- list()
  .csdid_design_capture$wald <- NULL
}

.csdid_design_observe <- function(frame, result = NULL, fitted = FALSE) {
  tryCatch({
    if (fitted) {
      group <- frame$g_val
      time <- frame$t_val
    } else {
      group <- frame$dp2$treated_groups[frame$g]
      time <- frame$dp2$time_periods[frame$t + frame$tfac]
    }
    stopifnot(length(group) == 1L, length(time) == 1L)
    key <- paste(group, time, sep = ":")
    entry <- .csdid_design_capture$cells[[key]]
    if (is.null(entry)) entry <- list(group = group, time = time)
    if (fitted) {
      stopifnot(is.null(entry$X_f64le))
      x <- as.matrix(frame$covariates)
      rows <- frame$valid_obs
      dp <- frame$dp2
      if (dp$panel && !frame$force_rc) {
        ids <- dp$time_invariant_data[[dp$idname]][rows]
        periods <- rep(min(frame$pret_val, frame$t_val), length(rows))
        route <- "panel"
      } else if (frame$force_rc) {
        ids <- rep(dp$time_invariant_data[[dp$idname]], 2L)[rows]
        periods <- ifelse(frame$post == 1, frame$t_val, frame$pret_val)
        route <- "panel_stacked"
      } else {
        ids <- dp$time_invariant_data[[dp$idname]][rows]
        periods <- dp$time_invariant_data[[dp$tname]][rows]
        route <- if (dp$allow_unbalanced_panel) "unbalanced" else "rcs"
      }
      stopifnot(nrow(x) == length(ids), nrow(x) == length(frame$D),
                nrow(x) == length(frame$i.weights), all(is.finite(x)),
                all(is.finite(ids)), all(is.finite(periods)))
      entry$pre <- frame$pret_val
      entry$route <- route
      entry$X_f64le <- gsub("[[:space:]]", "", jsonlite::base64_enc(
        writeBin(as.double(x), raw(), size = 8L, endian = "little")))
      entry$columns <- ncol(x)
      entry$rows <- nrow(x)
      entry$ids <- unname(ids)
      entry$periods <- unname(periods)
      entry$D <- unname(frame$D)
      entry$weights <- unname(frame$i.weights)
    } else {
      stopifnot(is.null(entry$status))
      entry$status <- if (!is.null(result$base_period_norm)) "structural_zero" else
        if (is.null(result$att) || !is.finite(result$att)) "missing" else "fitted"
      if (entry$status == "fitted") stopifnot(!is.null(entry$X_f64le))
    }
    .csdid_design_capture$cells[[key]] <- entry
  }, error = function(error) {
    .csdid_design_capture$errors <- c(.csdid_design_capture$errors, conditionMessage(error))
  })
  invisible(NULL)
}

csdid_design_write <- function(path) {
  jsonlite::write_json(list(schema = 1L, trial = .csdid_design_capture$trial,
    input_sha256 = .csdid_design_capture$input_sha256,
    spec = .csdid_design_capture$spec,
    errors = as.list(.csdid_design_capture$errors),
    cells = unname(.csdid_design_capture$cells),
    wald = .csdid_design_capture$wald,
    aggregations = .csdid_design_capture$aggregations), path,
    auto_unbox = TRUE, digits = NA, null = "null", na = "null", pretty = FALSE)
}

trace("run_DRDID", where = asNamespace("did"),
      exit = quote(.GlobalEnv$.csdid_design_observe(environment(), fitted = TRUE)), print = FALSE)
trace("run_att_gt_estimation", where = asNamespace("did"),
      exit = quote(.GlobalEnv$.csdid_design_observe(environment(), returnValue())), print = FALSE)

csdid_design_agg_begin <- function(label) {
  .csdid_design_capture$aggregation <- label
  .csdid_design_capture$current_support <- list()
  .csdid_design_capture$current_errors <- character()
}

.csdid_design_agg <- function(frame, expression, frames) {
  tryCatch({
    owners <- Filter(function(e) exists("originalgroup", e, inherits = FALSE) &&
      exists("originalt", e, inherits = FALSE) && exists("MP", e, inherits = FALSE), frames)
    stopifnot(length(owners) == 1L)
    owner <- owners[[1L]]
    which <- frame$whichones
    weights <- frame$weights.agg
    stopifnot(length(which) == length(weights), all(is.finite(weights)))
    contributes <- weights != 0
    if (!is.null(frame$wif)) {
      stopifnot(ncol(frame$wif) == length(which), all(is.finite(frame$wif)))
      contributes <- contributes | colSums(abs(frame$wif)) != 0
    }
    selected <- which[contributes]
    if (identical(expression, quote(att))) {
      groups <- owner$originalgroup[selected]
      times <- owner$originalt[selected]
      label <- switch(owner$type,
        simple = "overall",
        group = paste0("egt:", unique(owner$originalgroup[which])),
        calendar = paste0("egt:", unique(owner$originalt[which])),
        dynamic = paste0("egt:", unique(owner$originalt[which] - owner$originalgroup[which])))
      stopifnot(length(label) == 1L)
      keys <- paste(groups, times, sep = ":")
    } else {
      labels <- switch(owner$type,
        group = owner$originalglist,
        calendar = owner$t2orig(owner$calendar.tlist),
        dynamic = owner$eseq[owner$epos])
      stopifnot(length(labels) == length(frame$att))
      children <- paste0("egt:", labels[selected])
      stopifnot(all(children %in% names(.csdid_design_capture$current_support)))
      keys <- unlist(.csdid_design_capture$current_support[children], use.names = FALSE)
      label <- "overall"
    }
    stopifnot(is.null(.csdid_design_capture$current_support[[label]]))
    .csdid_design_capture$current_support[[label]] <- as.list(unique(keys))
  }, error = function(error) {
    .csdid_design_capture$current_errors <- c(.csdid_design_capture$current_errors, conditionMessage(error))
  })
  invisible(NULL)
}

csdid_design_agg_end <- function(result) {
  label <- .csdid_design_capture$aggregation
  status <- if (inherits(result, "error")) "refused" else "complete"
  expected <- if (status == "complete") c("overall", if (length(result$egt)) paste0("egt:", result$egt)) else character()
  supports <- .csdid_design_capture$current_support
  if (status == "complete" && !setequal(names(supports), expected)) {
    .csdid_design_capture$errors <- c(.csdid_design_capture$errors,
      paste("aggregation support incomplete:", label))
  }
  # A reference error returns no estimates requiring a bound. Keep its trace
  # diagnostics with that refusal; any error on a returned aggregation remains
  # a failure of the required numerical evidence.
  errors <- .csdid_design_capture$current_errors
  if (status == "complete") {
    .csdid_design_capture$errors <- c(.csdid_design_capture$errors, errors)
  }
  .csdid_design_capture$aggregations[[label]] <- list(status = status,
    supports = supports, errors = as.list(errors))
}

.csdid_design_wald <- function(frame, result) {
  if (!inherits(result, "MP")) return(invisible(NULL))
  tryCatch({
    keys <- character()
    status <- "missing"
    if (length(result$Wpval) == 1L && is.finite(result$Wpval)) {
      stopifnot(length(frame$pre) > 0L)
      keys <- paste(frame$group[frame$pre], frame$tt[frame$pre], sep = ":")
      status <- "complete"
    }
    .csdid_design_capture$wald <- list(status = status, support = as.list(keys))
  }, error = function(error) {
    .csdid_design_capture$errors <- c(.csdid_design_capture$errors, conditionMessage(error))
  })
  invisible(NULL)
}

trace("get_agg_inf_func", where = asNamespace("did"),
      exit = quote(.GlobalEnv$.csdid_design_agg(environment(), substitute(att), sys.frames())), print = FALSE)
trace("att_gt", where = asNamespace("did"),
      exit = quote(.GlobalEnv$.csdid_design_wald(environment(), returnValue())), print = FALSE)
