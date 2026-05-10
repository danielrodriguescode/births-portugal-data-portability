# 03_analyse.R
# Compute the Mobility metric (Hospital deliveries − Resident births at ULS) and
# run the four hypothesis tests at ULS level.
#
# Inputs:  data/processed/{partos_uls, pordata_uls, hospitals}.rds
# Outputs: data/processed/{mobility_panel, models}.rds
#          outputs/tables/{headline, ppp_panel}.csv
#
# Methodological choices encoded here (all confirmed with the user):
#  - Mobility(uls, t) = HospitalDeliveries(uls, t) − ResidentBirths(uls, t)
#    NO capacity proxy, NO redistribution. Direct comparison of two totals.
#  - 39 ULS form the analytical cohort. Mobility > 0 means the ULS absorbs
#    deliveries from outside its catchment; < 0 means residents deliver
#    elsewhere (other ULS, private hospitals, at home, abroad).
#  - 4 PPPs reported separately (B-i): hospital-level deliveries only, no
#    catchment defined, excluded from H1–H4.
#
# Hypotheses (per data/DATA_DICTIONARY.md):
#  H1 — Mobility ≠ 0 across the 39 ULS (mean per ULS, one-sample t-test).
#  H2 — Urban tertiary ULS (Santa Maria, São José, São João, Santo António,
#       Coimbra) absorb more than peripheral ULS (Wilcoxon two-sample).
#  H3 — Mobility drifts over time (lmerTest::lmer(mobility ~ year + (1|uls))).
#  H4 — Spatial clustering of mean Mobility (Moran's I, k=5 nearest neighbours
#       on ULS polygon centroids).

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringi)
  library(sf)
  library(lme4)
  library(lmerTest)
  library(broom)
  library(broom.mixed)
  library(spdep)
  library(ulsportugal)
})

source(here("R", "region_crosswalk.R"))

proc_dir   <- here("data", "processed")
tables_dir <- here("outputs", "tables")
dir.create(tables_dir, showWarnings = FALSE, recursive = TRUE)

nfc <- function(x) stri_trans_nfc(x)

partos_uls  <- readRDS(file.path(proc_dir, "partos_uls.rds")) |>
  mutate(unit_id = nfc(unit_id))
pordata_uls <- readRDS(file.path(proc_dir, "pordata_uls.rds")) |>
  mutate(uls = nfc(uls))

# ---- 1. Build the mobility panel -------------------------------------------
# Only ULS units have a defined catchment; PPP units are reported separately.
mobility_panel <- partos_uls |>
  filter(type == "ULS") |>
  inner_join(pordata_uls, by = c("unit_id" = "uls", "year")) |>
  mutate(mobility = deliveries - resident_births,
         mobility_ratio = deliveries / resident_births)

ppp_panel <- partos_uls |>
  filter(type == "PPP") |>
  select(unit_id, year, deliveries, cesarianas, n_hospitals)

saveRDS(mobility_panel, file.path(proc_dir, "mobility_panel.rds"))

# ---- 2. H1: one-sample t-test on per-ULS mean mobility ---------------------
# Compute mean mobility per ULS, then test that the distribution of those
# 39 means is centred at 0. This avoids the pseudo-replication of treating
# each (ULS, year) as an independent observation.
uls_means <- mobility_panel |>
  group_by(unit_id) |>
  summarise(mean_mobility       = mean(mobility, na.rm = TRUE),
            mean_mobility_ratio = mean(mobility_ratio, na.rm = TRUE),
            mean_deliveries     = mean(deliveries, na.rm = TRUE),
            mean_resident       = mean(resident_births, na.rm = TRUE),
            .groups = "drop") |>
  mutate(urban_tertiary = unit_id %in% URBAN_TERTIARY_ULS)

h1 <- t.test(uls_means$mean_mobility, mu = 0)

# ---- 3. H2: urban tertiary vs peripheral ULS (Wilcoxon) --------------------
h2 <- wilcox.test(mean_mobility ~ urban_tertiary, data = uls_means,
                  conf.int = TRUE)

# ---- 4. H3: lmer(mobility ~ year + (1 | uls)) ------------------------------
m_lmer <- lmer(mobility ~ year + (1 | unit_id), data = mobility_panel,
               REML = FALSE)
lmer_tidy <- broom.mixed::tidy(m_lmer, conf.int = TRUE, effects = "fixed")

# ---- 5. H4: Moran's I on ULS polygon centroids -----------------------------
uls_map <- ulsportugal() |>
  mutate(NOME_ULS = nfc(NOME_ULS))

centroids <- uls_map |>
  inner_join(uls_means, by = c("NOME_ULS" = "unit_id")) |>
  st_centroid() |>
  st_coordinates()

# spdep accepts coordinates with longitude on x, latitude on y
nb <- knn2nb(knearneigh(centroids, k = 5))
lw <- nb2listw(nb, style = "W")

uls_means_ordered <- uls_map |>
  st_drop_geometry() |>
  inner_join(uls_means, by = c("NOME_ULS" = "unit_id"))

h4 <- moran.test(uls_means_ordered$mean_mobility, lw)

# Moran scatterplot coordinates (standardised x vs spatially-lagged x). Bundled
# into models.rds so the Shiny app can plot H4 without depending on spdep.
moran_x  <- as.numeric(scale(uls_means_ordered$mean_mobility))
moran_y  <- as.numeric(spdep::lag.listw(lw, moran_x))
moran_scatter <- tibble::tibble(
  unit_id = uls_means_ordered$NOME_ULS,
  x       = moran_x,
  y       = moran_y,
  quadrant = dplyr::case_when(
    x >= 0 & y >= 0 ~ "high-high",
    x <  0 & y <  0 ~ "low-low",
    x >= 0 & y <  0 ~ "high-low",
    TRUE            ~ "low-high"
  )
)

# ---- 6. Persist models + diagnostics ---------------------------------------
diag_df <- tibble::tibble(
  fitted     = fitted(m_lmer),
  resid      = residuals(m_lmer),
  std_resid  = scale(residuals(m_lmer))[, 1]
)

saveRDS(list(h1 = h1, h2 = h2, lmer = m_lmer, lmer_tidy = lmer_tidy,
             h4 = h4, moran_scatter = moran_scatter,
             diag = diag_df, uls_means = uls_means,
             ppp_panel = ppp_panel),
        file.path(proc_dir, "models.rds"))

# ---- 7. Headline table -----------------------------------------------------
lmer_year_row <- lmer_tidy |> filter(term == "year")
lmer_ci       <- sprintf("[%.2f, %.2f]",
                         lmer_year_row$conf.low, lmer_year_row$conf.high)

headline <- tibble::tibble(
  metric = c("n_uls", "n_urban_tertiary", "n_peripheral", "n_ppp",
             "year_range",
             "share_positive_mobility",
             "median_uls_mobility", "iqr_uls_mobility",
             "h1_t",   "h1_p", "h1_estimate",  "h1_ci",
             "h2_W",   "h2_p", "h2_diff",      "h2_diff_ci",
             "h3_year_coef", "h3_year_ci", "h3_year_p",
             "h4_moran_I",   "h4_moran_p"),
  value  = c(as.character(nrow(uls_means)),
             as.character(sum(uls_means$urban_tertiary)),
             as.character(sum(!uls_means$urban_tertiary)),
             as.character(nrow(ppp_panel |> distinct(unit_id))),
             paste(range(mobility_panel$year), collapse = "-"),
             sprintf("%.1f", mean(uls_means$mean_mobility > 0) * 100),
             sprintf("%.1f", median(uls_means$mean_mobility)),
             sprintf("%.1f", IQR(uls_means$mean_mobility)),
             sprintf("%.3f", h1$statistic),
             format.pval(h1$p.value, digits = 3, eps = 1e-4),
             sprintf("%.1f", h1$estimate),
             sprintf("[%.1f, %.1f]", h1$conf.int[1], h1$conf.int[2]),
             sprintf("%.0f", h2$statistic),
             format.pval(h2$p.value, digits = 3, eps = 1e-4),
             sprintf("%.1f", h2$estimate),
             sprintf("[%.1f, %.1f]", h2$conf.int[1], h2$conf.int[2]),
             sprintf("%.2f", lmer_year_row$estimate),
             lmer_ci,
             format.pval(lmer_year_row$p.value, digits = 3, eps = 1e-4),
             sprintf("%.3f", h4$estimate["Moran I statistic"]),
             format.pval(h4$p.value, digits = 3, eps = 1e-4))
)
write_csv(headline, file.path(tables_dir, "headline.csv"))

# ---- 8. Persist the PPP panel as a separate CSV (reported in limitations) --
write_csv(ppp_panel, file.path(tables_dir, "ppp_panel.csv"))

# ---- 9. Console summary ----------------------------------------------------
message("\n=== Headline ===")
print(headline)

message("\n=== Per-ULS mean mobility (sorted) ===")
print(uls_means |>
        arrange(desc(mean_mobility)) |>
        select(unit_id, mean_mobility, urban_tertiary), n = Inf)

message("\n=== H1: t-test on per-ULS mean mobility ===")
print(h1)

message("\n=== H3: lmer fixed effects ===")
print(lmer_tidy)

message("\n=== H4: Moran's I on ULS centroid weights (k=5) ===")
print(h4)
