# region_crosswalk.R
# Concelho → ULS mapping built from `ulsportugal:::dicionario_mestre`.
# 278 Continental concelhos; 275 map 1:1 to a ULS, 3 are split (Lisboa, Loures,
# Porto). For split concelhos we allocate PORDATA births proportionally to the
# number of freguesias the package assigns to each ULS — a defensible default
# in the absence of freguesia-level population weights.

suppressPackageStartupMessages({
  library(dplyr)
  library(stringi)
  library(ulsportugal)
})

build_concelho_uls_crosswalk <- function() {
  dm <- ulsportugal:::dicionario_mestre |>
    mutate(Concelho = stri_trans_nfc(Concelho),
           NOME_ULS = stri_trans_nfc(NOME_ULS))

  # Count freguesias per (concelho, ULS) and turn into share-of-concelho
  dm |>
    count(Concelho, NOME_ULS, name = "n_freguesias") |>
    group_by(Concelho) |>
    mutate(share = n_freguesias / sum(n_freguesias)) |>
    ungroup() |>
    arrange(Concelho, desc(share))
}

# Hospitals classified as 'urban tertiary' for hypothesis H2 (the modern names
# of the academic centres in Lisboa, Porto and Coimbra).
URBAN_TERTIARY_ULS <- c(
  stri_trans_nfc("Unidade Local de Saúde de São José, EPE"),
  stri_trans_nfc("Unidade Local de Saúde de Santa Maria, EPE"),
  stri_trans_nfc("Unidade Local de Saúde de Lisboa Ocidental, EPE"),
  stri_trans_nfc("Unidade Local de Saúde de São João, EPE"),
  stri_trans_nfc("Unidade Local de Saúde de Santo António, EPE"),
  stri_trans_nfc("Unidade Local de Saúde de Coimbra, EPE")
)
