# 04_visualise.R
# Produce every static figure referenced by paper/paper.Rmd into outputs/figures/.
# Inputs:  data/processed/*.rds
# Outputs: outputs/figures/*.png (and .pdf where vector is preferred)

library(here)
library(dplyr)
library(ggplot2)

proc_dir <- here("data", "processed")
fig_dir  <- here("outputs", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

partos_annual <- readRDS(file.path(proc_dir, "partos_annual.rds"))

# Figure 1 — annual delivery volume by Região de Saúde
fig1 <- partos_annual |>
  group_by(regiao, year) |>
  summarise(partos = sum(partos, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(year, partos, colour = regiao)) +
  geom_line(linewidth = 0.8) +
  labs(x = NULL, y = "Annual deliveries", colour = NULL,
       title = "Annual deliveries by Região de Saúde") +
  theme_minimal()

ggsave(file.path(fig_dir, "fig01_deliveries_by_region.png"),
       fig1, width = 8, height = 5, dpi = 300)

# Additional figures (catchment map, flow heatmap, observed-vs-expected) wire in
# once 03_analyse.R produces flow_index.rds.
