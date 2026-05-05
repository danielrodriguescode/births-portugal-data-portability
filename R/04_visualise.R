# 04_visualise.R
# Produce the static figures referenced by paper/paper.Rmd into outputs/figures/.
# Inputs:  data/processed/{partos_annual, pordata_annual, hospitals, flow_index}.rds
# Outputs: outputs/figures/*.png

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(ggplot2)
  library(forcats)
  library(stringi)
})

proc_dir <- here("data", "processed")
fig_dir  <- here("outputs", "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

nfc <- function(x) stri_trans_nfc(x)

partos_annual <- readRDS(file.path(proc_dir, "partos_annual.rds")) |>
  mutate(regiao = nfc(regiao))
flow          <- readRDS(file.path(proc_dir, "flow_index.rds")) |>
  mutate(regiao = nfc(regiao))

# Figure 1 — annual deliveries by Região de Saúde
fig1 <- partos_annual |>
  group_by(regiao, year) |>
  summarise(partos = sum(partos, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(year, partos, colour = regiao)) +
  geom_line(linewidth = 0.8) +
  scale_y_continuous(labels = scales::comma) +
  labs(x = NULL, y = "Annual SNS deliveries", colour = NULL,
       title = "Annual SNS deliveries by Região de Saúde",
       subtitle = "Source: Transparência SNS, Partos e Cesarianas") +
  theme_minimal()

ggsave(file.path(fig_dir, "fig01_deliveries_by_region.png"),
       fig1, width = 9, height = 5, dpi = 300)

# Figure 2 — caesarean rate by Região de Saúde
fig2 <- partos_annual |>
  group_by(regiao, year) |>
  summarise(caesarean_rate = sum(cesarianas) / sum(partos), .groups = "drop") |>
  ggplot(aes(year, caesarean_rate, colour = regiao)) +
  geom_line(linewidth = 0.8) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = NULL, y = "Caesarean rate", colour = NULL,
       title = "Caesarean section rate by Região de Saúde",
       subtitle = "Source: Transparência SNS, Partos e Cesarianas") +
  theme_minimal()

ggsave(file.path(fig_dir, "fig02_caesarean_rate.png"),
       fig2, width = 9, height = 5, dpi = 300)

# Figure 3 — observed vs expected per hospital-year
fig3 <- flow |>
  ggplot(aes(expected, partos, colour = regiao)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "dashed") +
  geom_point(alpha = 0.6) +
  scale_x_continuous(labels = scales::comma) +
  scale_y_continuous(labels = scales::comma) +
  labs(x = "Expected deliveries (capacity-weighted regional share)",
       y = "Observed deliveries",
       colour = NULL,
       title = "Observed vs expected deliveries per hospital-year",
       subtitle = "Points above the dashed line: hospital absorbs more than its capacity share predicts") +
  theme_minimal()

ggsave(file.path(fig_dir, "fig03_observed_vs_expected.png"),
       fig3, width = 9, height = 6, dpi = 300)

# Figure 4 — distribution of mean flow index per hospital
hospital_means <- flow |>
  group_by(hospital_id, instituicao, regiao) |>
  summarise(mean_flow = mean(flow_index, na.rm = TRUE), .groups = "drop")

fig4 <- hospital_means |>
  mutate(instituicao = fct_reorder(instituicao, mean_flow)) |>
  ggplot(aes(mean_flow, instituicao, fill = regiao)) +
  geom_col() +
  geom_vline(xintercept = 0, colour = "grey20") +
  labs(x = "Mean flow index (observed − expected, deliveries/year)",
       y = NULL, fill = NULL,
       title = "Cross-regional flow index by hospital, averaged over 2013–2023",
       subtitle = "Right of zero: net inflow (absorbs from outside region). Left: net outflow.") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 7))

ggsave(file.path(fig_dir, "fig04_flow_by_hospital.png"),
       fig4, width = 11, height = 9, dpi = 300)

message("Wrote 4 figures to ", fig_dir)
