# 01_import.R
# Load raw source files from data/raw/ and persist them as .rds in data/processed/.
# No transformation here beyond what readr/readxl require — preserve raw fidelity
# so 02_clean.R can re-read without touching data/raw/.

library(here)
library(readr)
library(readxl)

raw_dir <- here("data", "raw")
out_dir <- here("data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Partos e Cesarianas: semicolon-delimited CSV, UTF-8 with BOM
partos <- read_delim(
  file.path(raw_dir, "partos-e-cesarianas.csv"),
  delim = ";",
  locale = locale(encoding = "UTF-8"),
  show_col_types = FALSE
)
saveRDS(partos, file.path(out_dir, "raw_partos.rds"))

# PORDATA xlsx has 5 metadata rows and a multi-block header (Total / Masculino /
# Feminino, see CLAUDE.md). Read raw without column-name parsing so 02_clean.R
# can slice the right block.
pordata <- read_excel(
  file.path(raw_dir, "pordata.xlsx"),
  sheet = 1,
  col_names = FALSE,
  .name_repair = "minimal"
)
saveRDS(pordata, file.path(out_dir, "raw_pordata.rds"))
