# Births in Portugal — Cross-Regional Flow & Health Data Portability

> Regional Analysis, Hospital Cross-Referencing, and the Case for Health Data Portability.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PhD Laboratory Project in Health Data Science. Quantifies inter-regional obstetric patient flow in Portugal by cross-referencing PORDATA regional birth statistics against hospital-level deliveries from the Transparência SNS *Partos e Cesarianas* dataset, and uses the result to argue for health data portability across SNS institutions.

**Authors:** Daniel Rodrigues, Diana Cibele, Madhuri Desai.

## Repository contents

- **R analytical pipeline** in `R/` (numbered `00_setup.R` → `04_visualise.R`).
- **Interactive Shiny dashboard** in `shiny/`, deployable to shinyapps.io.
- **LLM interaction log** in [prompts.md](prompts.md).
- **Main results summary** in [RESULTS.md](RESULTS.md).
- **Data dictionary** in [data/DATA_DICTIONARY.md](data/DATA_DICTIONARY.md).

## Reproducibility — full step-by-step

The source data is committed to the repository, so reproduction is clone → install → run with no manual data step. The pipeline is deterministic from `data/raw/` onward: the same raw inputs produce the same `.rds` panels, headline numbers, and figures.

### 0. Prerequisites

| Need | Why |
|---|---|
| **R ≥ 4.3** (tested with 4.5) | The pipeline uses `\|>` and other recent base-R features. |
| **macOS / Linux / WSL2** with **GDAL ≥ 3.4** and **PROJ ≥ 8** | `sf` and `spdep` need these system libraries. On macOS, `brew install gdal proj` is enough; on Debian/Ubuntu, `sudo apt install libgdal-dev libproj-dev libudunits2-dev`. |
| **Internet access** | The SNS CSV is auto-fetched, and `ulsportugal` is installed from GitHub. |
| **Optional — shinyapps.io account** | Only needed for online deployment. Local Shiny launches do not need it. |

### 1. Clone the repo

```bash
git clone https://github.com/danielrodriguescode/births-portugal-data-portability.git
cd births-portugal-data-portability
```

### 2. Install R dependencies (one-off)

```bash
Rscript R/00_setup.R
```

Installs the CRAN packages the pipeline and Shiny app require, plus the `ulsportugal` package from GitHub. This step is mandatory; `run_all.R` preflights the dependency list and stops with an explicit message if any package is missing.

### 3. Get the raw data — already in the repo

**Nothing to do.** Both source snapshots are committed under `data/raw/` so the repo is clone-and-run reproducible:

| Dataset | Source | File (committed) |
|---|---|---|
| SNS hospital deliveries (monthly cumulative-YTD) | [Transparência SNS](https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/) | `data/raw/partos-e-cesarianas.csv` |
| Live births by *município* of residence (annual) | [PORDATA](https://www.pordata.pt) | `data/raw/pordata.xlsx` |
| 39 ULS sf polygons + concelho dictionary | [`ulsportugal`](https://github.com/danielrodriguescode/ulsportugal) | (R package, installed in step 2) |

These are point-in-time snapshots (2014–2024 analysis window). Provenance, licensing, and attribution are documented in [data/raw/README.md](data/raw/README.md).

#### Refreshing to a newer data vintage (optional)

Only needed to run against data more recent than the committed snapshot:

- **SNS:** `FORCE_REDOWNLOAD=TRUE Rscript R/00_download.R`.
- **PORDATA:** PORDATA exposes no stable direct-download URL. Re-export by hand from <https://www.pordata.pt/> (indicator *"Nados-vivos de mães residentes em Portugal por Município"*, território *Municípios*, período ≥ 2010), using PORDATA's own **Descarregar → Excel (.xlsx)** button — do not copy-paste or re-save through another spreadsheet tool, which strips the metadata rows the parser relies on. Overwrite `data/raw/pordata.xlsx`, keeping all three sheets (`Quadro` / `Metainformação` / `Códigos`).

`R/01_import.R` reads the `Quadro` sheet by name and validates the structure `R/02_clean.R` requires (year labels in row 6, columns 3–21); a malformed export is rejected at import with a message stating what was expected.

### 4. Run the full pipeline

```bash
Rscript run_all.R
```

This sources, in order:

| # | Script | Reads from | Writes to |
|---|---|---|---|
| 1 | `R/00_download.R` | (network) | `data/raw/partos-e-cesarianas.csv` (skipped if already present) |
| 2 | `R/01_import.R` | `data/raw/` | `data/processed/raw_partos.rds`, `raw_pordata.rds` |
| 3 | `R/02_clean.R` | `data/processed/raw_*.rds` | `data/processed/{partos_uls, pordata_uls, hospitals, crosswalk_concelho_uls}.rds` |
| 4 | `R/03_analyse.R` | `data/processed/*.rds` | `data/processed/{mobility_panel, models}.rds`, `outputs/tables/{headline, ppp_panel}.csv` |
| 5 | `R/04_visualise.R` | `data/processed/`, `outputs/tables/` | `outputs/figures/fig01–fig08*.png` (9 figures) |
| 6 | `R/sync_shiny_data.R` | `data/processed/`, `outputs/tables/headline.csv`, `ulsportugal` | `shiny/data/` (5 panel `.rds` + `headline.csv` + cached `uls_map.rds`) |

Expected output on success ends with:

```
Synced 7 files into shiny/data/: headline.csv, hospitals.rds, mobility_panel.rds, models.rds, partos_uls.rds, pordata_uls.rds, uls_map.rds
Pipeline complete. Processed data in data/processed/, figures in outputs/figures/, Shiny bundle in shiny/data/.
```

### 5. Verify the headline numbers

```bash
cat outputs/tables/headline.csv
```

Against the committed snapshot this prints the values reported in [RESULTS.md](RESULTS.md): `n_uls = 39`, `h1_estimate ≈ −434`, `h1_p ≈ 0.001`, `h3_year_coef ≈ −7.5`, `h4_moran_I ≈ 0.115`.

### 6. Launch the Shiny app locally

```bash
Rscript -e "shiny::runApp('shiny', launch.browser = TRUE)"
```

The app reads `shiny/data/`, populated by `sync_shiny_data()` in step 4 (the `ulsportugal` polygons are pre-cached into `shiny/data/uls_map.rds` so the app does no network access at startup). To rebuild the bundle without re-running the full pipeline:

```bash
DRY_RUN=TRUE Rscript deploy_app.R
```

### 7. Deploy to shinyapps.io (optional)

```bash
# One-off: authorise rsconnect with your shinyapps.io account
Rscript -e 'rsconnect::setAccountInfo(name="<account>", token="<token>", secret="<secret>")'

# Deploy (rebuilds shiny/data/ from pipeline outputs, then uploads):
Rscript deploy_app.R
```

The Shiny app is self-contained: it reads only from `shiny/data/` (a derived copy of the pipeline outputs, gitignored and rebuilt by `sync_shiny_data()`) using paths relative to the app directory. It does not use `here::here()`, because shinyapps.io has no project-root marker for it to resolve against.

### Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Missing R packages: …` from `run_all.R` | You skipped step 2. Run `Rscript R/00_setup.R` (it installs everything, including `lmerTest` and `bsicons`), then re-run. |
| `Error: package 'sf' could not be loaded` | Install GDAL/PROJ/UDUNITS system libraries first (see Prerequisites), then `Rscript R/00_setup.R` again. |
| `00_download.R` fails with HTTP 403/404 | Transparência SNS occasionally rotates the dataset slug. The current URL is hard-coded in `R/00_download.R` — update it from the [dataset page](https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/) and re-run with `FORCE_REDOWNLOAD=TRUE`. |
| `data/raw/pordata.xlsx does not match the expected PORDATA layout` (from `01_import.R`) | The manual export is the wrong shape. Re-export per README section 3 — use PORDATA's own Excel download, keep all three sheets (`Quadro`/`Metainformação`/`Códigos`), and do **not** re-save it through another spreadsheet tool. The error message prints what it expected vs. what it got. |
| Joins drop Portuguese ULS / hospital names | Unicode NFC vs NFD mismatch — `02_clean.R` and `03_analyse.R` both run `stringi::stri_trans_nfc()` on join keys. If you add a new join, normalise both sides. |
| Shiny app shows blank panels locally | `shiny/data/` is empty. Run `DRY_RUN=TRUE Rscript deploy_app.R` (or `run_all.R`) to rebuild it from the pipeline outputs. |

## Dashboard

Live: **https://danielrodrigues.shinyapps.io/births-portugal/**

Five tabs:

| Tab | What it shows |
|---|---|
| **Overview** | One-paragraph answer to the research question, an inline *what-is-mobility* explainer, a year slider (2014–2024, default 2024, animatable), four KPI value boxes, a year-filterable ULS choropleth, and the top-7 net importers / exporters. |
| **By ULS** | Deliveries-vs-residents scatter for the selected year, and a sortable per-ULS table with a mobility-ratio column (+87 % / −55 % framing). |
| **Over time** | National mean-mobility trend with the `lmer` slope, and a ULS × year mobility heatmap. |
| **Hypotheses** | Sub-tabs for H1–H4. Each is a full page: the question, the statistical test and why it was chosen, a verdict pill (reject H₀ / n.s.), a 480 px plot, and 2–3 paragraphs of interpretation. |
| **Sources** | Open-data attribution with links, plus the four PPP hospitals (excluded from H1–H4) reported separately. |

The app is self-contained and reads only from `shiny/data/` — see the deployment notes in step 7.

## Data sources

See [data/DATA_DICTIONARY.md](data/DATA_DICTIONARY.md) for full variable descriptions, time periods, and study populations.

| Dataset | Source | File |
|---|---|---|
| Deliveries by hospital (monthly cumulative YTD) | [Transparência SNS](https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/) | `data/raw/partos-e-cesarianas.csv` (auto-fetched) |
| Live births by *município* of residence (annual) | [PORDATA](https://www.pordata.pt) | `data/raw/pordata.xlsx` (manual export — see step 3) |
| ULS sf polygons (39 mainland Unidades Locais de Saúde) | [`ulsportugal` R package](https://github.com/danielrodriguescode/ulsportugal) | installed via `remotes::install_github` |

## Repository layout

See [CLAUDE.md](CLAUDE.md) for the canonical layout, pipeline contract, and data-quirk notes (region crosswalk, hospital-name drift, monthly→annual aggregation, Unicode NFC/NFD).

`data/raw/` contains the two committed source snapshots and their provenance note ([data/raw/README.md](data/raw/README.md)). `data/processed/`, `outputs/figures/`, `outputs/tables/`, and `shiny/data/` are gitignored regenerable artefacts (rebuilt by `Rscript run_all.R`); each keeps a tracked `.gitkeep` so the directory structure survives a clone.

## Main results

Headline numbers and figures live in [RESULTS.md](RESULTS.md) — that file is the executive summary of the empirical findings.

## License

Code is released under the [MIT License](LICENSE). Source data are subject to PORDATA and Transparência SNS terms; attribute both when reusing.
