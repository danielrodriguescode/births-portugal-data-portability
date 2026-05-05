# 00_setup.R
# Install and load every package the project depends on. Run once after cloning.
# Usage: Rscript R/00_setup.R

required <- c(
  # data wrangling
  "tidyverse", "janitor", "lubridate", "here", "stringr",
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
  "rsconnect"
)

missing <- setdiff(required, rownames(installed.packages()))
if (length(missing) > 0) {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
}

invisible(lapply(required, function(pkg) {
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}))

message("All ", length(required), " packages installed and loaded.")
