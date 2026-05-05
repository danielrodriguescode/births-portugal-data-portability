# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

This is **not a generic software project**. It is a research codebase for a PhD discipline assignment (Laboratory Project in Health Data Science) — the canonical project plan lives in [paper/PhD_Project_Plan_Births_Portugal.docx](paper/PhD_Project_Plan_Births_Portugal.docx) and the assignment brief in [paper/Health_Data_Science_Lab_Project_EN (1).pdf](paper/Health_Data_Science_Lab_Project_EN%20(1).pdf). Read the plan before making non-trivial changes — methodology, data sources, and deliverables are all fixed there.

**Research question.** Quantify inter-regional obstetric patient flow in Portugal by cross-referencing PORDATA regional birth statistics against hospital-level deliveries from the Transparência SNS *Partos e Cesarianas* dataset, and use the result to argue for health data portability across SNS institutions.

**Deliverables (all mandatory):**
1. **R analytical pipeline** producing the cross-regional flow index (see Methodology below).
2. **Shiny application** deployed to shinyapps.io with three panels: Regional Overview (choropleth), Hospital Explorer (table + observed-vs-expected plot), Cross-Regional Flow (heat map / Sankey).
3. **Academic paper** (IMRaD) targeting JAMIA / IJMI / Acta Médica Portuguesa.
4. **GitHub repo** with README, `prompts.md` (LLM interactions, mandated by the course), data download instructions, and reproducibility notes.

The assignment grading is: research question 10% / data acquisition & processing 20% / statistical analysis 25% / dashboard 20% / GitHub & reproducibility 15% / oral defense 10%. Optimise for **statistical depth and reproducibility**, not feature breadth.

## Stack

R only. Do not introduce Python — the assignment allows it but the project plan commits to R end-to-end so the same code base can drive both the analysis and the Shiny app.

Core packages (already declared in the plan, install via `R/00_setup.R` once it exists):

| Layer | Packages |
|---|---|
| Data wrangling | `tidyverse`, `janitor`, `lubridate`, `here` |
| I/O | `readr`, `readxl`, `openxlsx` |
| Spatial | `sf`, `leaflet`, `tmap`, `osmdata` |
| Modelling | `lme4` (mixed effects), `spdep` (Moran's I) |
| Reporting | `knitr`, `rmarkdown` |
| App | `shiny`, `bslib`, `shinydashboard`, `plotly`, `DT` |

## Repository layout

```
.
├── data/
│   ├── raw/         # Untouched source files (partos-e-cesarianas.csv, pordata.xlsx, NUTS shapefiles)
│   └── processed/   # .rds artefacts produced by the pipeline — safe to delete and rebuild
├── R/
│   ├── 01_import.R    # Read raw files; output data/processed/raw_*.rds
│   ├── 02_clean.R     # Standardise names, codes, missing values; output tidy panels
│   ├── 03_analyse.R   # Catchment expectation, flow index, mixed model, Moran's I
│   └── 04_visualise.R # Static figures for the paper → outputs/figures/
├── shiny/
│   ├── app.R          # Single-file Shiny entry point (ui + server)
│   └── R/             # Modules and helpers sourced by app.R
├── outputs/
│   ├── figures/       # PNG/PDF for the paper
│   └── tables/        # CSV/RDS summary tables
├── paper/
│   ├── paper.Rmd      # IMRaD manuscript draft
│   └── *.{docx,pdf}   # Source assignment brief and PhD project plan (reference, do not edit)
├── run_all.R          # Master script; sources 01→04 in order
├── prompts.md         # MANDATORY: every LLM prompt + response + critical commentary
└── README.md
```

`run_all.R` must remain runnable end-to-end from raw data; if a step needs new dependencies or new raw files, update both the script and this file.

## Common commands

All commands assume the working directory is the project root (use `here::here()` inside scripts, not `setwd()`).

```bash
# Run the full analytical pipeline (raw → processed → figures)
Rscript run_all.R

# Run a single pipeline stage
Rscript R/03_analyse.R

# Launch the Shiny app locally
Rscript -e "shiny::runApp('shiny', launch.browser = TRUE)"

# Knit the paper
Rscript -e "rmarkdown::render('paper/paper.Rmd')"

# Deploy the app (requires rsconnect set up once with shinyapps.io credentials)
Rscript -e "rsconnect::deployApp('shiny')"
```

There is no formal test suite. If you add validation, prefer `testthat` placed under `tests/testthat/` and runnable with `testthat::test_dir('tests/testthat')`.

## Pipeline architecture

The pipeline is **strictly sequential and idempotent**. Each numbered script reads from `data/processed/` (or `data/raw/` for `01_import.R`) and writes its outputs back to `data/processed/` as `.rds`. Never mutate raw files. Never short-circuit by sourcing one script from another at runtime — `run_all.R` is the only orchestrator.

1. **`01_import.R`** — load `partos-e-cesarianas.csv` (semicolon-separated, header row is `Período;Região;Instituição;Localização Geográfica;Nº Total de Partos;Nº Cesarianas`, period is monthly `YYYY-MM`, geocoords are `"lat, lng"` in a single column) and `pordata.xlsx`. Output `raw_partos.rds`, `raw_pordata.rds`.
2. **`02_clean.R`** — `janitor::clean_names()`, parse `período` to date, split geocoords into `lat`/`lng`, harmonise `região` strings (the CSV uses *Região de Saúde do Alentejo*, *LVT*, *Norte*, *Centro*, *Algarve* — not NUTS II directly; build an explicit crosswalk table and commit it as `R/region_crosswalk.R`). Aggregate hospital counts to annual totals to align with PORDATA's annual cadence. Output `partos_annual.rds`, `pordata_annual.rds`, `hospitals.rds` (one row per institution with coordinates).
3. **`03_analyse.R`** — compute, per `(hospital h, region r, year t)`:
   `Expected(h, r, t) = TotalBirths(r, t) × Capacity(h, t) / Σ Capacity(r, t)`
   where `Capacity(h, t)` is the hospital's mean delivery volume over the baseline period. The **cross-regional flow index** is `Observed − Expected`. Then: one-sample t-test against zero (pooled across years), `lme4::lmer(flow ~ year + (1 | hospital))`, and `spdep::moran.test` on the spatial weights of hospital coordinates.
4. **`04_visualise.R`** — generate every static figure referenced by `paper.Rmd` into `outputs/figures/`. Figures must be regenerable; do not hand-edit PNGs.

The Shiny app reads the same `data/processed/*.rds` artefacts. It does **not** re-run the pipeline. If app data looks stale, run `run_all.R` first.

## Data notes that bite

- The `Período` column in `partos-e-cesarianas.csv` is monthly; PORDATA is annual. Always aggregate the SNS data to annual before any cross-referencing.
- `Região` in the SNS CSV refers to *Regiões de Saúde* (5 categories), not NUTS II (7) or NUTS III (25). The crosswalk is non-trivial — Alentejo/Algarve/LVT map cleanly, but Norte and Centro Regiões de Saúde do not align 1:1 with NUTS II Norte/Centro. Document every mapping decision in `R/region_crosswalk.R` with a comment citing the source.
- Hospital names mutate across annual SNS releases (e.g., reorganisations into ULS units). Build a stable hospital ID by hashing the geocoordinate or by a manually curated alias table — never join on the raw `Instituição` string alone.
- PORDATA Excel files have multi-row headers and merged cells. Read with `readxl::read_excel(skip = ...)` and validate row counts after import.

## LLM-use protocol (assignment requirement)

Every meaningful prompt-and-response with an LLM (including conversations with you, Claude) **must** be logged to `prompts.md` along with a short critical comment from the student. This is graded. When you make a substantive recommendation that ends up in the codebase or the paper, remind the user to capture the exchange in `prompts.md`.

## What "done" looks like for a task

- Pipeline change: `Rscript run_all.R` runs clean from a fresh `data/processed/` directory.
- Shiny change: app starts via `shiny::runApp('shiny')`, all three panels render with current processed data, no console warnings about reactive invalidation.
- Paper change: `paper.Rmd` knits without errors, all referenced figures exist in `outputs/figures/`.
