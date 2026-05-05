# 03_analyse.R
# Compute the catchment expectation, the cross-regional flow index, and run the
# inferential tests (H1–H4) defined in data/DATA_DICTIONARY.md.
#
# Inputs:  data/processed/{partos_annual, pordata_annual, hospitals}.rds
# Outputs: data/processed/{flow_index, models}.rds; outputs/tables/headline.csv
#
# Methodological notes (these belong in the paper Methods section too):
#
# 1. Capacity proxy.
#    Hospital "capacity" is operationalised as the mean annual delivery volume
#    over a fixed baseline window (default: 2013–2015, the earliest three full
#    years of the SNS dataset). This is a structural proxy, not a licensed-bed
#    count: it captures the realised throughput of a hospital, which already
#    reflects local demand patterns. The choice biases the expected-births
#    formula toward the status quo distribution, which is conservative — any
#    flow index we recover *despite* this conservatism is a lower bound on
#    actual cross-regional movement. Fixed bed counts would be preferable but
#    are not consistently published per-institution per-year.
#
# 2. Catchment expectation.
#    For hospital h in Região de Saúde r in year t:
#       Expected(h, r, t) = TotalBirths(r, t) * Capacity(h) / Σ_{h' ∈ r} Capacity(h')
#    PORDATA reports births by NUTS 2024; we aggregate NUTS II → Região de
#    Saúde via R/region_crosswalk.R (LVT = Oeste e Vale do Tejo + Grande
#    Lisboa + Península de Setúbal under NUTS 2024).
#
# 3. Flow index.
#    flow_index(h, r, t) = Observed(h, r, t) − Expected(h, r, t)
#    Positive: hospital absorbs more deliveries than its regional share alone
#    would explain (cross-regional inflow). Negative: regional residents
#    deliver elsewhere (cross-regional outflow).
#
# 4. Tests (see data/DATA_DICTIONARY.md for the hypotheses).
#    H1: one-sample t-test on flow_index pooled across hospital-years vs μ=0.
#    H3: lme4::lmer(flow_index ~ year + (1 | hospital_id)) — fixed-effect year
#        coefficient tests temporal drift.
#    H4: spdep::moran.test on hospital-level mean flow indices using a
#        k-nearest-neighbour spatial weights matrix from hospital coordinates.
#
# 5. Why mixed effects rather than per-hospital regressions: pooling stabilises
#    estimates for hospitals with sparse panels, and the random intercept
#    encodes the (substantively important) variation in baseline that we are
#    NOT trying to test.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringi)
  library(lme4)
  library(lmerTest)   # adds Satterthwaite p-values to lmer fits
  library(broom)
  library(broom.mixed)
  library(spdep)
})

source(here("R", "region_crosswalk.R"))

# Unicode NFC normalisation: SNS data is composed (ã = 1 codepoint), the
# crosswalk source file may be decomposed (ã = a + combining tilde = 2
# codepoints) depending on editor. Without this, joins on Portuguese region
# names silently produce zero rows.
nfc <- function(x) stri_trans_nfc(x)

proc_dir   <- here("data", "processed")
tables_dir <- here("outputs", "tables")
dir.create(tables_dir, showWarnings = FALSE, recursive = TRUE)

partos_annual  <- readRDS(file.path(proc_dir, "partos_annual.rds")) |>
  mutate(regiao = nfc(regiao))
pordata_annual <- readRDS(file.path(proc_dir, "pordata_annual.rds")) |>
  mutate(region = nfc(region))
hospitals      <- readRDS(file.path(proc_dir, "hospitals.rds")) |>
  mutate(regiao = nfc(regiao))

xwalk <- nuts2_to_regiao_saude |>
  mutate(nuts2 = nfc(nuts2), regiao_saude = nfc(regiao_saude))

baseline_years <- 2013:2015

# ---- Aggregate PORDATA NUTS II totals to Região de Saúde --------------------
region_totals <- pordata_annual |>
  filter(nuts_level == "NUTS II") |>
  inner_join(xwalk, by = c("region" = "nuts2")) |>
  group_by(regiao = regiao_saude, year) |>
  summarise(total_births_region = sum(live_births, na.rm = TRUE),
            .groups = "drop")

# ---- Capacity (baseline mean delivery volume per hospital) ------------------
capacity <- partos_annual |>
  filter(year %in% baseline_years) |>
  group_by(hospital_id, regiao) |>
  summarise(capacity = mean(partos, na.rm = TRUE), .groups = "drop") |>
  filter(capacity > 0)

region_capacity <- capacity |>
  group_by(regiao) |>
  summarise(cap_total = sum(capacity, na.rm = TRUE), .groups = "drop")

# ---- Expected births per (hospital, region, year) ---------------------------
expected <- partos_annual |>
  inner_join(capacity,        by = c("hospital_id", "regiao")) |>
  inner_join(region_capacity, by = "regiao") |>
  inner_join(region_totals,   by = c("regiao", "year")) |>
  mutate(
    expected   = total_births_region * capacity / cap_total,
    flow_index = partos - expected
  )

saveRDS(expected, file.path(proc_dir, "flow_index.rds"))

# ---- H1: one-sample t-test against zero -------------------------------------
h1 <- t.test(expected$flow_index, mu = 0)

# ---- H3: mixed-effects model with year as fixed, hospital as random --------
m_lmer <- lmer(flow_index ~ year + (1 | hospital_id), data = expected,
               REML = FALSE)

# ---- H4: Moran's I on hospital-level mean flow ------------------------------
hospital_means <- expected |>
  group_by(hospital_id) |>
  summarise(mean_flow = mean(flow_index, na.rm = TRUE), .groups = "drop") |>
  inner_join(hospitals, by = "hospital_id") |>
  filter(!is.na(lat), !is.na(lng))

coords <- hospital_means |> select(lng, lat) |> as.matrix()
nb     <- knn2nb(knearneigh(coords, k = 5))
lw     <- nb2listw(nb, style = "W")
h4     <- moran.test(hospital_means$mean_flow, lw)

# ---- H2: urban tertiary centres absorb more than peripheral hospitals ------
# Pre-registered subgroup: hospitals classified as urban tertiary centres in
# Lisboa, Porto, or Coimbra (the three cities the project plan calls out by
# name). Two-sample Wilcoxon (Mann-Whitney) on hospital-level mean flow,
# robust to non-normality given the long left tail visible in the data.
urban_tertiary_pattern <- paste(
  "Centro Hospitalar Universit.rio Lisboa Central",
  "Centro Hospitalar Universit.rio de Lisboa Norte",
  "Centro Hospitalar Universit.rio de Santo Ant.nio",
  "Centro Hospitalar Universit.rio de S.o Jo.o",
  "Centro Hospitalar Universit.rio do Porto",
  "Centro Hospitalar e Universit.rio de Coimbra",
  sep = "|"
)

hospital_means <- hospital_means |>
  mutate(urban_tertiary = grepl(urban_tertiary_pattern, instituicao))

h2 <- wilcox.test(mean_flow ~ urban_tertiary, data = hospital_means,
                  conf.int = TRUE)

# ---- Confidence intervals via broom.mixed for the lmer fit ------------------
lmer_tidy <- broom.mixed::tidy(m_lmer, conf.int = TRUE, effects = "fixed")

# ---- Residual diagnostics for the mixed model -------------------------------
diag_df <- tibble::tibble(
  fitted   = fitted(m_lmer),
  resid    = residuals(m_lmer),
  std_resid = scale(residuals(m_lmer))[, 1]
)

saveRDS(list(h1 = h1, h2 = h2, lmer = m_lmer, lmer_tidy = lmer_tidy,
             h4 = h4, diag = diag_df, hospital_means = hospital_means),
        file.path(proc_dir, "models.rds"))

# ---- Headline numbers for RESULTS.md and the dashboard ----------------------
n_hospitals          <- n_distinct(expected$hospital_id)
share_positive_flow  <- mean(hospital_means$mean_flow > 0) * 100
median_flow          <- median(expected$flow_index, na.rm = TRUE)
iqr_flow             <- IQR(expected$flow_index, na.rm = TRUE)
year_range           <- paste(range(expected$year), collapse = "–")
lmer_year_coef       <- fixef(m_lmer)["year"]

lmer_year_row <- lmer_tidy |> filter(term == "year")
lmer_ci       <- sprintf("[%.2f, %.2f]",
                         lmer_year_row$conf.low, lmer_year_row$conf.high)
n_urban   <- sum(hospital_means$urban_tertiary)
n_other   <- sum(!hospital_means$urban_tertiary)

headline <- tibble::tibble(
  metric = c("n_hospitals", "n_urban_tertiary", "n_other",
             "share_positive_flow", "median_flow", "iqr_flow", "year_range",
             "h1_t", "h1_p",
             "h2_wilcox_W", "h2_p", "h2_diff_estimate", "h2_diff_ci",
             "h3_year_coef", "h3_year_ci", "h3_year_p",
             "h4_moran_I", "h4_moran_p"),
  value  = c(as.character(n_hospitals),
             as.character(n_urban), as.character(n_other),
             sprintf("%.1f", share_positive_flow),
             sprintf("%.1f", median_flow),
             sprintf("%.1f", iqr_flow),
             year_range,
             sprintf("%.3f", h1$statistic),
             format.pval(h1$p.value, digits = 3, eps = 1e-4),
             sprintf("%.0f", h2$statistic),
             format.pval(h2$p.value, digits = 3, eps = 1e-4),
             sprintf("%.1f", h2$estimate),
             sprintf("[%.1f, %.1f]", h2$conf.int[1], h2$conf.int[2]),
             sprintf("%.2f", lmer_year_coef),
             lmer_ci,
             format.pval(lmer_year_row$p.value, digits = 3, eps = 1e-4),
             sprintf("%.3f", h4$estimate["Moran I statistic"]),
             format.pval(h4$p.value, digits = 3, eps = 1e-4))
)
write_csv(headline, file.path(tables_dir, "headline.csv"))

# ---- Console summary --------------------------------------------------------
message("\n=== Headline results ===")
print(headline)
message("\n=== H1: one-sample t-test on flow index ===")
print(h1)
message("\n=== H3: lmer(flow_index ~ year + (1 | hospital_id)) ===")
print(summary(m_lmer))
message("\n=== H4: Moran's I on hospital mean flow (k=5 nearest neighbours) ===")
print(h4)
