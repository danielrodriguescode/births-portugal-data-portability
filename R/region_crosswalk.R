# region_crosswalk.R
# Mapping between PORDATA NUTS 2024 regions (used in pordata.xlsx) and the
# Regiões de Saúde (used in partos-e-cesarianas.csv). Sourced by 02_clean.R
# and 03_analyse.R.
#
# IMPORTANT: pordata.xlsx in this repo uses the NUTS 2024 revision, which
# splits the old NUTS II "Área Metropolitana de Lisboa" into three NUTS II
# units: Oeste e Vale do Tejo, Grande Lisboa, Península de Setúbal. The
# Região de Saúde LVT roughly aggregates all three. Confirm boundary
# alignment against DGS sources before final submission — the empirical fit
# is approximate, not exact (especially the Tejo concelhos).
#
# Madeira and Açores have autonomous regional health systems outside the
# Continental SNS — we exclude them from cross-referencing because the SNS
# Partos e Cesarianas dataset does not cover them.

nuts2_to_regiao_saude <- tibble::tribble(
  ~nuts2,                              ~regiao_saude,
  "Norte",                             "Região de Saúde Norte",
  "Centro",                            "Região de Saúde do Centro",
  "Oeste e Vale do Tejo",              "Região de Saúde LVT",
  "Grande Lisboa",                     "Região de Saúde LVT",
  "Península de Setúbal",              "Região de Saúde LVT",
  "Alentejo",                          "Região de Saúde do Alentejo",
  "Algarve",                           "Região de Saúde do Algarve"
  # "Região Autónoma dos Açores"  — outside Continental SNS
  # "Região Autónoma da Madeira"  — outside Continental SNS
)
