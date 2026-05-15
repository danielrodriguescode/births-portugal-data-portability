# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

This is **not a generic software project**. It is a research codebase for a PhD discipline assignment (Laboratory Project in Health Data Science). The assignment brief and the original project plan are kept on the student's machine (outside the repo) and are not part of the public codebase.

**Research question.** Quantify inter-regional obstetric patient flow in Portugal by cross-referencing PORDATA regional birth statistics against hospital-level deliveries from the Transparência SNS *Partos e Cesarianas* dataset, and use the result to argue for health data portability across SNS institutions.

**What lives in this repository:**
1. **R analytical pipeline** producing the ULS-level Mobility metric (see Methodology below).
2. **Shiny application** deployable to shinyapps.io with five tabs: **Overview** (lede + KPI value boxes + year-filterable ULS choropleth via `ulsportugal` + top-7 importer/exporter ranks), **By ULS** (deliveries-vs-residents scatter + per-ULS table with mobility ratio), **Over time** (national lmer trend + ULS × year heatmap), **Hypotheses** (sub-tabs H1–H4, each with question, test rationale, verdict pill, plot, and interpretation), **Sources** (open-data attribution + the four PPP hospitals folded in).
3. **README, [prompts.md](prompts.md) (LLM interactions, mandated by the course), data dictionary, and reproducibility notes.**

The assignment grading is: research question 10% / data acquisition & processing 20% / statistical analysis 25% / dashboard 20% / GitHub & reproducibility 15% / oral defense 10%. Optimise for **statistical depth and reproducibility**, not feature breadth.

## Stack

R only. Do not introduce Python — the assignment allows it but the project plan commits to R end-to-end so the same code base can drive both the analysis and the Shiny app.

| Layer | Packages |
|---|---|
| Data wrangling | `tidyverse`, `janitor`, `lubridate`, `here`, `stringi` |
| I/O | `readr`, `readxl` |
| Spatial | `sf`, `leaflet`, [`ulsportugal`](https://github.com/danielrodriguescode/ulsportugal) |
| Modelling | `lme4`, `lmerTest` (Satterthwaite p-values), `spdep` (Moran's I), `broom`, `broom.mixed` |
| App | `shiny`, `bslib`, `plotly`, `DT` |

`ulsportugal` is a GitHub-only own package that returns sf geometries for the 39 ULS in mainland Portugal — installed via `remotes::install_github` inside [R/00_setup.R](R/00_setup.R). It replaces the original plan's NUTS shapefile fetch because ULS catchment areas are the actual policy-relevant unit for analyses of Portuguese health-care delivery.

## Repository layout

```
.
├── data/
│   ├── raw/         # Source snapshots COMMITTED (partos csv + pordata xlsx + README provenance); other drops gitignored
│   └── processed/   # .rds artefacts produced by the pipeline (gitignored)
├── R/
│   ├── 00_setup.R          # Install all packages incl. ulsportugal from GitHub
│   ├── 00_download.R       # Auto-fetch SNS CSV; PORDATA xlsx is manual
│   ├── 01_import.R         # Read raw files → data/processed/raw_*.rds
│   ├── 02_clean.R          # Tidy, deduplicate, harmonise codes
│   ├── 03_analyse.R        # ULS-level Mobility, H1–H4 tests
│   ├── 04_visualise.R      # Static figures
│   ├── region_crosswalk.R  # NUTS 2024 ↔ Região de Saúde mapping + URBAN_TERTIARY_ULS
│   └── sync_shiny_data.R   # Copy data/processed/ + headline.csv → shiny/data/
├── shiny/
│   ├── app.R                # Single-file Shiny entry point (five tabs)
│   └── data/                # Bundle (gitignored) — refilled by sync_shiny_data
├── deploy_app.R             # Sync + rsconnect::deployApp("shiny")
├── outputs/
│   ├── figures/             # PNG figures (gitignored, regenerable)
│   └── tables/              # headline.csv (gitignored, regenerable)
├── run_all.R                # Master orchestrator (sources 00→04 + sync_shiny_data)
├── RESULTS.md               # Plain-language executive summary of findings
├── prompts.md               # MANDATORY: every LLM prompt + critical comment
├── data/DATA_DICTIONARY.md  # Source, variables, time period, study population
└── README.md
```

`run_all.R` must remain runnable end-to-end from raw data; if a step needs new dependencies or new raw files, update both the script and this file.

## Common commands

All commands assume the working directory is the project root. Use `here::here()` inside `R/` scripts and `run_all.R` / `deploy_app.R`, not `setwd()`. **Do not use `here::here()` inside `shiny/app.R`** — the deployed app has no project-root marker on shinyapps.io and will fail to start (see "Shiny self-containment contract" below).

```bash
# One-off setup
Rscript R/00_setup.R

# Run the full analytical pipeline (raw → processed → figures + tables)
Rscript run_all.R

# Run a single pipeline stage
Rscript R/03_analyse.R

# Launch the Shiny app locally — run_all.R already populated shiny/data/.
# If you only ran 03_analyse.R, refresh the bundle first:
#   DRY_RUN=TRUE Rscript deploy_app.R
Rscript -e "shiny::runApp('shiny', launch.browser = TRUE)"

# Deploy the app (rebuilds shiny/data/ from pipeline outputs, then uploads).
# Requires rsconnect::setAccountInfo() to have been run once with shinyapps.io
# credentials.
Rscript deploy_app.R
```

### Shiny self-containment contract

`shiny/app.R` reads ONLY from `shiny/data/` using paths **relative to the app directory** — never `here::here()`. shinyapps.io has no project-root marker, so `here()` resolves unpredictably there; that is the failure mode that produced the *"Unable to connect to worker after 60.00 seconds"* error in deployment. `shiny/data/` is rebuilt every time `run_all.R` finishes (via `sync_shiny_data()`) and again every time `deploy_app.R` runs, so a removed pipeline output never silently lingers in the deploy. `shiny/data/` is gitignored — never edit by hand, never commit.

There is no formal test suite. If you add validation, prefer `testthat` placed under `tests/testthat/` and runnable with `testthat::test_dir('tests/testthat')`.

## Pipeline architecture

The pipeline is **strictly sequential and idempotent**. Each numbered script in `R/` reads from `data/processed/` (or `data/raw/` for `01_import.R`) and writes its outputs back to `data/processed/` as `.rds`. Never mutate raw files. Never short-circuit by sourcing one script from another at runtime — `run_all.R` is the only orchestrator, and it ends by calling `sync_shiny_data()` so the Shiny bundle in `shiny/data/` always reflects the latest pipeline run.

1. **`00_download.R`** — fetch SNS CSV from Transparência SNS (env var `FORCE_REDOWNLOAD=TRUE` to bypass the local-file skip). PORDATA xlsx must be exported manually from pordata.pt — the file does not expose a stable direct URL.
2. **`01_import.R`** — read `partos-e-cesarianas.csv` (semicolon, UTF-8) and `pordata.xlsx` (sheet 1, no header parsing — preserve the multi-row layout for 02 to handle). Output `raw_partos.rds`, `raw_pordata.rds`.
3. **`02_clean.R`** — apply data-quality filters, build the concelho→ULS crosswalk, and aggregate both sources to ULS level:
    - Drop years with non-December latest month (filters partial 2026)
    - Hospital identity = `(instituicao, regiao)` — *never* include lat/lng in the key (drift across releases splits the same hospital into two ids)
    - Take the **December** value as the annual total (the SNS monthly counters are cumulative year-to-date — see "Data notes that bite" below)
    - Map hospitals to ULS by spatial point-in-polygon against `ulsportugal()` polygons, falling back to direct ULS-name match for the few hospitals with imprecise reported coordinates
    - PORDATA: skip rows 1–5 (metadata), use row 6 cols 3–21 as year labels (Total block; cols 22+ are Masculino/Feminino), pivot wide-to-long, then aggregate concelho→ULS using the freguesia-share crosswalk (3 split concelhos: Lisboa, Loures, Porto)
    - Output `crosswalk_concelho_uls.rds`, `partos_uls.rds`, `pordata_uls.rds`, `hospitals.rds`.
4. **`03_analyse.R`** — compute, per `(uls, year)`:
   `Mobility = HospitalDeliveries(uls, year) − ResidentBirths(uls, year)`
   No capacity proxy, no redistribution. PORDATA is aggregated to ULS via the concelho→ULS dictionary in `ulsportugal` (3 split concelhos — Lisboa, Loures, Porto — allocated proportionally to freguesia counts). Apply Unicode NFC normalisation (`stringi::stri_trans_nfc`) on every join key — without it the SNS data (composed `ã`) silently fails to match the crosswalk source-file (decomposed). Run H1 (one-sample t-test on per-ULS means, n=39 — no IID violation), H2 (Wilcoxon urban tertiary vs other), H3 (lmer with `lmerTest`-derived Satterthwaite p-values), H4 (Moran's I, k=5 NN on ULS polygon centroids). Output `mobility_panel.rds`, `models.rds`, `outputs/tables/headline.csv`, `outputs/tables/ppp_panel.csv`.
5. **`04_visualise.R`** — generate every static figure into `outputs/figures/` for use by the dashboard. Currently 9 figures (`fig01_deliveries_top10_uls`, `fig02_caesarean_rate_national`, `fig03_mobility_by_uls`, `fig04_deliveries_vs_residents`, `fig05_mobility_heatmap`, `fig06_mobility_choropleth`, `fig07a_lmer_resid_vs_fitted`, `fig07b_lmer_qq`, `fig08_h2_urban_vs_peripheral`).
6. **`R/sync_shiny_data.R`** — copies the five required `.rds` panels (`partos_uls`, `pordata_uls`, `mobility_panel`, `hospitals`, `models`) plus `outputs/tables/headline.csv` into `shiny/data/`, and additionally caches the `ulsportugal` sf polygons as `shiny/data/uls_map.rds` (xz-compressed, ~67 KB) so the deployed app never calls `ulsportugal()` at runtime — that download is ~60 MB on every shinyapps.io cold start. Seven files total. Sourced by `run_all.R` at the very end so a fresh pipeline run leaves the Shiny bundle ready for both local launch and `deploy_app.R`.

The Shiny app reads ONLY from `shiny/data/` — it does not re-run the pipeline and does not reach back into `data/processed/`. If app data looks stale, run `run_all.R` (or `DRY_RUN=TRUE Rscript deploy_app.R` to refresh just the bundle).

## Data notes that bite

These are not theoretical — every one was caught at runtime and corrected. Read carefully before changing anything in `02_clean.R`.

1. **SNS counters are cumulative year-to-date** — Cascais 2013-01 = 206, 2013-02 = 383 (Jan+Feb), …, 2013-12 = 2,304 (annual total); 2014-01 = 191 (resets). The annual total is the **December** value, never the sum across months. `02_clean.R` enforces this with `slice_max(date, n = 1)` per hospital-year, plus a filter that drops any year whose latest reported month is not December.
2. **Hospital identity drifts across SNS releases** — Cascais and 5 ULS units have two slightly different reported coordinates over the years; the same institution gets renamed (e.g. Centro Hospitalar Universitário Cova da Beira → Unidade Local de Saúde da Cova da Beira) in 2024. Identity is keyed on `(instituicao, regiao)` only — never include lat/lng. Despite this, the CHU→ULS rename still creates two `instituicao` strings for the same hospital; we treat them as separate institutions in the panel because pre-2024 baseline capacity is what defines the analysis cohort. A spatial join (point-in-polygon with `ulsportugal`) is used in the Shiny app to consolidate the duplicates visually but not in the analysis.
3. **Concelho → ULS mapping uses `ulsportugal:::dicionario_mestre`.** 275 of 278 Continental concelhos map 1:1 to a single ULS; 3 are split (Lisboa across 3 ULS, Loures and Porto across 2). For these we allocate PORDATA births proportionally to the number of freguesias the package assigns to each ULS — a defensible default in the absence of freguesia-level population weights. Madeira and Açores are excluded (autonomous regions outside Continental SNS).
4. **Unicode NFC vs NFD silently breaks joins.** SNS data is composed (`ã` = 1 codepoint), the crosswalk source file is decomposed (`a` + combining tilde = 2 codepoints) depending on editor. Always normalise with `stringi::stri_trans_nfc()` before any join on Portuguese region or hospital names.
5. **PORDATA Excel layout** — sheet "Quadro" has 5 metadata rows; row 6 is the year-label header for the *Total* block (cols 3–21); cols 22–40 repeat for Masculino, 41–59 for Feminino. Read the whole sheet with `col_names = FALSE, .name_repair = "minimal"` and slice the Total block manually. PORDATA in the current file uses **NUTS 2024** (live as of 2025-12-23), which splits the old Área Metropolitana de Lisboa into three NUTS II.
6. **Time-period coverage:** SNS is 2013–2025 + partial 2026; PORDATA is 2010–2024. The active analysis window is **2014–2024**.

## Statistical hypotheses (see [data/DATA_DICTIONARY.md](data/DATA_DICTIONARY.md) for full pre-registration)

Unit of analysis: 39 mainland ULS (PPPs reported separately, not in tests).

- **H1.** Mean ULS mobility ≠ 0 (one-sample t-test on the 39 per-ULS means). Empirically: t = −3.42, p = 0.001, mean = −434 deliveries/year/ULS. **Reject H₀.**
- **H2.** Urban tertiary ULS (Santa Maria, São José, Lisboa Ocidental, São João, Santo António, Coimbra) absorb more than peripheral ULS (Wilcoxon two-sample). Empirically: W = 80, p = 0.48 — **non-significant**, and the urban tertiaries span the entire mobility distribution (Coimbra +2,213 is the biggest magnet; Lisboa Ocidental −1,841 is one of the biggest exporters). The "urban tertiary" label is too coarse to be predictive.
- **H3.** Mobility drifts over time (`lmer(mobility ~ year + (1 | uls))`). Empirically: β = −7.5/year, 95% CI [−14.4, −0.7], p = 0.032. **Reject H₀** — gap widening.
- **H4.** Spatial clustering (Moran's I on ULS polygon centroids, k=5 NN). Empirically: I = 0.115, p = 0.034. **Reject H₀** — significant but modest spatial autocorrelation.

## LLM-use protocol (assignment requirement)

Every meaningful prompt-and-response with an LLM (including conversations with Claude) **must** be logged to [prompts.md](prompts.md) along with a short critical comment from the student. This is graded under "scientific quality of the research question" (10%) and "evaluation criteria — critical thinking about the LLM". When you make a substantive recommendation that ends up in the codebase, remind the user to capture the exchange in `prompts.md`.

## What "done" looks like for a task

- **Pipeline change:** `Rscript run_all.R` runs clean from a fresh `data/processed/` directory and ends with `shiny/data/` repopulated.
- **Shiny change:** app starts via `shiny::runApp('shiny')` with no `here::here()` calls inside `shiny/`, all five tabs render (Overview / By ULS / Over time / Hypotheses / Sources), no console warnings about reactive invalidation, the choropleth and heatmap are interactive, and the H1–H4 sub-tabs each render their plot. Deploy verified via `Rscript deploy_app.R` — worker boots within shinyapps.io's 60-second window.
