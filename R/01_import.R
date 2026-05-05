# 01_import.R
# Load raw source files from data/raw/ and persist them as .rds in data/processed/.
# No transformation here beyond what readr/readxl require — preserve raw fidelity.

library(here)
library(readr)
library(readxl)

raw_dir <- here("data", "raw")
out_dir <- here("data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

partos <- read_delim(
  file.path(raw_dir, "partos-e-cesarianas.csv"),
  delim = ";",
  locale = locale(encoding = "UTF-8"),
  show_col_types = FALSE
)
saveRDS(partos, file.path(out_dir, "raw_partos.rds"))

# pordata.xlsx layout is not yet documented — inspect sheets and pick the births series.
# Adjust `sheet` and `skip` once the file structure is confirmed.
pordata_sheets <- excel_sheets(file.path(raw_dir, "pordata.xlsx"))
message("PORDATA sheets: ", paste(pordata_sheets, collapse = ", "))

pordata <- read_excel(
  file.path(raw_dir, "pordata.xlsx"),
  sheet = 1,
  skip = 0
)
saveRDS(pordata, file.path(out_dir, "raw_pordata.rds"))
