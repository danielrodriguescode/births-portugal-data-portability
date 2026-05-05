# Data Dictionary

This document satisfies the course requirement to "clearly indicate: source link, selected variables, time period analyzed, study population" for every dataset used in the project.

---

## 1. Partos e Cesarianas (Transparência SNS)

| Field | Value |
|---|---|
| **Source link** | https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/ |
| **Publisher** | Serviços Partilhados do Ministério da Saúde (SPMS) / Direção-Geral da Saúde (DGS) |
| **Local file** | `data/raw/partos-e-cesarianas.csv` |
| **Format** | CSV, semicolon-delimited, UTF-8 with BOM |
| **Time period** | 2013-01 → most recent monthly release. Analysis window: 2013–2025 (full SNS years); cross-referenced flow analysis 2013–2024 (intersection with PORDATA). |
| **Granularity** | One row per (hospital × month) |
| **Study population** | All deliveries recorded in Portuguese SNS hospitals reporting to the Transparência platform |
| **License** | Open data, attribution to Transparência SNS / Ministério da Saúde |

### Variables

| Column (raw) | After `clean_names()` | Type | Description |
|---|---|---|---|
| Período | `periodo` | character `YYYY-MM` | Reporting month |
| Região | `regiao` | character | Região de Saúde (5 categories: Norte, Centro, LVT, Alentejo, Algarve) |
| Instituição | `instituicao` | character | Hospital / institution name (mutates across releases — see CLAUDE.md) |
| Localização Geográfica | `localizacao_geografica` | character | "lat, lng" pair, decimal degrees, WGS84 |
| Nº Total de Partos | `no_total_de_partos` | integer | **Cumulative year-to-date** total deliveries (see quirk below) |
| Nº Cesarianas | `no_cesarianas` | integer | **Cumulative year-to-date** caesarean deliveries (subset of total) |

> ⚠ **Critical data-semantics quirk** — the *Nº Total de Partos* and *Nº Cesarianas* columns are **cumulative year-to-date counters**, not per-month deliveries. Example: Hospital de Cascais 2013-01 = 206, 2013-02 = 383 (= Jan + Feb), …, 2013-12 = 2,304 (annual total); 2014-01 = 191 (counter resets in January). This is undocumented in the published Transparência SNS schema. The annual total per hospital is therefore the **December** value (or the latest available month, if December is missing), **never the sum across months**. `R/02_clean.R` enforces this with `slice_max(date, n = 1)` per hospital-year and additionally drops any year whose latest reported month is not December.

### Derived variables (created in `R/02_clean.R`)

- `date` (Date) — first day of the reporting month, parsed via `lubridate::ym()`
- `year` (integer)
- `lat`, `lng` (numeric) — split from `localizacao_geografica`
- `hospital_id` (character) — stable internal ID assigned in `hospitals.rds`

---

## 2. PORDATA — Births by Region and Year

| Field | Value |
|---|---|
| **Source link** | https://www.pordata.pt |
| **Publisher** | Fundação Francisco Manuel dos Santos (aggregator of INE / Eurostat data) |
| **Local file** | `data/raw/pordata.xlsx` |
| **Format** | XLSX (multi-row headers — see import notes in CLAUDE.md) |
| **Time period** | Project uses 2010 onwards to align with the SNS dataset |
| **Granularity** | One row per (region × year) |
| **Study population** | All live births occurring to mothers resident in each NUTS II / NUTS III region of Portugal |
| **Acquisition** | Manual export from PORDATA web interface (no stable direct-download URL) |
| **License** | PORDATA terms — free for academic use with attribution |

### Variables (planned — confirm against the actual XLSX layout)

| Variable | Type | Description |
|---|---|---|
| `region` | character | NUTS II or NUTS III region name |
| `nuts_level` | character | "NUTS2" or "NUTS3" |
| `year` | integer | Calendar year |
| `live_births` | integer | Total live births |
| `gfr` | numeric | General fertility rate (births per 1000 women aged 15–49) — optional |
| `cbr` | numeric | Crude birth rate (births per 1000 population) — optional |

---

## 3. Spatial reference data (NUTS shapefiles)

| Field | Value |
|---|---|
| **Source link** | https://ec.europa.eu/eurostat/web/gisco/geodata/reference-data/administrative-units-statistical-units/nuts |
| **Publisher** | Eurostat GISCO |
| **Local file** | `data/raw/nuts/` (to fetch — see `R/00_download.R`) |
| **Format** | Shapefile / GeoJSON, EPSG:4326 |
| **Time period** | NUTS 2021 nomenclature (lock to one revision and document) |
| **Study population** | Geographic boundaries only, no demographic data |

---

## Hypotheses

1. **H1 (primary).** The cross-regional flow index — observed deliveries minus expected deliveries based on regional birth share — is systematically positive across a majority of Portuguese maternity hospitals. Tested via one-sample t-test against zero on the pooled hospital-year distribution.

2. **H2.** Cross-regional flow is more pronounced in larger urban centres (Lisboa, Porto, Coimbra) than elsewhere. Tested via subgroup comparison.

3. **H3.** Cross-regional flow has a non-zero temporal trend over the study period. Tested via the fixed-year coefficient in `lmer(flow ~ year + (1 | hospital_id))`.

4. **H4.** Hospitals with positive flow indices cluster geographically rather than being randomly distributed. Tested via Moran's I (`spdep::moran.test`).

## Analysis strategy summary

Cross-reference annualised hospital delivery counts against PORDATA regional totals weighted by each hospital's baseline capacity share, derive the flow index, run inferential tests (H1–H4), and visualise both descriptively (time series, choropleth) and analytically (observed-vs-expected, Sankey of estimated flow). Full method in `paper/paper.Rmd` § Methods and `R/03_analyse.R`.
