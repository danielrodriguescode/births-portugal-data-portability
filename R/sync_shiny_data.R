# R/sync_shiny_data.R
# Copy pipeline artefacts into shiny/data/ so the Shiny app's bundle is
# self-contained. Used by both run_all.R (after the pipeline finishes) and
# deploy_app.R (immediately before rsconnect::deployApp). The app reads ONLY
# from shiny/data/ — see shiny/app.R for the contract.

sync_shiny_data <- function(repo_root = here::here(), verbose = TRUE) {
  shiny_data <- file.path(repo_root, "shiny", "data")
  proc_dir   <- file.path(repo_root, "data", "processed")
  tables_dir <- file.path(repo_root, "outputs", "tables")

  required_rds <- c("partos_uls.rds", "pordata_uls.rds", "mobility_panel.rds",
                    "hospitals.rds", "models.rds")
  required_csv <- "headline.csv"

  if (!dir.exists(proc_dir)) {
    stop("data/processed/ missing — run Rscript run_all.R first.", call. = FALSE)
  }
  missing_rds <- required_rds[!file.exists(file.path(proc_dir, required_rds))]
  if (length(missing_rds) > 0) {
    stop(sprintf("Missing pipeline artefacts in data/processed/: %s\nRun Rscript run_all.R first.",
                 paste(missing_rds, collapse = ", ")),
         call. = FALSE)
  }
  if (!file.exists(file.path(tables_dir, required_csv))) {
    stop(sprintf("outputs/tables/%s missing — run Rscript run_all.R first.",
                 required_csv),
         call. = FALSE)
  }

  if (dir.exists(shiny_data)) unlink(shiny_data, recursive = TRUE)
  dir.create(shiny_data, showWarnings = FALSE, recursive = TRUE)

  for (f in required_rds) {
    ok <- file.copy(file.path(proc_dir, f), file.path(shiny_data, f),
                    overwrite = TRUE)
    if (!ok) stop(sprintf("Failed to copy %s into shiny/data/.", f), call. = FALSE)
  }
  ok <- file.copy(file.path(tables_dir, required_csv),
                  file.path(shiny_data, required_csv), overwrite = TRUE)
  if (!ok) stop("Failed to copy headline.csv into shiny/data/.", call. = FALSE)

  if (verbose) {
    bundle <- list.files(shiny_data, full.names = FALSE)
    message(sprintf("Synced %d files into shiny/data/: %s",
                    length(bundle), paste(bundle, collapse = ", ")))
  }
  invisible(shiny_data)
}
