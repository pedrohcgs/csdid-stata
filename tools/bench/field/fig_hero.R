#------------------------------------------------------------------------------
# Hero figure for the csdid-against-the-field guide
#
# Reads the per-replication estimates written by figdata.do (unequal period
# sampling design, event time 0) and draws a two-panel figure in the style of
# the DR-with-weak-overlap / DDD papers: ridge densities of the estimates on
# the left, zipper plots of the confidence intervals on the right.
#
# Inputs : figdata.csv           (regime,pkg,rep,h,est,se)
# Outputs: <outdir>/field-hero-varmiss.png
#          figcheck.csv          (bias and coverage per command, for the gate)
#
# Usage  : Rscript fig_hero.R [infile] [outdir]
#------------------------------------------------------------------------------
rm(list = ls())

library(ggplot2)
library(ggridges)
library(ggtext)
library(cowplot)
library(ggplotify)
library(dplyr)
library(tibble)
library(grid)

#------------------------------------------------------------------------------
# Set parameters
#------------------------------------------------------------------------------
args    <- commandArgs(trailingOnly = TRUE)
infile  <- ifelse(length(args) >= 1, args[1], "figdata.csv")
outdir  <- ifelse(length(args) >= 2, args[2], ".")
h_sel   <- 0          # event time shown in the figure
truth   <- 2.0        # population ES(0) in the Reliability I designs
z95     <- qnorm(0.975)

navy <- "#012169"
gray <- "#525252"

# display labels and colors, in the order of the published table (top first)
pkg_meta <- tribble(
  ~pkg,       ~label,                  ~color,
  "csdid",    "csdid",                 "#1e40af",
  "jwdid",    "jwdid",                 "#d97706",
  "jwdid_uc", "jwdid uncond*",         "#b45309",
  "bjs",      "did_imputation",        "#b91c1c",
  "bjs_wtr",  "did_imputation wtr*",   "#15803d",
  "dcdh",     "did_multiplegt_dyn",    "#7c3aed",
  "lpdid",    "lpdid",                 "#6b7280",
  "lpdid_rw", "lpdid rw*",             "#334155",
  "sa",       "eventstudyinteract",    "#be185d"
)
pkg_meta <- pkg_meta %>%
  filter(!pkg %in% c("jwdid_uc", "bjs_wtr", "lpdid_rw"))
est_colors <- setNames(pkg_meta$color, pkg_meta$label)

#------------------------------------------------------------------------------
# Theme (theme_dr_paper, trimmed)
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
# Load, restrict to the plotted horizon, compute the summary used by the gate
#------------------------------------------------------------------------------
raw <- read.csv(infile, stringsAsFactors = FALSE)

dat <- raw %>%
  filter(h == h_sel, !is.na(est), !is.na(se)) %>%
  inner_join(pkg_meta, by = "pkg") %>%
  mutate(
    label = factor(label, levels = rev(pkg_meta$label)),  # csdid on top
    lower = est - z95 * se,
    upper = est + z95 * se,
    cover = lower <= truth & truth <= upper
  )

summ <- dat %>%
  group_by(label) %>%
  summarise(reps = n(), bias = mean(est) - truth,
            coverage = mean(cover), .groups = "drop") %>%
  arrange(desc(label))

write.csv(summ, "figcheck.csv", row.names = FALSE)

# shared horizontal scale so the two panels can be read against each other
xlims <- range(c(dat$lower, dat$upper, dat$est))

#------------------------------------------------------------------------------
# Left panel: ridge densities of the estimates
#------------------------------------------------------------------------------
ridge_p <- ggplot(dat, aes(x = est, y = label, fill = label)) +
  geom_density_ridges(alpha = 0.85, rel_min_height = 0.01, scale = 1.35) +
  geom_vline(xintercept = truth, colour = navy, linewidth = 1,
             linetype = "dashed") +
  scale_fill_manual(values = est_colors) +
  scale_y_discrete(expand = c(0, 0.2)) +
  coord_cartesian(xlim = xlims, clip = "off") +
  labs(title = "Where the estimates land",
       subtitle = "Density of the 500 estimates at e=0",
       x = NULL, y = NULL) +
  theme_fig() +
  theme(axis.text.y = element_text(color = navy, face = "bold", size = 11),
        plot.margin = margin(15, 12, 10, 10))

#------------------------------------------------------------------------------
# Right panel: zipper plot of the confidence intervals
#------------------------------------------------------------------------------
html_lab <- setNames(
  paste0("<span style='color:", pkg_meta$color, "'>**", pkg_meta$label,
         "**</span>"),
  pkg_meta$label)

zdat <- dat %>%
  mutate(
    flabel     = factor(html_lab[as.character(label)],
                        levels = html_lab),               # csdid strip on top
    draw_col   = ifelse(cover, est_colors[as.character(label)], "#000000"),
    draw_alpha = ifelse(cover, 0.45, 0.65)
  )

cov_anno <- summ %>%
  mutate(flabel = factor(html_lab[as.character(label)], levels = html_lab),
         run = -Inf, y_pos = Inf,
         lab = paste0("bias ", sprintf("%+.2f", bias), " &middot; coverage ",
                      formatC(100 * coverage, format = "f", digits = 0), "%"))

zip_base <- ggplot(zdat, aes(x = rep)) +
  geom_linerange(aes(ymin = lower, ymax = upper,
                     colour = draw_col, alpha = draw_alpha),
                 linewidth = 0.35, show.legend = FALSE) +
  geom_hline(yintercept = truth, colour = navy, linetype = "dashed",
             linewidth = 0.8) +
  facet_grid(flabel ~ ., switch = "y") +
  scale_colour_identity() +
  scale_alpha_identity() +
  coord_flip() +
  scale_y_continuous(limits = xlims) +
  labs(title = "Whether the intervals cover the truth",
       subtitle = "One 95% confidence interval per sample; black = does not cover the truth",
       x = NULL, y = NULL) +
  theme_fig() +
  ggtext::geom_richtext(
    data = cov_anno, aes(x = run, y = y_pos, label = lab),
    inherit.aes = FALSE, hjust = 1, vjust = 0,
    fill = alpha("white", 0.85), label.color = NA,
    label.padding = unit(c(1, 3, 1, 3), "pt"),
    color = navy, size = 3.0) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.spacing.y    = unit(2, "pt"),
    strip.text.y.left  = ggtext::element_markdown(angle = 0, vjust = 0.5,
                                                  hjust = 0, size = 9),
    strip.placement    = "outside",
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    plot.margin        = margin(15, 10, 10, 6)
  )

zip_p <- zip_base

#------------------------------------------------------------------------------
# Assemble: title block on top, panels, source note at the bottom
#------------------------------------------------------------------------------
panels <- cowplot::plot_grid(ridge_p, zip_p, ncol = 2, rel_widths = c(1, 1.15))

title_grob <- cowplot::ggdraw() +
  cowplot::draw_label(
    "Event-study estimates under unequal sampling across periods",
    x = 0.012, y = 0.80, hjust = 0, vjust = 0.5, color = navy,
    fontface = "bold", size = 19) +
  cowplot::draw_label(
    paste0("Staggered DiD with no covariates: 1,000 units, 7 periods, three treated cohorts plus a never-treated group; 500 simulated samples.\n",
           "Each period keeps a different share of its units (45% to 95%), independent of everything else. Truth at e=0 is 2. Every command at its default."),
    x = 0.012, y = 0.30, hjust = 0, vjust = 0.5, color = gray, size = 12,
    lineheight = 1.15)

foot_grob <- cowplot::ggdraw() +
  cowplot::draw_label(
    paste0("Same data-generating process and seeds as the Reliability I tables. Biases flip sign with the horizon (the imputation commands move from\n",
           "-0.16 at e=0 to +0.23 at e=2), so averaging across horizons would cancel misses rather than reveal them. Non-default options are discussed in the text."),
    x = 0.012, y = 0.55, hjust = 0, vjust = 0.5, color = gray, size = 10.5,
    lineheight = 1.2)

combo <- cowplot::plot_grid(title_grob, panels, foot_grob, ncol = 1,
                            rel_heights = c(0.155, 1, 0.085))

ggsave(file.path(outdir, "field-hero-varmiss.png"), combo,
       width = 13, height = 7.6, dpi = 200, bg = "white")
