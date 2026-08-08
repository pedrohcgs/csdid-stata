#------------------------------------------------------------------------------
# Speed figure for the csdid-against-the-field guide
#
# Two log-log panels drawn from the published Speed-section tables:
#   A. seconds vs rows       (unbalanced-panel table: n x {1k,10k,100k}, T=10)
#   B. seconds vs periods T  (T-scaling table: T x {5,10,20,40}, n=10,000)
# The numbers below are exactly the numbers printed in those tables; the
# timing protocol (median of 10 runs, event study plus clustered standard
# errors) is described in the Speed section.
#
# Output : <outdir>/field-speed.png
# Usage  : Rscript fig_speed.R [outdir]
#------------------------------------------------------------------------------
rm(list = ls())

library(ggplot2)
library(ggtext)
library(cowplot)
library(dplyr)
library(tibble)

#------------------------------------------------------------------------------
# Set parameters
#------------------------------------------------------------------------------
args   <- commandArgs(trailingOnly = TRUE)
outdir <- ifelse(length(args) >= 1, args[1], ".")

navy <- "#012169"
gray <- "#525252"
cols <- c("csdid"          = "#1e40af",
          "jwdid"          = "#d97706",
          "did_imputation" = "#b91c1c",
          "lpdid"          = "#6b7280")

# Speed section, "Unbalanced panels" table (csdid at bal(none), T=10, G=4)
size_tab <- tribble(
  ~rows,   ~csdid, ~jwdid, ~lpdid, ~did_imputation,
  8500,     0.10,   0.20,   0.32,   0.57,
  85000,    0.69,   0.70,   0.85,   3.85,
  850000,   3.79,   6.28,   5.83,   38.0
)

# Speed section, T-scaling table (balanced panel, n=10,000, G=4)
T_tab <- tribble(
  ~T,  ~csdid, ~jwdid, ~lpdid, ~did_imputation,
  5,    0.13,   0.26,   0.55,   1.44,
  10,   0.26,   0.67,   1.05,   3.44,
  20,   0.52,   2.76,   1.92,   8.99,
  40,   1.07,  12.1,    3.66,  20.0
)

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
speed_panel <- function(tab, xvar, title, subtitle, xlab, xbreaks, xlabels,
                        vj = NULL) {
  long <- tab %>%
    tidyr::pivot_longer(-dplyr::all_of(xvar), names_to = "cmd",
                        values_to = "sec") %>%
    mutate(cmd = factor(cmd, levels = names(cols)))
  ends <- long %>%
    group_by(cmd) %>% slice_max(.data[[xvar]], n = 1) %>% ungroup() %>%
    mutate(lab = paste0("**", cmd, "** ", sec, "s"),
           vjust = if (is.null(vj)) 0.5
                   else dplyr::coalesce(vj[as.character(cmd)], 0.5))

  ggplot(long, aes(x = .data[[xvar]], y = sec, colour = cmd)) +
    geom_line(linewidth = 1.1) +
    geom_point(size = 2.4) +
    ggtext::geom_richtext(
      data = ends, aes(label = lab, vjust = vjust), hjust = 0,
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
  "Unbalanced panel (15% of rows deleted), T=10, four cohorts",
  "rows in the panel",
  c(8500, 85000, 850000), c("8,500", "85,000", "850,000"),
  vj = c(jwdid = -0.3, lpdid = 0.5, csdid = 1.3))

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
    "Run time of one event-study estimation with clustered standard errors; median of 10 runs. Both axes on log scale.",
    x = 0.012, y = 0.22, hjust = 0, vjust = 0.5, color = gray, size = 12)

foot_grob <- cowplot::ggdraw() +
  cowplot::draw_label(
    paste0("Numbers from the Speed section tables. csdid timed at bal(none), the common-sample choice, with analytical inference;\n",
           "its default (999 bootstrap draws plus uniform bands) adds about a third of a second at one million rows."),
    x = 0.012, y = 0.5, hjust = 0, vjust = 0.5, color = gray, size = 10.5,
    lineheight = 1.2)

combo <- cowplot::plot_grid(title_grob, panels, foot_grob, ncol = 1,
                            rel_heights = c(0.16, 1, 0.11))

ggsave(file.path(outdir, "field-speed.png"), combo,
       width = 13, height = 5.6, dpi = 200, bg = "white")
