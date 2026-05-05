# 00_setup.R
# Install and load every package the project depends on. Run once after cloning.
# Usage: Rscript R/00_setup.R

required <- c(
  # data wrangling
  "tidyverse", "janitor", "lubridate", "here", "stringr", "stringi",
  # I/O
  "readr", "readxl", "openxlsx",
  # spatial
  "sf", "leaflet", "tmap",
  # modelling
  "lme4", "spdep", "broom", "broom.mixed",
  # reporting
  "knitr", "rmarkdown", "quarto",
  # app
  "shiny", "bslib", "shinydashboard", "plotly", "DT",
  # deploy
  "rsconnect",
  # github-only deps
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
