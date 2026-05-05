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

## 2. PORDATA — Births by Município and Year

| Field | Value |
|---|---|
| **Source link** | https://www.pordata.pt |
| **Publisher** | Fundação Francisco Manuel dos Santos (aggregator of INE / Eurostat data) |
| **Local file** | `data/raw/pordata.xlsx` |
| **Format** | XLSX (multi-row headers — see import notes in CLAUDE.md) |
| **Time period** | Active analysis: **2014–2024** |
| **Granularity** | One row per (município × year) — sheet "Quadro" rows tagged with `Município` in column 1 |
| **Study population** | All live births to mothers resident in each Continental Portuguese município (308 in PORDATA total; 278 Continental + 30 ilhas) |
| **Acquisition** | Manual export from PORDATA web interface (no stable direct-download URL) |
| **License** | PORDATA terms — free for academic use with attribution |

### Variables (after `02_clean.R` processing)

| Variable | Type | Description |
|---|---|---|
| `concelho` | character | Município name, NFC-normalised |
| `year` | integer | Calendar year |
| `live_births` | integer | Total live births to residents that year |

### Aggregation to ULS

`02_clean.R` joins PORDATA with `ulsportugal:::dicionario_mestre` (concelho → ULS). 275 of 278 Continental concelhos map 1:1; the 3 split concelhos (Lisboa, Loures, Porto) are allocated proportionally to freguesia counts per ULS:

- **Lisboa** (24 freguesias) → 13/24 to ULS São José + 8/24 to ULS Santa Maria + 3/24 to ULS Lisboa Ocidental
- **Loures** (10 freguesias) → 6/10 to ULS Loures-Odivelas + 4/10 to ULS São José
- **Porto** (7 freguesias) → 4/7 to ULS Santo António + 3/7 to ULS São João

Output table `pordata_uls.rds` has columns `(uls, year, resident_births)`.

---

## 3. Spatial / administrative reference data (`ulsportugal` R package)

| Field | Value |
|---|---|
| **Source link** | https://github.com/danielrodriguescode/ulsportugal |
| **Publisher** | Daniel Rodrigues (own package) |
| **Acquisition** | `remotes::install_github` inside `R/00_setup.R` |
| **Format** | sf POLYGON / MULTIPOLYGON in EPSG:4326 + tibble dictionaries |
| **Coverage** | 39 mainland Portuguese ULS + concelho/freguesia → ULS dictionary |
| **License** | MIT |

### Functions used

- `ulsportugal()` — sf table of the 39 ULS polygons with columns `NOME_ULS`, `NOME_CURTO`, `geometry`.
- `ulsportugal:::dicionario_mestre` — internal tibble with one row per (Freguesia, Concelho, NOME_ULS, DICO). Used to derive the concelho → ULS share table (see PORDATA aggregation above).

Replaces the original plan's NUTS shapefile fetch — ULS is the actual policy-relevant administrative unit for analyses of Portuguese health-care delivery, and freguesia/concelho granularity exceeds what NUTS 2024 provides.

---

## Hypotheses (revised after methodological pivot — see prompts.md 2026-05-05)

Unit of analysis: 39 mainland Unidades Locais de Saúde (ULS).

For each ULS in each year:
**Mobility = HospitalDeliveries(ULS) − ResidentBirths(ULS)**

where **HospitalDeliveries** comes from Transparência SNS (place of delivery, hospitals geographically inside that ULS) and **ResidentBirths** comes from PORDATA aggregated by concelho via `ulsportugal:::dicionario_mestre` (mother's residence). 4 PPPs reported separately, excluded from the tests.

1. **H1.** Mean ULS mobility ≠ 0 (one-sample t-test on the 39 per-ULS means).

2. **H2.** Urban tertiary ULS (Santa Maria, São José, Lisboa Ocidental, São João, Santo António, Coimbra) absorb more than peripheral ULS (Wilcoxon two-sample on per-ULS mean mobility).

3. **H3.** Mobility drifts over time (`lmer(mobility ~ year + (1 | uls))` with `lmerTest` Satterthwaite p-values).

4. **H4.** Spatial clustering of mean mobility (Moran's I on ULS polygon centroids, k=5 nearest-neighbour weights).

## Analysis strategy summary

For each ULS in each year, directly compare hospital-side deliveries (SNS) and residence-side births (PORDATA aggregated to ULS). The difference is the mobility metric — no capacity proxy, no redistribution. Inferential tests H1–H4. Full method in `paper/paper.Rmd` § Methods and `R/03_analyse.R`.
