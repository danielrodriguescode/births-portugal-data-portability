# 00_setup.R
# Install and load every package the project depends on. Run once after cloning.
# Usage: Rscript R/00_setup.R

# This list is the exact set of packages the pipeline (R/00–04 + sync) and the
# Shiny app attach. Kept deliberately tight: every entry is verified to be
# loaded somewhere in the codebase, and nothing left over from the removed
# paper/presentation tooling is installed. If you add a library() call
# anywhere, add the package here too.
required <- c(
  # data wrangling — tidyverse pulls dplyr/tidyr/ggplot2/readr/stringr/
  #                   forcats/lubridate/tibble, all attached across the code
  "tidyverse", "janitor", "lubridate", "here", "stringr", "stringi",
  # I/O
  "readr", "readxl",
  # spatial
  "sf", "leaflet",
  # modelling — lmerTest is REQUIRED by R/03_analyse.R for the Satterthwaite
  #             p-value on the H3 year coefficient (was missing → 03 crashed)
  "lme4", "lmerTest", "spdep", "broom", "broom.mixed",
  # Shiny app — bsicons is REQUIRED by shiny/app.R for the KPI value-box icons
  #             (was missing → the app crashed on startup)
  "shiny", "bslib", "bsicons", "plotly", "DT", "scales", "htmltools",
  # deploy
  "rsconnect",
  # github-only deps installer
  "remotes"
)

missing <- setdiff(required, rownames(installed.packages()))
if (length(missing) > 0) {
  message("Installing CRAN packages: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
}

# ulsportugal — sf geometries for the 39 ULS, GitHub-only (own package)
if (!requireNamespace("ulsportugal", quietly = TRUE)) {
  message("Installing ulsportugal from GitHub")
  remotes::install_github("danielrodriguescode/ulsportugal", quiet = TRUE)
}

invisible(lapply(c(required, "ulsportugal"), function(pkg) {
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}))

message("All ", length(required) + 1, " packages installed and loaded.")
