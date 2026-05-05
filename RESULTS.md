# Main Results

> This file is the executive summary of the project's empirical findings, written for non-statisticians. It is updated each time `R/04_visualise.R` runs against fresh processed data — the headline numbers come from `outputs/tables/headline.csv`.

## Headline answer

> _**Pending real analysis.**_ Once the pipeline produces `data/processed/flow_index.rds`, fill in here:
>
> _"Across N Portuguese maternity hospitals over the period YYYY–YYYY, X% had a positive cross-regional flow index, meaning they delivered more babies than their resident catchment population would predict. The median surplus was Y deliveries per year (IQR Z–W), and the effect was statistically distinguishable from zero (one-sample t-test, p = ...)."_

## Key figures

| # | Figure | File | What it shows |
|---|---|---|---|
| 1 | Annual deliveries by Região de Saúde | `outputs/figures/fig01_deliveries_by_region.png` | Time series of total deliveries per region |
| 2 | Choropleth of births by NUTS III | `outputs/figures/fig02_choropleth.png` | Regional birth density |
| 3 | Observed vs expected per hospital | `outputs/figures/fig03_obs_vs_exp.png` | Each dot = one hospital-year; off-diagonal = cross-regional flow |
| 4 | Cross-regional flow heatmap | `outputs/figures/fig04_flow_heatmap.png` | Estimated patient flow between regions |

## Statistical tests

| Test | Hypothesis | Statistic | p | Outcome |
|---|---|---|---|---|
| One-sample t-test (H1) | flow index ≠ 0 | _pending_ | _pending_ | _pending_ |
| `lmer` year coefficient (H3) | flow index changes over time | _pending_ | _pending_ | _pending_ |
| Moran's I (H4) | flow indices cluster spatially | _pending_ | _pending_ | _pending_ |

## Limitations

To be expanded in the paper Discussion. Anchor points:
- *Capacity proxy* — using mean baseline delivery volume conflates true capacity with historical demand patterns.
- *Region of residence* — the SNS dataset records hospital region, not maternal residence; the inferred "flow" is structural, not individual-level.
- *Hospital identity drift* — ULS reorganisations across years require manual reconciliation.
- *PORDATA / NUTS vs Regiões de Saúde* — the geography mismatch propagates into every cross-reference.

## Policy implication

The empirical finding (once confirmed) directly motivates the policy argument: if a meaningful share of obstetric care happens outside the patient's home region, prenatal records held by regional providers must follow the patient — i.e., **the SNS needs portable, interoperable maternal health records**.
