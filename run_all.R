# run_all.R
# Master orchestrator. Runs the full analytical pipeline from raw → processed → figures.
# Usage: Rscript run_all.R
#
# Prerequisite: Rscript R/00_setup.R (one-off, installs all dependencies).

# ---- Preflight: dependencies -------------------------------------------------
# Stop with a single clear message if R/00_setup.R has not been run.
.need <- c("here", "readr", "readxl", "dplyr", "tidyr", "stringi", "janitor",
           "lubridate", "sf", "spdep", "lme4", "lmerTest", "broom",
           "broom.mixed", "ulsportugal")
.missing <- .need[!vapply(.need, requireNamespace, logical(1), quietly = TRUE)]
if (length(.missing) > 0) {
  stop(
    "Missing R packages: ", paste(.missing, collapse = ", "), ".\n",
    "Run `Rscript R/00_setup.R` first (one-off; installs every dependency\n",
    "including ulsportugal from GitHub). See README section 2.",
    call. = FALSE
  )
}

library(here)

source(here("R", "00_download.R"))
source(here("R", "01_import.R"))
source(here("R", "02_clean.R"))
source(here("R", "03_analyse.R"))
source(here("R", "04_visualise.R"))

# Refresh the Shiny bundle so shiny::runApp("shiny") and deploy_app.R both
# pick up the latest .rds and headline.csv without an extra step.
source(here("R", "sync_shiny_data.R"))
sync_shiny_data()

message("Pipeline complete. Processed data in data/processed/, figures in outputs/figures/, Shiny bundle in shiny/data/.")
