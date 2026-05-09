# run_all.R
# Master orchestrator. Runs the full analytical pipeline from raw → processed → figures.
# Usage: Rscript run_all.R

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
