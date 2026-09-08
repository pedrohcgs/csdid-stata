#------------------------------------------------------------------------------
# Speed figure for the csdid-against-the-field guide
#
# Two log-log panels drawn from the recorded inputs to the Speed tables:
#   A. seconds vs rows       (unbalanced-panel table: n x {1k,10k,100k}, T=10)
#   B. seconds vs periods T  (T-scaling table: T x {5,10,20,40}, n=10,000)
# Timings include estimation and event-study aggregation with clustered
# standard errors. The recorded trial count and date label the figure.
#
# Outputs: <outdir>/field-speed.png and field-speed.provenance.json
# Usage  : Rscript fig_speed.R [outdir] [resultsdir]
#------------------------------------------------------------------------------
rm(list = ls())

library(ggplot2)
library(ggtext)
library(cowplot)
library(dplyr)

#------------------------------------------------------------------------------
# Set parameters
#------------------------------------------------------------------------------
args   <- commandArgs(trailingOnly = TRUE)
outdir <- ifelse(length(args) >= 1, args[1], ".")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
if (length(script) != 1) stop("Run this figure with Rscript.")
resultsdir <- if (length(args) >= 2) args[2] else
  file.path(dirname(normalizePath(script)), "results")
raw <- read.csv(file.path(resultsdir, "scalebench-results.csv"),
                stringsAsFactors = FALSE, na.strings = c("NA", ".", ""))
meta <- jsonlite::fromJSON(file.path(resultsdir, "metadata.json"))
required <- c("scan", "n_units", "T", "cohorts", "rows", "pkg",
              "median_seconds", "trials", "ok")
if (!all(required %in% names(raw))) stop("Incomplete speed-results schema.")
if (length(meta$trials) != 1 || !is.numeric(meta$trials) ||
    !is.finite(meta$trials) || meta$trials < 1 || meta$trials != floor(meta$trials))
  stop("Missing or invalid recorded trial count.")
if (length(meta$date) != 1 || is.na(as.Date(meta$date)) ||
    format(as.Date(meta$date), "%Y-%m-%d") != meta$date)
  stop("Missing or invalid benchmark date.")

navy <- "#012169"
gray <- "#525252"
cols <- c("csdid"          = "#1e40af",
          "jwdid"          = "#d97706",
          "did_imputation" = "#b91c1c",
          "lpdid"          = "#6b7280")

# A complete grid is required: a missing or duplicated measurement must not
# silently change a line, endpoint label or the bootstrap-cost annotation.
select_cells <- function(scan_name, units, periods, packages) {
  keep <- with(raw, scan == scan_name & n_units %in% units & T %in% periods &
                     cohorts == 4 & pkg %in% packages)
  dat <- raw[which(keep), ]
  grid <- expand.grid(n_units = units, T = periods, pkg = packages)
  key <- function(x) sprintf("%d/%d/%s", x$n_units, x$T, x$pkg)
  if (nrow(dat) != nrow(grid) || anyDuplicated(key(dat)) ||
      !setequal(key(dat), key(grid)))
    stop("Incomplete or duplicated speed grid: ", scan_name)
  if (anyNA(dat[required]) || any(dat$ok != 1) ||
      any(dat$trials != meta$trials) ||
      any(!is.finite(dat$median_seconds) | dat$median_seconds <= 0) ||
      any(!is.finite(dat$rows) | dat$rows <= 0 | dat$rows != floor(dat$rows)))
    stop("Invalid or unsuccessful speed measurement: ", scan_name)
  row_counts <- split(dat$rows, paste(dat$n_units, dat$T))
  if (any(vapply(row_counts, function(x) length(unique(x)) != 1, logical(1))))
    stop("Commands have different input row counts: ", scan_name)
  dat$cmd <- ifelse(grepl("^csdid", dat$pkg), "csdid", dat$pkg)
  dat$sec <- dat$median_seconds
  dat
}

rivals <- c("jwdid", "lpdid", "did_imputation")
size_tab <- select_cells("A_unbal", c(1000, 10000, 100000), 10,
                         c("csdid_balnone", rivals))
T_tab <- select_cells("C_periods", 10000, c(5, 10, 20, 40),
                      c("csdid", rivals))
default_tab <- select_cells("E_default", 100000, 10,
                            c("csdid_analytical", "csdid_boot999"))
if (any(T_tab$rows != T_tab$n_units * T_tab$T) ||
    any(default_tab$rows != 1000000))
  stop("Recorded balanced-panel dimensions do not match the figure.")
analytical <- default_tab$sec[default_tab$pkg == "csdid_analytical"]
bootstrap <- default_tab$sec[default_tab$pkg == "csdid_boot999"]
size_rows <- sort(unique(size_tab$rows))

#------------------------------------------------------------------------------
# Theme
#------------------------------------------------------------------------------
theme_fig <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(color = navy, face = "bold", size = 15),
      plot.subtitle    = element_text(color = gray, size = 11,
                                      margin = margin(b = 8)),
      axis.title       = element_text(color = navy),
      axis.text        = element_text(color = gray),
      legend.position  = "none",
      panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      plot.background  = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin      = margin(10, 10, 10, 10)
    )
}

#------------------------------------------------------------------------------
# One workhorse for both panels: log-log lines with end labels
#------------------------------------------------------------------------------
speed_panel <- function(tab, xvar, title, subtitle, xlab, xbreaks, xlabels) {
  long <- tab %>%
    mutate(cmd = factor(cmd, levels = names(cols)))
  ends <- long %>%
    group_by(cmd) %>% slice_max(.data[[xvar]], n = 1) %>% ungroup() %>%
    mutate(lab = paste0("**", cmd, ":** ",
                        trimws(formatC(sec, format = "fg", digits = 3)), " s"))

  ggplot(long, aes(x = .data[[xvar]], y = sec, colour = cmd)) +
    geom_line(linewidth = 1.1) +
    geom_point(size = 2.4) +
    ggtext::geom_richtext(
      data = ends, aes(label = lab), hjust = 0, vjust = 0.5,
      nudge_x = 0.045, fill = NA, label.color = NA, size = 3.6,
      show.legend = FALSE) +
    scale_colour_manual(values = cols) +
    scale_x_log10(breaks = xbreaks, labels = xlabels,
                  expand = expansion(mult = c(0.04, 0.42))) +
    scale_y_log10(breaks = c(0.1, 0.3, 1, 3, 10, 30),
                  labels = c("0.1", "0.3", "1", "3", "10", "30")) +
    labs(title = title, subtitle = subtitle, x = xlab, y = "seconds") +
    theme_fig()
}

pA <- speed_panel(size_tab, "rows",
  "More data",
  "Unbalanced panel (15% random row deletion), T=10, four cohorts",
  "rows in the panel",
  size_rows, format(size_rows, big.mark = ",", scientific = FALSE, trim = TRUE))

pB <- speed_panel(T_tab, "T",
  "More periods",
  "Balanced panel, 10,000 units, four cohorts",
  "number of time periods",
  c(5, 10, 20, 40), c("5", "10", "20", "40"))

#------------------------------------------------------------------------------
# Assemble: title block, panels, source note
#------------------------------------------------------------------------------
panels <- cowplot::plot_grid(pA, pB, ncol = 2)

title_grob <- cowplot::ggdraw() +
  cowplot::draw_label(
    "Computation time by sample size and number of periods",
    x = 0.012, y = 0.76, hjust = 0, vjust = 0.5, color = navy,
    fontface = "bold", size = 19) +
  cowplot::draw_label(
    sprintf("Estimation plus event-study aggregation with clustered standard errors; median of %d runs. Both axes on log scale.",
            meta$trials),
    x = 0.012, y = 0.22, hjust = 0, vjust = 0.5, color = gray, size = 12)

foot_grob <- cowplot::ggdraw() +
  cowplot::draw_label(
    paste0("Recorded ", meta$date, ". Plotted csdid curves: analytical pointwise, bal(none). Options and horizons follow the Speed tables.\n",
           sprintf("At one million balanced rows: analytical %.2f s; 999 bootstrap draws plus uniform bands %.2f s (%.3f s extra), including event aggregation.",
                   analytical, bootstrap, bootstrap - analytical)),
    x = 0.012, y = 0.5, hjust = 0, vjust = 0.5, color = gray, size = 10.5,
    lineheight = 1.2)

combo <- cowplot::plot_grid(title_grob, panels, foot_grob, ncol = 1,
                            rel_heights = c(0.16, 1, 0.11))

image_file <- file.path(outdir, "field-speed.png")
ggsave(image_file, combo,
       width = 13, height = 5.6, dpi = 200, bg = "white")

files <- c(r_source_sha256 = script,
           results_sha256 = file.path(resultsdir, "scalebench-results.csv"),
           metadata_sha256 = file.path(resultsdir, "metadata.json"),
           image_sha256 = image_file)
provenance <- as.list(vapply(files, function(path)
  digest::digest(file = path, algo = "sha256", serialize = FALSE), character(1)))
jsonlite::write_json(provenance, file.path(outdir, "field-speed.provenance.json"),
                     auto_unbox = TRUE, pretty = TRUE)
