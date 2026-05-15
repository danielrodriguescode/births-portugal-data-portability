# Raw data — provenance & attribution

The two source snapshots in this folder are committed deliberately so the
analysis is **clone-and-run reproducible** and survives upstream URL changes.
They are small, public statistical datasets, redistributed here for a
non-commercial academic project **with attribution**, as required by each
source's terms. If you reuse them, carry the attribution below.

| File | Dataset | Publisher | Source | Snapshot taken | Terms |
|---|---|---|---|---|---|
| `partos-e-cesarianas.csv` | *Partos e Cesarianas* — monthly deliveries & caesareans per SNS hospital | Serviços Partilhados do Ministério da Saúde (SPMS) / Direção-Geral da Saúde, via the **Transparência SNS** open-data portal | <https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/> | 2026-05-10 | Open government data — free reuse with attribution to Transparência SNS / Ministério da Saúde. |
| `pordata.xlsx` | Live births by *município* of mother's residence | Fundação Francisco Manuel dos Santos (**PORDATA**), aggregating Instituto Nacional de Estatística (INE) statistics | <https://www.pordata.pt/> | 2026-05-10 | PORDATA terms: free use including reproduction, with attribution to PORDATA (source: INE). |

## Why these are committed (and nothing else is)

`.gitignore` ignores all of `data/raw/*` **except** these two files and this
README. Rationale:

- They are the **canonical inputs** every headline number is computed from.
  Committing them pins provenance: a grader reproduces from exactly the data
  used, not from whatever the live portals serve later.
- `R/00_download.R` can still re-fetch the SNS CSV (`FORCE_REDOWNLOAD=TRUE`),
  but the committed copy is the fallback if the dataset slug rotates — a
  documented real risk.
- PORDATA has **no stable direct-download URL**; committing the export removes
  the only manual, non-deterministic step in the pipeline.

## Refreshing to a newer data vintage

These are point-in-time snapshots (2014–2024 analysis window). To update:

1. **SNS:** `FORCE_REDOWNLOAD=TRUE Rscript R/00_download.R`.
2. **PORDATA:** re-export per README section 3 in the repo root, overwrite
   `pordata.xlsx`, keeping PORDATA's native multi-sheet workbook
   (`Quadro` / `Metainformação` / `Códigos`). `R/01_import.R` validates the
   structure on read and fails loudly with guidance if the export is mis-shaped.
3. Re-run `Rscript run_all.R`. If headline numbers move, update `RESULTS.md`.

See [../DATA_DICTIONARY.md](../DATA_DICTIONARY.md) for variables, time periods,
and study populations.
