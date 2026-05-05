# Births in Portugal — Cross-Regional Flow & Health Data Portability

> Regional Analysis, Hospital Cross-Referencing, and the Case for Health Data Portability.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PhD Laboratory Project in Health Data Science. Quantifies inter-regional obstetric patient flow in Portugal by cross-referencing PORDATA regional birth statistics against hospital-level deliveries from the Transparência SNS *Partos e Cesarianas* dataset, and uses the result to argue for health data portability across SNS institutions.

**Author:** Daniel Rodrigues — solo submission.

## Deliverables

- **R analytical pipeline** in `R/` (numbered `00_setup.R` → `04_visualise.R`).
- **Interactive Shiny dashboard** in `shiny/`, deployable to shinyapps.io.
- **Academic paper** in `paper/paper.Rmd` (IMRaD).
- **Oral defense slides** in `presentation/slides.qmd` (Quarto reveal.js).
- **LLM interaction log** in [prompts.md](prompts.md) — course requirement.
- **Main results summary** in [RESULTS.md](RESULTS.md).
- **Data dictionary** in [data/DATA_DICTIONARY.md](data/DATA_DICTIONARY.md).

## Quick start

```bash
# 1. Install R dependencies (one-off)
Rscript R/00_setup.R

# 2. Run the full pipeline: download → import → clean → analyse → visualise
Rscript run_all.R

# 3. Launch the Shiny app
Rscript -e "shiny::runApp('shiny', launch.browser = TRUE)"

# 4. Knit the paper
Rscript -e "rmarkdown::render('paper/paper.Rmd')"

# 5. Render the presentation
quarto render presentation/slides.qmd
```

To re-fetch source data even if files exist locally:
```bash
FORCE_REDOWNLOAD=TRUE Rscript R/00_download.R
```

## Data sources

See [data/DATA_DICTIONARY.md](data/DATA_DICTIONARY.md) for full variable descriptions, time periods, and study populations.

| Dataset | Source | File |
|---|---|---|
| Deliveries by hospital | [Transparência SNS](https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/) | `data/raw/partos-e-cesarianas.csv` |
| Births by region & year | [PORDATA](https://www.pordata.pt) | `data/raw/pordata.xlsx` (manual export) |
| NUTS shapefiles | [Eurostat GISCO](https://ec.europa.eu/eurostat/web/gisco/geodata/reference-data/administrative-units-statistical-units/nuts) | `data/raw/nuts/` (auto-fetched) |

## Repository layout

See [CLAUDE.md](CLAUDE.md) for the canonical layout, pipeline contract, and data-quirk notes (region crosswalk, hospital-name drift, monthly→annual aggregation).

## Main results

Headline numbers and figures live in [RESULTS.md](RESULTS.md). Once the pipeline runs against confirmed PORDATA data, that file is the executive summary; the paper expands on it.

## Deploying the Shiny app

```r
# One-off: authorise rsconnect with shinyapps.io credentials
rsconnect::setAccountInfo(name = "<account>", token = "<token>", secret = "<secret>")

# Deploy
rsconnect::deployApp("shiny", appName = "births-portugal")
```

The deployed app reads only from `data/processed/*.rds` bundled into the deploy — keep `shiny/` self-contained.

## Reproducibility

`Rscript run_all.R` rebuilds every artefact from `data/raw/`. The Shiny app and paper read only from `data/processed/` and `outputs/` — no live computation happens outside the pipeline.

## License

Code is released under the [MIT License](LICENSE). Source data are subject to PORDATA and Transparência SNS terms; attribute both when reusing.
