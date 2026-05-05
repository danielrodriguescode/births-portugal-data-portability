# 04_visualise.R
# Produce the static figures referenced by paper/paper.Rmd into outputs/figures/.
# Inputs:  data/processed/{partos_uls, pordata_uls, mobility_panel, models}.rds
# Outputs: outputs/figures/*.png

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(ggplot2)
  library(forcats)
  library(stringi)
  library(sf)
  library(scales)
  library(ulsportugal)
})

source(here("R", "region_crosswalk.R"))

proc_dir <- here("data", "processed")
fig_dir  <- here("outputs", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

nfc <- function(x) stri_trans_nfc(x)

partos_uls   <- readRDS(file.path(proc_dir, "partos_uls.rds")) |>
  mutate(unit_id = nfc(unit_id))
pordata_uls  <- readRDS(file.path(proc_dir, "pordata_uls.rds")) |>
  mutate(uls = nfc(uls))
mobility     <- readRDS(file.path(proc_dir, "mobility_panel.rds")) |>
  mutate(unit_id = nfc(unit_id))
models       <- readRDS(file.path(proc_dir, "models.rds"))
uls_means    <- models$uls_means

uls_map      <- ulsportugal() |> mutate(NOME_ULS = nfc(NOME_ULS),
                                        NOME_CURTO = nfc(NOME_CURTO))

# ---- Figure 1 — Annual SNS deliveries by ULS (top 10) ----------------------
top10_deliveries <- partos_uls |>
  filter(type == "ULS") |>
  group_by(unit_id) |>
  summarise(total = sum(deliveries), .groups = "drop") |>
  slice_max(total, n = 10) |>
  pull(unit_id)

short_names <- uls_map |>
  st_drop_geometry() |>
  as_tibble() |>
  select(NOME_ULS, NOME_CURTO)

fig1 <- partos_uls |>
  filter(type == "ULS", unit_id %in% top10_deliveries) |>
  left_join(short_names, by = c("unit_id" = "NOME_ULS")) |>
  ggplot(aes(year, deliveries, colour = NOME_CURTO)) +
  geom_line(linewidth = 0.7) +
  scale_y_continuous(labels = comma) +
  labs(x = NULL, y = "Annual SNS deliveries", colour = NULL,
       title = "Annual SNS deliveries — top 10 ULS by total volume",
       subtitle = "Source: Transparência SNS, Partos e Cesarianas (2014–2024)") +
  theme_minimal()
ggsave(file.path(fig_dir, "fig01_deliveries_top10_uls.png"),
       fig1, width = 9, height = 5, dpi = 300)

# ---- Figure 2 — National caesarean rate by year (SNS only) -----------------
fig2 <- partos_uls |>
  filter(type == "ULS") |>
  group_by(year) |>
  summarise(rate = sum(cesarianas) / sum(deliveries), .groups = "drop") |>
  ggplot(aes(year, rate)) +
  geom_line(linewidth = 0.8, colour = "#2166ac") +
  geom_point() +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0.25, 0.40)) +
  labs(x = NULL, y = "Caesarean section rate",
       title = "National caesarean rate, SNS hospitals only",
       subtitle = "Source: Transparência SNS (2014–2024)") +
  theme_minimal()
ggsave(file.path(fig_dir, "fig02_caesarean_rate_national.png"),
       fig2, width = 8, height = 5, dpi = 300)

# ---- Figure 3 — Mobility per ULS, ordered ----------------------------------
fig3 <- uls_means |>
  left_join(short_names, by = c("unit_id" = "NOME_ULS")) |>
  mutate(NOME_CURTO = fct_reorder(NOME_CURTO, mean_mobility),
         category   = ifelse(urban_tertiary, "Urban tertiary",
                             "Peripheral / district")) |>
  ggplot(aes(mean_mobility, NOME_CURTO, fill = category)) +
  geom_col() +
  geom_vline(xintercept = 0, colour = "grey30") +
  scale_x_continuous(labels = comma) +
  scale_fill_manual(values = c("Urban tertiary" = "#b2182b",
                                "Peripheral / district" = "#1f78b4")) +
  labs(x = "Mean mobility (deliveries − resident births, per year)",
       y = NULL, fill = NULL,
       title = "Mobility by ULS, averaged over 2014–2024",
       subtitle = "Right of zero: net inflow. Left: net outflow.") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8),
        legend.position = "top")
ggsave(file.path(fig_dir, "fig03_mobility_by_uls.png"),
       fig3, width = 10, height = 9, dpi = 300)

# ---- Figure 4 — Hospital deliveries vs resident births per ULS-year --------
fig4 <- mobility |>
  left_join(short_names, by = c("unit_id" = "NOME_ULS")) |>
  ggplot(aes(resident_births, deliveries,
             colour = unit_id %in% URBAN_TERTIARY_ULS)) +
  geom_abline(slope = 1, intercept = 0,
              colour = "grey60", linetype = "dashed") +
  geom_point(alpha = 0.6, size = 2) +
  scale_x_continuous(labels = comma) +
  scale_y_continuous(labels = comma) +
  scale_colour_manual(values = c("TRUE" = "#b2182b", "FALSE" = "#1f78b4"),
                      labels = c("Peripheral / district", "Urban tertiary"),
                      name = NULL) +
  labs(x = "Resident births (PORDATA, attributed to ULS via concelho)",
       y = "Hospital deliveries (Transparência SNS)",
       title = "Hospital deliveries vs resident births per ULS × year",
       subtitle = "Above the line: net inflow. Below: net outflow.") +
  theme_minimal()
ggsave(file.path(fig_dir, "fig04_deliveries_vs_residents.png"),
       fig4, width = 9, height = 6, dpi = 300)

# ---- Figure 5 — Mobility heatmap (ULS × year) ------------------------------
fig5_data <- mobility |>
  left_join(short_names, by = c("unit_id" = "NOME_ULS")) |>
  group_by(unit_id, NOME_CURTO) |>
  mutate(overall = mean(mobility)) |>
  ungroup() |>
  mutate(NOME_CURTO = fct_reorder(NOME_CURTO, overall))

fig5 <- ggplot(fig5_data, aes(year, NOME_CURTO, fill = mobility)) +
  geom_tile(colour = "white") +
  scale_fill_gradient2(low = "#b2182b", mid = "#f7f7f7", high = "#2166ac",
                       midpoint = 0, labels = comma) +
  labs(x = NULL, y = NULL, fill = "Mobility",
       title = "Mobility per ULS × year",
       subtitle = "Blue = net inflow; red = net outflow.") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 7),
        legend.position = "right")
ggsave(file.path(fig_dir, "fig05_mobility_heatmap.png"),
       fig5, width = 11, height = 9, dpi = 300)

# ---- Figure 6 — Choropleth of mean mobility on ULS polygons ---------------
choro_df <- uls_map |>
  inner_join(uls_means, by = c("NOME_ULS" = "unit_id"))

fig6 <- ggplot(choro_df) +
  geom_sf(aes(fill = mean_mobility), colour = "white", linewidth = 0.2) +
  scale_fill_gradient2(low = "#b2182b", mid = "#f7f7f7", high = "#2166ac",
                       midpoint = 0, labels = comma, name = "Mean\nmobility") +
  labs(title = "Mobility by ULS — Continental Portugal",
       subtitle = "Mean over 2014–2024. Blue = net inflow; red = net outflow.") +
  theme_void()
ggsave(file.path(fig_dir, "fig06_mobility_choropleth.png"),
       fig6, width = 8, height = 9, dpi = 300)

# ---- Figure 7a/b — lmer residual diagnostics ------------------------------
diag_df <- models$diag

fig7a <- ggplot(diag_df, aes(fitted, resid)) +
  geom_point(alpha = 0.4) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_smooth(method = "loess", se = FALSE, colour = "tomato",
              formula = y ~ x) +
  labs(x = "Fitted", y = "Residual",
       title = "Residuals vs fitted (lmer)",
       subtitle = "H3 model: mobility ~ year + (1 | ULS)") +
  theme_minimal()
ggsave(file.path(fig_dir, "fig07a_lmer_resid_vs_fitted.png"),
       fig7a, width = 7, height = 5, dpi = 300)

fig7b <- ggplot(diag_df, aes(sample = std_resid)) +
  stat_qq(alpha = 0.4) +
  stat_qq_line(colour = "tomato") +
  labs(x = "Theoretical quantiles", y = "Standardised residuals",
       title = "Q-Q plot of standardised residuals (lmer)") +
  theme_minimal()
ggsave(file.path(fig_dir, "fig07b_lmer_qq.png"),
       fig7b, width = 6, height = 5, dpi = 300)

# ---- Figure 8 — H2 box+strip: urban tertiary vs peripheral ----------------
fig8_df <- uls_means |>
  mutate(group = ifelse(urban_tertiary,
                        "Urban tertiary (n=6)",
                        "Peripheral / district (n=33)"))

fig8 <- ggplot(fig8_df, aes(group, mean_mobility, colour = group)) +
  geom_boxplot(outlier.shape = NA, fill = NA) +
  geom_jitter(width = 0.15, alpha = 0.8, size = 2) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = comma) +
  labs(x = NULL, y = "Mean mobility per ULS",
       title = "H2: do urban tertiary ULS absorb more cross-regional patients?",
       subtitle = sprintf("Wilcoxon W = %.0f, p = %.3f",
                          models$h2$statistic, models$h2$p.value)) +
  theme_minimal() +
  theme(legend.position = "none")
ggsave(file.path(fig_dir, "fig08_h2_urban_vs_peripheral.png"),
       fig8, width = 8, height = 5, dpi = 300)

message("Wrote 9 figures to ", fig_dir)
