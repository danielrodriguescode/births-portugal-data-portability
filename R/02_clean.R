# 02_clean.R
# Build the analytical panel at ULS / pseudo-ULS level.
#
# Inputs:  data/processed/{raw_partos, raw_pordata}.rds
# Outputs: data/processed/
#            hospitals.rds       # one row per SNS institution (cols: instituicao, regiao, lat, lng, hospital_id, ppp_flag, NOME_ULS)
#            partos_uls.rds      # one row per (unit_id, year): hospital deliveries aggregated to unit
#            pordata_uls.rds     # one row per (uls, year): resident births aggregated from PORDATA municípios
#            crosswalk_concelho_uls.rds   # auditable concelho→ULS share table
#
# Methodological choices encoded here (all confirmed with the user):
#  - Time window: 2014–2024 (10 years).
#  - Drop years whose latest reported month is not December (filters partial 2026).
#  - Madeira and Açores excluded (outside Continental SNS).
#  - SNS monthly counters are CUMULATIVE year-to-date; annual total = December.
#  - Hospital identity:
#       - Non-PPP: spatial join lat/lng → ULS polygon (point-in-polygon via sf::st_within).
#                  All hospitals falling in the same ULS are aggregated into ONE unit
#                  (this consolidates the 2024 CHU→ULS rename automatically).
#       - PPP: each PPP is its own pseudo-ULS (5 hospitals: Cascais, Loures PPP,
#              Braga PPP, Vila Franca de Xira PPP, Sintra-Hospital Beatriz Ângelo).
#              No defined catchment; no ResidentBirths; reported separately.
#  - PORDATA Concelho → ULS crosswalk:
#       - 275 concelhos map 1:1.
#       - 3 split concelhos (Lisboa / Loures / Porto) allocated proportionally to
#         the number of freguesias the ulsportugal package assigns to each ULS.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(janitor)
  library(lubridate)
  library(stringi)
  library(stringr)
  library(sf)
  library(ulsportugal)
})

source(here("R", "region_crosswalk.R"))

proc_dir <- here("data", "processed")
nfc <- function(x) stri_trans_nfc(x)

partos_raw  <- readRDS(file.path(proc_dir, "raw_partos.rds"))
pordata_raw <- readRDS(file.path(proc_dir, "raw_pordata.rds"))

YEARS <- 2014:2024

# ---- 1. Concelho → ULS crosswalk -------------------------------------------
crosswalk <- build_concelho_uls_crosswalk()
saveRDS(crosswalk, file.path(proc_dir, "crosswalk_concelho_uls.rds"))

# ---- 2. PORDATA: Município × year → ULS ------------------------------------
mun_label <- nfc("Município")
year_labels <- as.integer(unlist(pordata_raw[6, 3:21]))

# Slice the Total block (cols 1, 2, 3..21) and rename the year columns
total_block <- pordata_raw[7:nrow(pordata_raw), c(1, 2, 3:21)]
names(total_block) <- c("nuts_level", "concelho", as.character(year_labels))

pordata_long <- total_block |>
  mutate(nuts_level = nfc(as.character(nuts_level)),
         concelho   = nfc(as.character(concelho))) |>
  filter(nuts_level == mun_label, !is.na(concelho)) |>
  select(-nuts_level) |>
  mutate(across(-concelho, as.character)) |>
  pivot_longer(-concelho, names_to = "year", values_to = "live_births") |>
  mutate(year = as.integer(year),
         live_births = suppressWarnings(as.integer(live_births))) |>
  filter(!is.na(live_births), year %in% YEARS)

pordata_uls <- pordata_long |>
  inner_join(crosswalk, by = c("concelho" = "Concelho")) |>
  mutate(allocated_births = live_births * share) |>
  group_by(NOME_ULS, year) |>
  summarise(resident_births = sum(allocated_births), .groups = "drop") |>
  rename(uls = NOME_ULS) |>
  mutate(uls = nfc(uls))

saveRDS(pordata_uls, file.path(proc_dir, "pordata_uls.rds"))

# ---- 3. SNS partos: month → year, identify PPPs, spatial join → ULS --------
partos <- partos_raw |>
  clean_names() |>
  mutate(periodo     = nfc(as.character(periodo)),
         regiao      = nfc(as.character(regiao)),
         instituicao = nfc(as.character(instituicao)),
         date        = ym(periodo),
         year        = year(date)) |>
  separate(localizacao_geografica, into = c("lat", "lng"),
           sep = ",\\s*", convert = TRUE)

# Drop partial years (latest reported month != December)
complete_years <- partos |>
  group_by(year) |>
  summarise(latest_month = max(date), .groups = "drop") |>
  filter(month(latest_month) == 12) |>
  pull(year)
partos <- partos |> filter(year %in% intersect(complete_years, YEARS))

# Distinct hospital list with PPP flag
hospitals <- partos |>
  group_by(instituicao, regiao) |>
  slice_max(date, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(instituicao, regiao, lat, lng,
            ppp_flag = grepl(",\\s*PPP$", instituicao)) |>
  arrange(instituicao, regiao) |>
  mutate(hospital_id = paste0("H", sprintf("%04d", row_number())))

# Match each hospital to a ULS:
#  1. Direct name match for hospitals named exactly after a ULS (handles
#     coordinate-precision issues — e.g. SNS reports Santa Maria's lng as -9.0
#     which falls outside the ULS polygon).
#  2. Spatial join (st_within) for everything else (CHUs, generic hospitals).
#  3. PPPs are flagged but still receive a NOME_ULS from the spatial join, so
#     they can be displayed on the map; the panel logic uses ppp_flag to keep
#     them as separate units.
uls_map <- ulsportugal() |>
  mutate(NOME_ULS   = nfc(NOME_ULS),
         NOME_CURTO = nfc(NOME_CURTO))

uls_lookup <- uls_map |> st_drop_geometry() |> as_tibble()

hospitals_named <- hospitals |>
  inner_join(uls_lookup, by = c("instituicao" = "NOME_ULS")) |>
  rename(NOME_ULS = instituicao) |>
  mutate(instituicao = NOME_ULS)

hospitals_sf <- hospitals |>
  anti_join(hospitals_named, by = "hospital_id") |>
  filter(!is.na(lat), !is.na(lng)) |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326, remove = FALSE) |>
  st_join(uls_map |> select(NOME_ULS, NOME_CURTO), join = st_within) |>
  st_drop_geometry() |>
  as_tibble()

# Reattach NOME_ULS / NOME_CURTO to the hospitals table by hospital_id
match_table <- bind_rows(
  hospitals_named |> select(hospital_id, NOME_ULS, NOME_CURTO),
  hospitals_sf |> select(hospital_id, NOME_ULS, NOME_CURTO)
)

hospitals <- hospitals |>
  left_join(match_table, by = "hospital_id")

saveRDS(hospitals, file.path(proc_dir, "hospitals.rds"))

# Annual hospital totals (December value)
partos_hospital_year <- partos |>
  inner_join(hospitals |> select(instituicao, regiao, hospital_id, ppp_flag,
                                  NOME_ULS),
             by = c("instituicao", "regiao")) |>
  group_by(hospital_id, instituicao, ppp_flag, NOME_ULS, year) |>
  slice_max(date, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(hospital_id, instituicao, ppp_flag, NOME_ULS, year,
            partos     = no_total_de_partos,
            cesarianas = no_cesarianas)

# Build the analytical panel:
#   - Non-PPP: aggregate by (NOME_ULS, year)  → unit_id = NOME_ULS,  type = "ULS"
#   - PPP: keep separate                       → unit_id = instituicao, type = "PPP"
panel_uls <- partos_hospital_year |>
  filter(!ppp_flag, !is.na(NOME_ULS)) |>
  group_by(unit_id = NOME_ULS, year) |>
  summarise(deliveries = sum(partos, na.rm = TRUE),
            cesarianas = sum(cesarianas, na.rm = TRUE),
            n_hospitals = n(),
            .groups = "drop") |>
  mutate(type = "ULS")

panel_ppp <- partos_hospital_year |>
  filter(ppp_flag) |>
  group_by(unit_id = instituicao, year) |>
  summarise(deliveries = sum(partos, na.rm = TRUE),
            cesarianas = sum(cesarianas, na.rm = TRUE),
            n_hospitals = n(),
            .groups = "drop") |>
  mutate(type = "PPP")

partos_uls <- bind_rows(panel_uls, panel_ppp)
saveRDS(partos_uls, file.path(proc_dir, "partos_uls.rds"))

# ---- 4. Diagnostics --------------------------------------------------------
message("\n=== Pipeline diagnostics ===")
message("Years covered: ", paste(range(partos_hospital_year$year), collapse = "–"))
message("Total SNS hospitals: ", nrow(hospitals),
        " (", sum(hospitals$ppp_flag), " PPPs)")
message("Hospitals with no ULS spatial match: ",
        sum(is.na(hospitals$NOME_ULS) & !hospitals$ppp_flag))
message("ULS in panel: ", n_distinct(panel_uls$unit_id),
        "  PPP units: ", n_distinct(panel_ppp$unit_id))
message("PORDATA ULS-years: ", nrow(pordata_uls))
