# 00_setup.R
# Install and load every package the project depends on. Run once after cloning.
# Usage: Rscript R/00_setup.R

# Packages attached by the pipeline (R/00–04 + sync) and the Shiny app.
required <- c(
  # data wrangling (tidyverse provides dplyr/tidyr/ggplot2/readr/stringr/
  # forcats/lubridate/tibble)
  "tidyverse", "janitor", "lubridate", "here", "stringr", "stringi",
  # I/O
  "readr", "readxl",
  # spatial
  "sf", "leaflet",
  # modelling (lmerTest provides Satterthwaite p-values for the H3 coefficient)
  "lme4", "lmerTest", "spdep", "broom", "broom.mixed",
  # Shiny app
  "shiny", "bslib", "bsicons", "plotly", "DT", "scales", "htmltools",
  # deploy
  "rsconnect",
  # GitHub-package installer
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
