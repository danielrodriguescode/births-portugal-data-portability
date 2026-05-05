# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

This is **not a generic software project**. It is a research codebase for a PhD discipline assignment (Laboratory Project in Health Data Science) — the canonical project plan lives in [paper/PhD_Project_Plan_Births_Portugal.docx](paper/PhD_Project_Plan_Births_Portugal.docx) and the assignment brief in [paper/Health_Data_Science_Lab_Project_EN (1).pdf](paper/Health_Data_Science_Lab_Project_EN%20(1).pdf). Read the plan before making non-trivial changes — methodology, data sources, and deliverables are all fixed there.

**Research question.** Quantify inter-regional obstetric patient flow in Portugal by cross-referencing PORDATA regional birth statistics against hospital-level deliveries from the Transparência SNS *Partos e Cesarianas* dataset, and use the result to argue for health data portability across SNS institutions.

**Deliverables (all mandatory):**
1. **R analytical pipeline** producing the cross-regional flow index (see Methodology below).
2. **Shiny application** deployable to shinyapps.io with six tabs: Answer, Regional Overview (choropleth), Hospital Explorer (observed-vs-expected), Cross-Regional Flow (heatmap), Methods (plain language), Data.
3. **Academic paper** (IMRaD) targeting JAMIA / IJMI / Acta Médica Portuguesa.
4. **Oral defense slides** (5-slide reveal.js, 10 min total).
5. **GitHub repo** with README, [prompts.md](prompts.md) (LLM interactions, mandated by the course), data download instructions, and reproducibility notes.

The assignment grading is: research question 10% / data acquisition & processing 20% / statistical analysis 25% / dashboard 20% / GitHub & reproducibility 15% / oral defense 10%. Optimise for **statistical depth and reproducibility**, not feature breadth.

## Stack

R only. Do not introduce Python — the assignment allows it but the project plan commits to R end-to-end so the same code base can drive both the analysis and the Shiny app.

| Layer | Packages |
|---|---|
| Data wrangling | `tidyverse`, `janitor`, `lubridate`, `here`, `stringi` |
| I/O | `readr`, `readxl` |
| Spatial | `sf`, `leaflet`, [`ulsportugal`](https://github.com/danielrodriguescode/ulsportugal) |
| Modelling | `lme4`, `lmerTest` (Satterthwaite p-values), `spdep` (Moran's I), `broom`, `broom.mixed` |
| Reporting | `knitr`, `rmarkdown`, `quarto` |
| App | `shiny`, `bslib`, `plotly`, `DT` |

`ulsportugal` is a GitHub-only own package that returns sf geometries for the 39 ULS in mainland Portugal — installed via `remotes::install_github` inside [R/00_setup.R](R/00_setup.R). It replaces the original plan's NUTS shapefile fetch because ULS catchment areas are the actual policy-relevant unit for analyses of Portuguese health-care delivery.

## Repository layout

```
.
├── data/
│   ├── raw/         # Untouched source files (gitignored, fetched by R/00_download.R)
│   └── processed/   # .rds artefacts produced by the pipeline (gitignored)
├── R/
│   ├── 00_setup.R          # Install all packages incl. ulsportugal from GitHub
│   ├── 00_download.R       # Auto-fetch SNS CSV; PORDATA xlsx is manual
│   ├── 01_import.R         # Read raw files → data/processed/raw_*.rds
│   ├── 02_clean.R          # Tidy, deduplicate, harmonise codes
│   ├── 03_analyse.R        # Catchment expectation, flow index, H1-H4 tests
│   ├── 04_visualise.R      # Static figures for the paper
│   └── region_crosswalk.R  # NUTS 2024 ↔ Região de Saúde mapping
├── shiny/
│   └── app.R                # Single-file Shiny entry point (six tabs)
├── outputs/
│   ├── figures/             # PNG figures (gitignored, regenerable)
│   └── tables/              # headline.csv (gitignored, regenerable)
├── paper/
│   ├── paper.Rmd            # IMRaD manuscript draft
│   ├── references.bib       # BibTeX bibliography
│   └── *.{docx,pdf}         # Source assignment brief and PhD project plan
├── presentation/
│   └── slides.qmd           # Quarto reveal.js, 5 slides for 10-min defense
├── run_all.R                # Master orchestrator (sources 00→04)
├── RESULTS.md               # Plain-language executive summary of findings
├── prompts.md               # MANDATORY: every LLM prompt + critical comment
├── data/DATA_DICTIONARY.md  # Source, variables, time period, study population
└── README.md
```

`run_all.R` must remain runnable end-to-end from raw data; if a step needs new dependencies or new raw files, update both the script and this file.

## Common commands

All commands assume the working directory is the project root (use `here::here()` inside scripts, not `setwd()`).

```bash
# One-off setup
Rscript R/00_setup.R

# Run the full analytical pipeline (raw → processed → figures + tables)
Rscript run_all.R

# Run a single pipeline stage
Rscript R/03_analyse.R

# Launch the Shiny app locally
Rscript -e "shiny::runApp('shiny', launch.browser = TRUE)"

# Knit the paper
Rscript -e "rmarkdown::render('paper/paper.Rmd')"

# Render the presentation
quarto render presentation/slides.qmd

# Deploy the app (requires rsconnect set up once with shinyapps.io credentials)
Rscript -e "rsconnect::deployApp('shiny')"
```

There is no formal test suite. If you add validation, prefer `testthat` placed under `tests/testthat/` and runnable with `testthat::test_dir('tests/testthat')`.

## Pipeline architecture

The pipeline is **strictly sequential and idempotent**. Each numbered script reads from `data/processed/` (or `data/raw/` for `01_import.R`) and writes its outputs back to `data/processed/` as `.rds`. Never mutate raw files. Never short-circuit by sourcing one script from another at runtime — `run_all.R` is the only orchestrator.

1. **`00_download.R`** — fetch SNS CSV from Transparência SNS (env var `FORCE_REDOWNLOAD=TRUE` to bypass the local-file skip). PORDATA xlsx must be exported manually from pordata.pt — the file does not expose a stable direct URL.
2. **`01_import.R`** — read `partos-e-cesarianas.csv` (semicolon, UTF-8) and `pordata.xlsx` (sheet 1, no header parsing — preserve the multi-row layout for 02 to handle). Output `raw_partos.rds`, `raw_pordata.rds`.
3. **`02_clean.R`** — apply data-quality filters and produce tidy panels:
    - Drop years with non-December latest month (filters partial 2026)
    - Hospital identity = `(instituicao, regiao)` — *never* include lat/lng in the key (drift across releases splits the same hospital into two ids)
    - Take the **December** value as the annual total (the SNS monthly counters are cumulative year-to-date — see "Data notes that bite" below)
    - PORDATA: skip rows 1–5 (metadata), use row 6 cols 3–21 as year labels (Total block; cols 22+ are Masculino/Feminino), pivot wide-to-long, filter to NUTS II/III ≥ 2010
    - Output `partos_annual.rds`, `pordata_annual.rds`, `hospitals.rds`.
4. **`03_analyse.R`** — compute, per `(hospital h, region r, year t)`:
   `Expected(h, r, t) = TotalBirths(r, t) × Capacity(h) / Σ Capacity(r)`
   where `Capacity(h)` is the hospital's mean delivery volume over baseline 2013–2015. Aggregate PORDATA NUTS II to Região de Saúde via [R/region_crosswalk.R](R/region_crosswalk.R) (Lisboa is split into 3 NUTS II under NUTS 2024; all map to LVT). Apply Unicode NFC normalisation (`stringi::stri_trans_nfc`) on every join key — without it the SNS data (composed `ã`) silently fails to match the crosswalk source-file (decomposed). Run H1 (one-sample t-test, IID violated, lmer is the trustworthy test), H2 (Wilcoxon urban tertiary vs other), H3 (lmer with `lmerTest`-derived Satterthwaite p-values), H4 (Moran's I, k=5 NN). Output `flow_index.rds`, `models.rds`, `outputs/tables/headline.csv`.
5. **`04_visualise.R`** — generate every static figure referenced by `paper.Rmd` and the slides into `outputs/figures/`. Currently 7 figures (deliveries by region, caesarean rate, observed-vs-expected, mean flow per hospital, two lmer diagnostics, H2 box+strip).

The Shiny app reads the same `data/processed/*.rds` artefacts. It does **not** re-run the pipeline. If app data looks stale, run `run_all.R` first.

## Data notes that bite

These are not theoretical — every one was caught at runtime and corrected. Read carefully before changing anything in `02_clean.R`.

1. **SNS counters are cumulative year-to-date** — Cascais 2013-01 = 206, 2013-02 = 383 (Jan+Feb), …, 2013-12 = 2,304 (annual total); 2014-01 = 191 (resets). The annual total is the **December** value, never the sum across months. `02_clean.R` enforces this with `slice_max(date, n = 1)` per hospital-year, plus a filter that drops any year whose latest reported month is not December.
2. **Hospital identity drifts across SNS releases** — Cascais and 5 ULS units have two slightly different reported coordinates over the years; the same institution gets renamed (e.g. Centro Hospitalar Universitário Cova da Beira → Unidade Local de Saúde da Cova da Beira) in 2024. Identity is keyed on `(instituicao, regiao)` only — never include lat/lng. Despite this, the CHU→ULS rename still creates two `instituicao` strings for the same hospital; we treat them as separate institutions in the panel because pre-2024 baseline capacity is what defines the analysis cohort. A spatial join (point-in-polygon with `ulsportugal`) is used in the Shiny app to consolidate the duplicates visually but not in the analysis.
3. **Região in the SNS CSV is *Região de Saúde*, not NUTS II.** Five categories vs PORDATA's nine NUTS II under NUTS 2024. The crosswalk in [R/region_crosswalk.R](R/region_crosswalk.R) maps Norte/Centro/Alentejo/Algarve cleanly; LVT aggregates the three Lisboa-area NUTS II (Oeste e Vale do Tejo + Grande Lisboa + Península de Setúbal). Madeira and Açores are excluded — outside Continental SNS.
4. **Unicode NFC vs NFD silently breaks joins.** SNS data is composed (`ã` = 1 codepoint), the crosswalk source file is decomposed (`a` + combining tilde = 2 codepoints) depending on editor. Always normalise with `stringi::stri_trans_nfc()` before any join on Portuguese region or hospital names.
5. **PORDATA Excel layout** — sheet "Quadro" has 5 metadata rows; row 6 is the year-label header for the *Total* block (cols 3–21); cols 22–40 repeat for Masculino, 41–59 for Feminino. Read the whole sheet with `col_names = FALSE, .name_repair = "minimal"` and slice the Total block manually. PORDATA in the current file uses **NUTS 2024** (live as of 2025-12-23), which splits the old Área Metropolitana de Lisboa into three NUTS II.
6. **Time-period coverage:** SNS is 2013–2025 + partial 2026; PORDATA is 2010–2024. The cross-referenced flow analysis is 2013–2024; SNS-only descriptive figures use 2013–2025.

## Statistical hypotheses (see [data/DATA_DICTIONARY.md](data/DATA_DICTIONARY.md) for full pre-registration)

- **H1.** Flow index ≠ 0 across all hospital-years (one-sample t-test). Caveat: violates IID; the lmer fit (H3) is the trustworthy test.
- **H2.** Urban tertiary centres in Lisboa, Porto and Coimbra absorb more cross-regional patients than peripheral hospitals (Wilcoxon two-sample). **Empirically the direction was opposite** — urban tertiaries have *more negative* flow indices than peripheral hospitals (p = 0.14, not significant). The most parsimonious explanation is private-sector concentration in those same cities.
- **H3.** Flow index drifts over time (`lmer(flow ~ year + (1 | hospital_id))`).
- **H4.** Spatial clustering of flow indices (Moran's I with k=5 nearest-neighbour weights).

## LLM-use protocol (assignment requirement)

Every meaningful prompt-and-response with an LLM (including conversations with Claude) **must** be logged to [prompts.md](prompts.md) along with a short critical comment from the student. This is graded under "scientific quality of the research question" (10%) and "evaluation criteria — critical thinking about the LLM". When you make a substantive recommendation that ends up in the codebase or the paper, remind the user to capture the exchange in `prompts.md`.

## What "done" looks like for a task

- **Pipeline change:** `Rscript run_all.R` runs clean from a fresh `data/processed/` directory.
- **Shiny change:** app starts via `shiny::runApp('shiny')`, all six tabs render, no console warnings about reactive invalidation, the choropleth and flow heatmap are interactive.
- **Paper change:** `paper.Rmd` knits without errors, all referenced figures exist in `outputs/figures/`, every numerical claim cites a value computed in the pipeline.
