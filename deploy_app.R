# deploy_app.R
# Deploy the Shiny app to shinyapps.io with a fresh data bundle.
#
# Why this script exists:
#   The Shiny app reads ONLY from shiny/data/ so the bundle uploaded to
#   shinyapps.io has no out-of-folder dependencies. shiny/data/ is rebuilt
#   from data/processed/ + outputs/tables/headline.csv every time, so a
#   removed pipeline output never silently lingers in the deploy.
#
# Usage:
#   1. Run the pipeline first to refresh data/processed/ and outputs/tables/:
#         Rscript run_all.R
#   2. (one-off) Authorise rsconnect with your shinyapps.io credentials:
#         rsconnect::setAccountInfo(name = "<account>",
#                                    token = "<token>",
#                                    secret = "<secret>")
#   3. Deploy:
#         Rscript deploy_app.R
#
# To rebuild shiny/data/ without uploading, set DRY_RUN=TRUE:
#   DRY_RUN=TRUE Rscript deploy_app.R

suppressPackageStartupMessages({
  library(here)
  library(rsconnect)
})

source(here("R", "sync_shiny_data.R"))
sync_shiny_data()

if (isTRUE(as.logical(Sys.getenv("DRY_RUN", "FALSE")))) {
  message("DRY_RUN=TRUE — skipping rsconnect::deployApp().")
  invisible(NULL)
} else {
  rsconnect::deployApp(
    appDir         = here("shiny"),
    appName        = "births-portugal",
    forceUpdate    = TRUE,
    launch.browser = FALSE
  )
}
