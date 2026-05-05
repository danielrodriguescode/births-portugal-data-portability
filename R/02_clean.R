# 02_clean.R
# Standardise variables, build the hospital × year panel, harmonise region codes.
# Inputs:  data/processed/raw_partos.rds, raw_pordata.rds
# Outputs: data/processed/partos_annual.rds, pordata_annual.rds, hospitals.rds

library(here)
library(dplyr)
library(tidyr)
library(janitor)
library(lubridate)
library(stringr)

proc_dir <- here("data", "processed")

partos_raw  <- readRDS(file.path(proc_dir, "raw_partos.rds"))
pordata_raw <- readRDS(file.path(proc_dir, "raw_pordata.rds"))

# ---- Partos e Cesarianas -----------------------------------------------------
# Columns: período (YYYY-MM), região, instituição, localização geográfica ("lat, lng"),
# nº total de partos, nº cesarianas. Aggregate monthly → annual to align with PORDATA.

partos <- partos_raw |>
  clean_names() |>
  mutate(
    date = ym(periodo),
    year = year(date)
  ) |>
  separate(localizacao_geografica, into = c("lat", "lng"), sep = ",\\s*", convert = TRUE)

hospitals <- partos |>
  distinct(instituicao, regiao, lat, lng) |>
  mutate(hospital_id = paste0("H", sprintf("%04d", row_number())))

partos_annual <- partos |>
  inner_join(hospitals, by = c("instituicao", "regiao", "lat", "lng")) |>
  group_by(hospital_id, instituicao, regiao, year) |>
  summarise(
    partos     = sum(no_total_de_partos, na.rm = TRUE),
    cesarianas = sum(no_cesarianas,      na.rm = TRUE),
    .groups = "drop"
  )

# ---- PORDATA -----------------------------------------------------------------
# Layout (sheet "Quadro" of pordata.xlsx, confirmed empirically):
#   Rows 1-5  metadata (title, subtitle, units)
#   Row  4    "Territórios" in col 1
#   Row  5    "Total" at col 3, "Masculino" at col 22, "Feminino" at col 41
#             (i.e. the table is repeated three times across columns)
#   Row  6    col 1 = "Âmbito Geográfico", col 2 = "Anos",
#             cols 3..21 = years 1981, 1995, 2001, 2009..2024  (Total block)
#             cols 22..40 = same years for Masculino, 41..59 for Feminino, etc.
#   Row  7+   data; col 1 = NUTS level ("NUTS II", "NUTS III", "Município", ...),
#             col 2 = region/territory name, cols 3..21 = live births.
# We only need the Total block (cols 1,2,3..21) at NUTS II / NUTS III granularity.

# Re-read raw to recover full layout (raw_pordata.rds was a quick first pass).
pordata_full <- readxl::read_excel(
  here::here("data", "raw", "pordata.xlsx"),
  sheet = 1, col_names = FALSE, .name_repair = "minimal"
)

year_labels  <- as.integer(unlist(pordata_full[6, 3:21]))
total_block  <- pordata_full[7:nrow(pordata_full), c(1, 2, 3:21)]
names(total_block) <- c("nuts_level", "region", as.character(year_labels))

pordata_annual <- total_block |>
  filter(nuts_level %in% c("NUTS II", "NUTS III")) |>
  mutate(across(-c(nuts_level, region), as.character)) |>  # PORDATA mixes "..." sentinels with numbers
  pivot_longer(
    cols      = -c(nuts_level, region),
    names_to  = "year",
    values_to = "live_births"
  ) |>
  mutate(
    year        = as.integer(year),
    live_births = suppressWarnings(as.integer(live_births))
  ) |>
  filter(!is.na(live_births), year >= 2010)

saveRDS(hospitals,      file.path(proc_dir, "hospitals.rds"))
saveRDS(partos_annual,  file.path(proc_dir, "partos_annual.rds"))
saveRDS(pordata_annual, file.path(proc_dir, "pordata_annual.rds"))
