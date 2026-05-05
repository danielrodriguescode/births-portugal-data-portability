# 00_download.R
# Automated data acquisition. Fetches PORDATA and Transparência SNS source files
# into data/raw/ if they are missing or if FORCE_REDOWNLOAD=TRUE is in the env.
#
# Usage:
#   Rscript R/00_download.R              # downloads only what's missing
#   FORCE_REDOWNLOAD=TRUE Rscript R/00_download.R   # re-fetches everything
#
# Note: PORDATA and Transparência SNS do not currently expose stable, citable
# direct-download URLs for these specific series. The URLs below were the
# canonical landing pages at project start; if they redirect or 404, update
# them here AND log the change in prompts.md per the course LLM-use protocol.

library(here)

raw_dir <- here("data", "raw")
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

force <- isTRUE(as.logical(Sys.getenv("FORCE_REDOWNLOAD", "FALSE")))

sources <- list(
  partos = list(
    file = "partos-e-cesarianas.csv",
    url  = "https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/download/?format=csv&use_labels_for_header=true&csv_separator=%3B",
    mode = "wb"
  ),
  pordata = list(
    file = "pordata.xlsx",
    # PORDATA does not expose a stable direct-download URL; the file must be
    # exported manually from https://www.pordata.pt and dropped into data/raw/.
    # Set url = NA to indicate manual provisioning.
    url  = NA_character_,
    mode = "wb"
  )
)

for (src in sources) {
  dest <- file.path(raw_dir, src$file)
  if (file.exists(dest) && !force) {
    message("Skipping ", src$file, " (already present; set FORCE_REDOWNLOAD=TRUE to re-fetch)")
    next
  }
  if (is.na(src$url)) {
    if (!file.exists(dest)) {
      stop(src$file, " requires manual download — see comment in R/00_download.R")
    }
    next
  }
  message("Downloading ", src$file, " from ", src$url)
  utils::download.file(src$url, destfile = dest, mode = src$mode, quiet = FALSE)
}

message("Data acquisition complete.")
