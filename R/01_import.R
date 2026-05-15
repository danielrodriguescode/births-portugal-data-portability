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
partos_path <- file.path(raw_dir, "partos-e-cesarianas.csv")
if (!file.exists(partos_path)) {
  stop(
    "data/raw/partos-e-cesarianas.csv is missing. Run `Rscript R/00_download.R`\n",
    "(it auto-fetches from Transparência SNS). If that 404s, the dataset slug\n",
    "changed — update the URL in R/00_download.R and re-run with\n",
    "FORCE_REDOWNLOAD=TRUE. See README section 3.",
    call. = FALSE
  )
}
partos <- read_delim(
  partos_path,
  delim = ";",
  locale = locale(encoding = "UTF-8"),
  show_col_types = FALSE
)
saveRDS(partos, file.path(out_dir, "raw_partos.rds"))

# PORDATA xlsx has metadata rows and a multi-block header (Total / Masculino /
# Feminino, see CLAUDE.md). Read raw without column-name parsing so 02_clean.R
# can slice the right block. The data sheet is read by name ("Quadro") and its
# structure validated here, so a malformed manual export is rejected at import
# rather than corrupting downstream results.
pordata_path <- file.path(raw_dir, "pordata.xlsx")
if (!file.exists(pordata_path)) {
  stop(
    "data/raw/pordata.xlsx is missing. It is a MANUAL export — PORDATA has no\n",
    "stable direct-download URL. Follow README section 3 ('How to export\n",
    "pordata.xlsx manually') exactly, then re-run. Keep PORDATA's native\n",
    "multi-sheet workbook (Quadro / Metainformação / Códigos) — do not open\n",
    "and re-save it through another tool.",
    call. = FALSE
  )
}

sheets <- readxl::excel_sheets(pordata_path)
data_sheet <- if ("Quadro" %in% sheets) "Quadro" else 1L
if (!"Quadro" %in% sheets) {
  message(
    "  ! PORDATA workbook has no 'Quadro' sheet (found: ",
    paste(sheets, collapse = ", "), "). Falling back to sheet 1 — if the ",
    "structure check below fails, re-export per README section 3."
  )
}

pordata <- read_excel(
  pordata_path,
  sheet = data_sheet,
  col_names = FALSE,
  .name_repair = "minimal"
)

# Structural contract 02_clean.R relies on: calendar-year labels at row 6,
# columns 3:21 (the 'Total' block). Validate at import so a mis-shaped export
# is caught here, not as wrong numbers later.
.year_hdr <- suppressWarnings(as.integer(unlist(pordata[6, 3:21])))
.year_ok  <- sum(!is.na(.year_hdr) & .year_hdr >= 1990 & .year_hdr <= 2100)
if (ncol(pordata) < 21 || nrow(pordata) < 8 || .year_ok < 5) {
  stop(
    "data/raw/pordata.xlsx does not match the expected PORDATA layout.\n",
    "Expected: a 'Quadro' sheet whose row 6, columns 3-21 hold calendar-year\n",
    "labels (2010, 2011, …) — the 'Total' block. Got ", nrow(pordata),
    " rows x ", ncol(pordata), " cols; row 6 cols 3-21 parsed as: ",
    paste(utils::head(.year_hdr, 8), collapse = ", "), ".\n",
    "Re-export from pordata.pt following README section 3 — keep the\n",
    "indicator's native multi-row header; do not delete the metadata rows.",
    call. = FALSE
  )
}

saveRDS(pordata, file.path(out_dir, "raw_pordata.rds"))
