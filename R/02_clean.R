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
    partos     = sum(n_total_de_partos, na.rm = TRUE),
    cesarianas = sum(n_cesarianas,      na.rm = TRUE),
    .groups = "drop"
  )

# ---- PORDATA -----------------------------------------------------------------
# Pending: confirm sheet/header layout in raw_pordata.rds and reshape to long
# (region × year → births). Placeholder pass-through until layout is verified.
pordata_annual <- pordata_raw |> clean_names()

saveRDS(hospitals,      file.path(proc_dir, "hospitals.rds"))
saveRDS(partos_annual,  file.path(proc_dir, "partos_annual.rds"))
saveRDS(pordata_annual, file.path(proc_dir, "pordata_annual.rds"))
