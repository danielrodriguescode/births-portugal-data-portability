# region_crosswalk.R
# Mapping between Regiões de Saúde (used in partos-e-cesarianas.csv) and
# NUTS II / NUTS III (used in PORDATA). Sourced by 02_clean.R and 03_analyse.R.
#
# Sources to cite when filling this in:
#  - DGS administrative boundaries for Regiões de Saúde
#  - INE / Eurostat NUTS 2013 or NUTS 2024 definitions (pick one and stick to it)
#
# Norte and Centro Regiões de Saúde do NOT align 1:1 with NUTS II Norte/Centro —
# document every disputed concelho here with a comment.

regiao_saude_to_nuts2 <- tibble::tribble(
  ~regiao_saude,                          ~nuts2,
  "Região de Saúde Norte",                "Norte",
  "Região de Saúde Centro",               "Centro",
  "Região de Saúde LVT",                  "Área Metropolitana de Lisboa",
  "Região de Saúde do Alentejo",          "Alentejo",
  "Região de Saúde do Algarve",           "Algarve"
)
