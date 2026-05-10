# shiny/app.R
# Single-file Shiny entry point. Self-contained — reads pre-computed artefacts
# from shiny/data/, populated by deploy_app.R (or shiny::runApp from the repo
# root after run_all.R has produced fresh data/processed/*.rds).
#
# All paths in this file are RELATIVE to the app directory so the bundle works
# both locally and on shinyapps.io (where here::here() cannot find a project
# root). Do not reintroduce here::here() — see prompts.md.
#
# Design system:
#   - bs_theme(version = 5), Inter from Google Fonts, off-white page bg #FAFBFC,
#     white cards with hairline #E5E7EB borders, #0F4C81 accent.
#   - Single diverging mobility palette #B2182B → #F2F2F2 → #1A5276 used
#     everywhere mobility appears (choropleth, scatter, heatmap, ranks, table).
#   - tabular-nums on every figure; semibold (600) headings.
#   - Four tabs: Overview / By ULS / Over time / Sources.

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(bsicons)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(plotly)
  library(leaflet)
  library(DT)
  library(sf)
  library(stringi)
  library(scales)
  library(forcats)
})

# Strip the "Unidade Local de Saude (de|do|da|...)" prefix that bloats every
# label. The 'u' escape is used instead of a literal 'ú' so the pattern is
# ASCII-source and the regex engine doesn't choke on a Latin1/UTF-8 mismatch.
ULS_PREFIX_RE <- "^Unidade Local de Sa\u00fade (?:de|do|da|dos|das|d')\\s+"
uls_short_name <- function(x) {
  out <- sub(ULS_PREFIX_RE, "", x, perl = TRUE)
  out <- sub(", EPE$", "", out, perl = TRUE)
  out
}

URBAN_TERTIARY_ULS <- vapply(c(
  "Unidade Local de Saúde de São José, EPE",
  "Unidade Local de Saúde de Santa Maria, EPE",
  "Unidade Local de Saúde de Lisboa Ocidental, EPE",
  "Unidade Local de Saúde de São João, EPE",
  "Unidade Local de Saúde de Santo António, EPE",
  "Unidade Local de Saúde de Coimbra, EPE"
), stri_trans_nfc, character(1), USE.NAMES = FALSE)

proc_dir <- "data"
nfc <- function(x) stri_trans_nfc(x)

mobility    <- readRDS(file.path(proc_dir, "mobility_panel.rds")) |>
  mutate(unit_id = nfc(unit_id))
hospitals   <- readRDS(file.path(proc_dir, "hospitals.rds")) |>
  mutate(NOME_ULS = nfc(NOME_ULS), instituicao = nfc(instituicao))
models      <- readRDS(file.path(proc_dir, "models.rds"))

# sf polygons cached into the bundle by R/sync_shiny_data.R — do NOT call
# ulsportugal::ulsportugal() at runtime; it downloads ~60 MB on every
# shinyapps.io cold start. Source of truth: data/uls_map.rds.
uls_map <- readRDS(file.path(proc_dir, "uls_map.rds")) |>
  mutate(NOME_ULS   = nfc(NOME_ULS),
         NOME_CURTO = nfc(NOME_CURTO),
         NOME_PRETTY = uls_short_name(NOME_ULS))

uls_short <- uls_map |> st_drop_geometry() |> as_tibble() |>
  select(NOME_ULS, NOME_CURTO, NOME_PRETTY)

uls_means <- models$uls_means |>
  left_join(uls_short, by = c("unit_id" = "NOME_ULS"))

ppp_panel <- models$ppp_panel

# Period derived directly from the panel — never trust the CSV string.
year_range <- range(mobility$year)
period_label <- sprintf("%d-%d", year_range[1], year_range[2])

# Mainland Portugal bounding box (slightly padded). Used by the choropleth's
# fitBounds + setMaxBounds so users can't pan into the Atlantic and the default
# view doesn't include half of empty Spain.
PT_BBOX <- list(lng = c(-9.55, -6.10), lat = c(36.92, 42.18))

# ---- Headline numbers ------------------------------------------------------
headline_path <- file.path(proc_dir, "headline.csv")
headline <- if (file.exists(headline_path)) {
  readr::read_csv(headline_path, show_col_types = FALSE) |> tibble::deframe()
} else c()

# Format helpers — fully vectorised so they work both inside scalar contexts
# (renderText) and vector contexts (ggplot aes(text = sprintf(...))).
fmt_int <- function(x) {
  ifelse(is.na(x), "—",
         formatC(round(x), format = "d", big.mark = ","))
}
fmt_signed <- function(x) {
  ifelse(is.na(x), "—",
         paste0(ifelse(x >= 0, "+", "−"),
                formatC(abs(round(x)), format = "d", big.mark = ",")))
}
fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "—",
         paste0(ifelse(x >= 0, "+", "−"),
                formatC(abs(x) * 100, format = "f", digits = digits), "%"))
}
# Convert mobility_ratio (deliveries / resident_births, e.g. 1.87 for Coimbra)
# to a deficit/surplus percentage (+87% magnet, -55% exporter).
ratio_to_surplus <- function(r) r - 1

# ---- Theme + CSS -----------------------------------------------------------
ACCENT  <- "#0F4C81"
EXPORT  <- "#B2182B"
IMPORT  <- "#1A5276"
NEUTRAL <- "#F2F2F2"

theme <- bs_theme(
  version    = 5,
  base_font  = font_google("Inter"),
  heading_font = font_google("Inter"),
  bg         = "#FAFBFC",
  fg         = "#1F2937",
  primary    = ACCENT,
  "border-color"        = "#E5E7EB",
  "card-border-color"   = "#E5E7EB",
  "card-cap-bg"         = "#FFFFFF",
  "card-bg"             = "#FFFFFF",
  "navbar-light-bg"     = "#FFFFFF"
)

custom_css <- "
  body, .navbar, .card, .form-control, .nav-link {
    font-feature-settings: 'tnum' 1, 'cv11' 1;
  }
  .navbar { border-bottom: 1px solid #E5E7EB; box-shadow: none; }
  .navbar-brand { font-weight: 600; letter-spacing: -0.01em; }
  h1, h2, h3, h4, .card-header { font-weight: 600; letter-spacing: -0.01em; }
  .card { box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04); border-radius: 10px; }
  .card-header { background: #FFFFFF; border-bottom: 1px solid #F3F4F6;
                 font-size: 0.78rem; text-transform: uppercase;
                 letter-spacing: 0.04em; color: #6B7280; }
  .lede { font-size: 1.125rem; line-height: 1.55; color: #1F2937; max-width: 70ch; }
  .lede strong { color: #0F172A; font-weight: 600; }
  .why { font-size: 0.92rem; color: #4B5563; max-width: 70ch; margin-top: 0.4rem; }
  .explainer { background: #F8FAFC; border-left: 3px solid #0F4C81;
               padding: 0.65rem 0.95rem; border-radius: 0 6px 6px 0;
               font-size: 0.88rem; color: #334155; }
  .explainer strong { color: #0F172A; }
  .year-bar { display: flex; align-items: center; gap: 0.75rem;
              padding: 0.5rem 0; }
  .year-bar label { margin: 0; font-size: 0.78rem; text-transform: uppercase;
                    letter-spacing: 0.04em; color: #6B7280; }
  .stat-num { font-variant-numeric: tabular-nums; font-weight: 600; }
  .rank-row { display: flex; justify-content: space-between;
              padding: 0.35rem 0; border-bottom: 1px solid #F3F4F6;
              font-variant-numeric: tabular-nums; }
  .rank-row:last-child { border-bottom: 0; }
  .rank-row .name { color: #1F2937; }
  .rank-row .val  { font-weight: 600; }
  .rank-import .val { color: #1A5276; }
  .rank-export .val { color: #B2182B; }
  .leaflet-container { font-family: 'Inter', sans-serif; background: #FAFBFC; }
  .leaflet-tooltip { font-family: 'Inter', sans-serif; padding: 6px 10px;
                     border-radius: 6px; border: 1px solid #E5E7EB;
                     box-shadow: 0 1px 2px rgba(15,23,42,0.06);
                     font-size: 0.86rem; }
  table.dataTable { font-variant-numeric: tabular-nums; }

  /* KPI value boxes — moderate size, no clipping. */
  .bslib-value-box {
    min-height: 102px !important;
    border-radius: 10px;
  }
  .bslib-value-box .value-box-area {
    padding: 0.7rem 0.85rem !important;
    line-height: 1.2;
    justify-content: center;
  }
  .bslib-value-box .value-box-title {
    font-size: 0.76rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    opacity: 0.92;
    margin-bottom: 0.3rem;
    white-space: normal;
  }
  .bslib-value-box .value-box-value {
    font-size: 1.85rem !important;
    font-weight: 700 !important;
    letter-spacing: -0.02em;
    line-height: 1.05;
  }
  .bslib-value-box .value-box-showcase { padding-left: 0.75rem; padding-right: 0.5rem; }
  .bslib-value-box .value-box-showcase i, .bslib-value-box .value-box-showcase svg {
    font-size: 1.85rem;
    width: 1.85rem; height: 1.85rem;
  }

  /* Force the choropleth container to its declared height and stretch leaflet
     to fill it — without this, the card body can collapse the iframe to a
     fraction of the requested 720 px. */
  .map-card { min-height: 760px; }
  .map-card .card-body { padding: 0 !important; height: 720px; }
  .map-card .leaflet-container { height: 720px !important; width: 100% !important; }

  /* Slider tweaks for the year navigator. */
  .irs-bar, .irs-bar-edge { background: #0F4C81 !important; border-color: #0F4C81 !important; }
  .irs-from, .irs-to, .irs-single { background: #0F4C81 !important; }
  .irs-grid-text { color: #6B7280 !important; }

  /* Lede block — keep it tight, no overlap with the explainer. */
  .lede-block { display: flex; flex-direction: column; gap: 0.85rem; max-width: 78ch; }
  .legend-tip { font-size: 0.72rem; color: #6B7280; margin-top: 4px; }

  /* Hypotheses tab — typography for the question / test / outcome blocks. */
  .hyp-q, .hyp-test, .hyp-out { margin-bottom: 0.55rem; line-height: 1.5; color: #1F2937; font-size: 0.92rem; }
  .hyp-test { color: #334155; }
  .hyp-q strong, .hyp-test strong, .hyp-out strong { color: #0F172A; font-weight: 600; }
  .hyp-test em { color: #0F4C81; font-style: normal; font-weight: 600; }
  .hyp-out {
    background: #F8FAFC; border-radius: 8px; padding: 0.55rem 0.85rem;
    font-variant-numeric: tabular-nums; font-size: 0.9rem;
    border-left: 3px solid #E5E7EB;
  }
  .hyp-out.reject { border-left-color: #10B981; }
  .hyp-out.ns     { border-left-color: #9CA3AF; }
  .verdict-pill { display: inline-block; padding: 1px 8px; border-radius: 999px;
                   font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em;
                   font-weight: 700; margin-left: 0.5rem; vertical-align: middle; }
  .verdict-reject { background: #ECFDF5; color: #065F46; }
  .verdict-ns     { background: #F3F4F6; color: #6B7280; }
"

# ---- UI helpers ------------------------------------------------------------
mobility_palette <- function(domain_abs) {
  colorNumeric(c(EXPORT, NEUTRAL, IMPORT),
               domain = c(-domain_abs, domain_abs),
               na.color = "#E5E7EB")
}

rank_block <- function(df, value_col, css_class, n = 7) {
  df <- df |> head(n)
  rows <- mapply(function(name, val) {
    tags$div(class = paste("rank-row", css_class),
             tags$span(class = "name", name),
             tags$span(class = "val", fmt_signed(val)))
  }, df$NOME_PRETTY, df[[value_col]], SIMPLIFY = FALSE, USE.NAMES = FALSE)
  do.call(tagList, rows)
}

# ---- UI --------------------------------------------------------------------
ui <- page_navbar(
  id = "main_nav",
  title = "Births in Portugal",
  theme = theme,
  header = tags$head(
    tags$style(HTML(custom_css)),
    tags$meta(name = "viewport",
              content = "width=device-width, initial-scale=1")
  ),

  # ---- Tab 1: OVERVIEW ----------------------------------------------------
  nav_panel(
    "Overview",

    div(class = "lede-block",
      p(class = "lede",
        HTML(paste0(
          "Do mothers in Portugal deliver in their own region? Across ",
          "the 39 mainland Unidades Locais de Saúde (",
          tags$strong(period_label),
          "), only ",
          tags$strong(sprintf("%s%%", headline["share_positive_mobility"])),
          " are net importers of deliveries — the other ",
          sprintf("%d ULS", 39 - round(as.numeric(headline["share_positive_mobility"]) / 100 * 39)),
          " export births to other ULS or to private hospitals."
        ))),
      p(class = "why",
        "If a woman delivers outside her resident ULS, her prenatal record stays behind. ",
        "This dashboard quantifies the mismatch — and the case for portable maternal health records across SNS institutions."
      ),
      div(class = "explainer",
          tags$strong("Mobility"),
          " = hospital deliveries inside the ULS − births to its residents. ",
          tags$span(style = sprintf("color:%s; font-weight:600;", IMPORT), "Positive = magnet"),
          "  ·  ",
          tags$span(style = sprintf("color:%s; font-weight:600;", EXPORT), "Negative = exporter"),
          tags$span(class = "legend-tip",
                    " · Click a ULS on the map to see its detail.")
      ),
      div(class = "year-bar",
          tags$label("Filter by year"),
          div(style = "flex: 1; max-width: 560px;",
              sliderInput("year_overview", label = NULL,
                          min = year_range[1], max = year_range[2],
                          value = year_range[2], step = 1, sep = "",
                          ticks = TRUE,
                          animate = animationOptions(interval = 1100,
                                                      loop = FALSE),
                          width = "100%"))
      )
    ),

    layout_column_wrap(
      width = 1/4, gap = "0.75rem", heights_equal = "row",
      value_box(
        title = "ULS analysed",
        value = textOutput("kpi_n_uls", inline = TRUE),
        showcase = bs_icon("hospital"),
        theme = "primary"
      ),
      value_box(
        title = "Net importers",
        value = textOutput("kpi_pct_pos", inline = TRUE),
        showcase = bs_icon("arrow-down-circle"),
        theme = "secondary"
      ),
      value_box(
        title = textOutput("kpi_mean_label", inline = TRUE),
        value = textOutput("kpi_mean", inline = TRUE),
        showcase = bs_icon("activity"),
        theme = "secondary"
      ),
      value_box(
        title = "Period",
        value = textOutput("kpi_period", inline = TRUE),
        showcase = bs_icon("calendar3"),
        theme = "secondary"
      )
    ),

    br(),

    layout_columns(
      col_widths = c(9, 3),
      card(
        class = "map-card",
        card_header(textOutput("map_title", inline = TRUE)),
        leafletOutput("map_choropleth", height = "720px")
      ),
      div(
        card(
          card_header("Top 7 net importers"),
          div(style = "padding: 0.4rem 1rem 0.6rem 1rem;",
              uiOutput("rank_import"))
        ),
        br(),
        card(
          card_header("Top 7 net exporters"),
          div(style = "padding: 0.4rem 1rem 0.6rem 1rem;",
              uiOutput("rank_export"))
        )
      )
    )
  ),

  # ---- Tab 2: BY ULS -------------------------------------------------------
  nav_panel(
    "By ULS",
    layout_sidebar(
      sidebar = sidebar(
        width = 280,
        sliderInput("year_explorer", "Year",
                    min = year_range[1], max = year_range[2],
                    value = year_range[2], step = 1, sep = ""),
        helpText(
          "Each point is one ULS in the chosen year. Above the dashed line: more deliveries than residents (net importer). ",
          "Below: residents leave their ULS to deliver elsewhere."
        )
      ),
      card(
        card_header("Hospital deliveries vs resident births"),
        plotlyOutput("plot_obs_vs_exp", height = 420)
      ),
      card(
        card_header("Per-ULS detail"),
        DTOutput("table_uls")
      )
    )
  ),

  # ---- Tab 3: OVER TIME ----------------------------------------------------
  nav_panel(
    "Over time",
    layout_columns(
      col_widths = c(12),
      card(
        card_header("National mobility trend (lmer fit)"),
        plotlyOutput("plot_trend", height = 280)
      ),
      card(
        card_header("Mobility per ULS, by year"),
        plotlyOutput("plot_heatmap", height = 620)
      )
    )
  ),

  # ---- Tab 4: HYPOTHESES ---------------------------------------------------
  nav_panel(
    "Hypotheses",

    div(class = "lede-block",
      p(class = "lede",
        HTML("Four pre-registered hypotheses, one statistical test each — chosen to match what the data can and cannot say.")),
      p(class = "why",
        "Unit of analysis: the 39 mainland ULS (PPPs reported separately). Each test is run on the per-ULS mean over 2014-2024 unless stated otherwise.")
    ),

    layout_columns(
      col_widths = c(6, 6),

      # H1 ---------------------------------------------------------------
      card(
        card_header(uiOutput("h1_header")),
        div(style = "padding: 0.4rem 1.1rem 0.6rem 1.1rem;",
            tags$div(class = "hyp-q",
                     tags$strong("Question. "),
                     "Are Portuguese ULS in balance, on average — does the typical ULS deliver as many babies as it has resident births?"),
            tags$div(class = "hyp-test",
                     tags$strong("Test. "),
                     "One-sample t-test on the 39 per-ULS mean mobility values against the null mean 0. ",
                     tags$em("Why this one: "), "collapsing to one number per ULS gives 39 IID observations; the panel itself is autocorrelated and would violate the t-test's assumptions."),
            tags$div(class = "hyp-out",
                     uiOutput("h1_result")),
            plotlyOutput("plot_h1", height = 260))
      ),

      # H2 ---------------------------------------------------------------
      card(
        card_header(uiOutput("h2_header")),
        div(style = "padding: 0.4rem 1.1rem 0.6rem 1.1rem;",
            tags$div(class = "hyp-q",
                     tags$strong("Question. "),
                     "Do the 6 urban tertiary ULS (Santa Maria, São José, Lisboa Ocidental, São João, Santo António, Coimbra) absorb more deliveries than the 33 peripheral ULS?"),
            tags$div(class = "hyp-test",
                     tags$strong("Test. "),
                     "Wilcoxon rank-sum on per-ULS mean mobility, urban tertiary vs peripheral. ",
                     tags$em("Why this one: "), "Wilcoxon makes no normality assumption and is robust to the heavy tails the mobility distribution has — n = 6 vs 33 is too small for a t-test."),
            tags$div(class = "hyp-out",
                     uiOutput("h2_result")),
            plotlyOutput("plot_h2", height = 260))
      ),

      # H3 ---------------------------------------------------------------
      card(
        card_header(uiOutput("h3_header")),
        div(style = "padding: 0.4rem 1.1rem 0.6rem 1.1rem;",
            tags$div(class = "hyp-q",
                     tags$strong("Question. "),
                     "Is the mismatch between residents and SNS deliveries widening over the decade?"),
            tags$div(class = "hyp-test",
                     tags$strong("Test. "),
                     "Linear mixed-effects model: ", tags$code("lmer(mobility ~ year + (1 | uls))"), ", with lmerTest's Satterthwaite df for the year coefficient. ",
                     tags$em("Why this one: "), "the random intercept on ULS absorbs huge level differences (Coimbra +2,213/yr vs Amadora-Sintra -3,280/yr) so the year effect is identified from the within-ULS time signal, not between-ULS variation."),
            tags$div(class = "hyp-out",
                     uiOutput("h3_result")),
            plotlyOutput("plot_h3", height = 260))
      ),

      # H4 ---------------------------------------------------------------
      card(
        card_header(uiOutput("h4_header")),
        div(style = "padding: 0.4rem 1.1rem 0.6rem 1.1rem;",
            tags$div(class = "hyp-q",
                     tags$strong("Question. "),
                     "Are magnets and exporters scattered randomly across Portugal, or do they cluster — neighbours behaving like neighbours?"),
            tags$div(class = "hyp-test",
                     tags$strong("Test. "),
                     "Moran's I on the 39 ULS-level mean mobility values, with a k = 5 nearest-neighbour spatial weights matrix on ULS polygon centroids. ",
                     tags$em("Why this one: "), "Moran's I is the standard global test for spatial autocorrelation; k = 5 NN avoids the boundary issues of contiguity-based weights when ULS polygons are very irregular in size."),
            tags$div(class = "hyp-out",
                     uiOutput("h4_result")),
            plotlyOutput("plot_h4", height = 260))
      )
    )
  ),

  # ---- Tab 5: SOURCES ------------------------------------------------------
  nav_panel(
    "Sources",
    layout_columns(
      col_widths = c(7, 5),
      card(
        card_header("Open datasets"),
        div(style = "padding: 0.75rem 1.1rem;",
            tags$ul(style = "margin: 0; padding-left: 1.1rem; line-height: 1.7;",
              tags$li(tags$a("Transparência SNS — Partos e Cesarianas",
                             href = "https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/",
                             target = "_blank"),
                      " · monthly cumulative-YTD deliveries per public hospital, 2013→present"),
              tags$li(tags$a("PORDATA — Nados-vivos por município",
                             href = "https://www.pordata.pt", target = "_blank"),
                      " · annual live births by município of residence"),
              tags$li(tags$a("ulsportugal R package",
                             href = "https://github.com/danielrodriguescode/ulsportugal",
                             target = "_blank"),
                      " · 39 mainland ULS sf polygons + concelho→ULS dictionary"),
              tags$li(tags$a("Project repository",
                             href = "https://github.com/danielrodriguescode/births-portugal-data-portability",
                             target = "_blank"),
                      " · pipeline source code and reproducibility notes")
            )
        )
      ),
      card(
        card_header("Public-private partnerships"),
        div(style = "padding: 0.6rem 1rem 0.9rem 1rem;",
            p(style = "color: #4B5563; font-size: 0.9rem; margin-bottom: 0.6rem;",
              "Four PPP hospitals — Cascais, Loures, Braga, Vila Franca de Xira — are SNS-funded but lack a defined ULS catchment. ",
              "Reported separately, excluded from the 39-ULS analysis above."),
            DTOutput("table_ppp"))
      )
    )
  )
)

# ---- Server ----------------------------------------------------------------
server <- function(input, output, session) {

  # Reactive: per-ULS data for the selected year (slider value, integer).
  uls_for_year <- reactive({
    yr <- as.integer(input$year_overview %||% year_range[2])
    yr_data <- mobility |> filter(year == yr) |>
      select(unit_id, mobility, deliveries, resident_births, mobility_ratio)
    uls_map |>
      left_join(yr_data, by = c("NOME_ULS" = "unit_id")) |>
      rename(value = mobility)
  })

  # KPIs — each reacts to the year selector
  output$kpi_n_uls   <- renderText(formatC(39, big.mark = ","))
  output$kpi_period  <- renderText(period_label)
  output$kpi_pct_pos <- renderText({
    df <- uls_for_year()
    n <- sum(!is.na(df$value))
    if (n == 0) "—" else sprintf("%.1f%%",
                                  mean(df$value > 0, na.rm = TRUE) * 100)
  })
  output$kpi_mean    <- renderText({
    df <- uls_for_year()
    if (all(is.na(df$value))) "—" else
      paste(fmt_signed(mean(df$value, na.rm = TRUE)), "deliv./yr")
  })
  output$kpi_mean_label <- renderText({
    sprintf("Mean mobility, %s", input$year_overview %||% year_range[2])
  })

  # Map title reflects selection
  output$map_title <- renderText({
    sprintf("ULS mobility, %s", input$year_overview %||% year_range[2])
  })

  # Top-5 ranks
  output$rank_import <- renderUI({
    df <- uls_for_year() |>
      st_drop_geometry() |> as_tibble() |>
      filter(!is.na(value)) |>
      arrange(desc(value))
    rank_block(df, "value", "rank-import")
  })
  output$rank_export <- renderUI({
    df <- uls_for_year() |>
      st_drop_geometry() |> as_tibble() |>
      filter(!is.na(value)) |>
      arrange(value)
    rank_block(df, "value", "rank-export")
  })


  # Choropleth
  output$map_choropleth <- renderLeaflet({
    df <- uls_for_year()
    finite_vals <- df$value[is.finite(df$value)]
    if (length(finite_vals) == 0) {
      return(
        leaflet() |>
          addProviderTiles(providers$CartoDB.PositronNoLabels) |>
          fitBounds(PT_BBOX$lng[1], PT_BBOX$lat[1],
                    PT_BBOX$lng[2], PT_BBOX$lat[2])
      )
    }
    domain_abs <- max(abs(finite_vals), na.rm = TRUE)
    pal <- mobility_palette(domain_abs)
    surplus_pct <- if ("mobility_ratio" %in% names(df))
      ifelse(is.na(df$mobility_ratio), "—",
             fmt_pct(ratio_to_surplus(df$mobility_ratio))) else
      rep("—", nrow(df))
    deliveries_str <- if ("deliveries" %in% names(df))
      fmt_int(df$deliveries) else rep("—", nrow(df))
    residents_str <- if ("resident_births" %in% names(df))
      fmt_int(df$resident_births) else rep("—", nrow(df))
    label <- sprintf(
      "<div style='font-weight:600; color:#0F172A; font-size:0.92rem;'>%s</div>
       <div style='margin-top:4px; color:#1F2937;'>Mobility: <span class='stat-num' style='font-weight:600;'>%s</span> <span style='color:#6B7280;'>(%s)</span></div>
       <div style='color:#6B7280; font-size:0.78rem; margin-top:2px;'>Deliveries %s · Residents %s</div>",
      df$NOME_PRETTY,
      ifelse(is.na(df$value), "n/a", fmt_signed(df$value)),
      surplus_pct,
      deliveries_str, residents_str
    ) |> lapply(htmltools::HTML)
    leaflet(df, options = leafletOptions(minZoom = 6, maxZoom = 11)) |>
      addProviderTiles(providers$CartoDB.PositronNoLabels) |>
      fitBounds(PT_BBOX$lng[1], PT_BBOX$lat[1],
                PT_BBOX$lng[2], PT_BBOX$lat[2]) |>
      setMaxBounds(PT_BBOX$lng[1] - 1.5, PT_BBOX$lat[1] - 1.0,
                   PT_BBOX$lng[2] + 1.5, PT_BBOX$lat[2] + 1.0) |>
      addPolygons(fillColor = ~pal(value),
                  weight = 0.6, color = "#FFFFFF",
                  fillOpacity = 0.78,
                  label = label,
                  layerId = ~NOME_ULS,
                  highlightOptions = highlightOptions(weight = 2,
                                                     color = ACCENT,
                                                     bringToFront = TRUE)) |>
      addLegend("bottomright", pal = pal, values = ~value,
                title = htmltools::HTML(
                  "<div style='font-weight:600;'>Mobility</div>
                   <div style='font-size:0.7rem; color:#6B7280; font-weight:400;'>deliveries / yr · + magnet · − exporter</div>"),
                opacity = 0.85, na.label = "n/a",
                labFormat = function(type, cuts, p) {
                  paste0(ifelse(cuts >= 0, "+", "−"),
                         formatC(abs(cuts), big.mark = ",", format = "d"))
                })
  })

  # Click a polygon → switch to By ULS tab (and remember the chosen year + ULS).
  selected_uls <- reactiveVal(NULL)
  observeEvent(input$map_choropleth_shape_click, {
    click <- input$map_choropleth_shape_click
    if (is.null(click$id)) return()
    selected_uls(click$id)
    yr <- as.integer(input$year_overview %||% year_range[2])
    updateSliderInput(session, "year_explorer", value = yr)
    updateNavbarPage_safe <- function() {
      if (exists("updateNavbarPage", mode = "function")) {
        updateNavbarPage(session, "main_nav", selected = "By ULS")
      } else {
        nav_select("main_nav", "By ULS", session = session)
      }
    }
    updateNavbarPage_safe()
  })

  # By-ULS scatter + table
  filtered_explorer <- reactive({
    mobility |> filter(year == input$year_explorer) |>
      left_join(uls_short, by = c("unit_id" = "NOME_ULS"))
  })

  output$plot_obs_vs_exp <- renderPlotly({
    df <- filtered_explorer()
    if (nrow(df) == 0) return(NULL)
    p <- ggplot(df, aes(resident_births, deliveries,
                        text = sprintf(
                          "%s<br>Deliveries: %s · Residents: %s<br>Mobility: %s (%s)",
                          NOME_PRETTY,
                          fmt_int(deliveries), fmt_int(resident_births),
                          fmt_signed(mobility),
                          fmt_pct(ratio_to_surplus(mobility_ratio))))) +
      geom_abline(slope = 1, intercept = 0, colour = "#9CA3AF",
                  linetype = "dashed") +
      geom_point(aes(colour = mobility), size = 3.2, alpha = 0.92) +
      scale_colour_gradient2(low = EXPORT, mid = NEUTRAL, high = IMPORT,
                             midpoint = 0, name = "Mobility") +
      scale_x_continuous(labels = comma) +
      scale_y_continuous(labels = comma) +
      labs(x = "Resident births (PORDATA)",
           y = "Hospital deliveries (SNS)") +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank(),
            axis.text = element_text(colour = "#374151"),
            axis.title = element_text(colour = "#374151"))
    ggplotly(p, tooltip = "text") |>
      config(displayModeBar = FALSE)
  })

  output$table_uls <- renderDT({
    sel <- selected_uls()
    df <- filtered_explorer() |>
      transmute(ULS = NOME_PRETTY,
                NOME_ULS = unit_id,
                Deliveries = round(deliveries),
                `Resident births` = round(resident_births),
                Mobility = round(mobility),
                Ratio = fmt_pct(ratio_to_surplus(mobility_ratio)))
    selection <- if (!is.null(sel)) which(df$NOME_ULS == sel) else integer(0)
    df |>
      select(-NOME_ULS) |>
      datatable(rownames = FALSE,
                options = list(pageLength = 12, dom = "tip",
                               order = list(list(3, "asc"))),
                selection = list(mode = "single", selected = selection))
  })

  # Over-time plots
  output$plot_trend <- renderPlotly({
    df <- mobility |>
      group_by(year) |>
      summarise(mean_mobility = mean(mobility, na.rm = TRUE), .groups = "drop")
    beta <- as.numeric(headline["h3_year_coef"])
    pval <- headline["h3_year_p"]
    annot <- if (!is.na(beta))
      sprintf("Trend: %s deliv./ULS/yr · p = %s",
              fmt_signed(beta), pval) else ""
    p <- ggplot(df, aes(year, mean_mobility,
                        text = sprintf("Year %d<br>Mean mobility: %s",
                                       year, fmt_signed(mean_mobility)))) +
      geom_hline(yintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_smooth(aes(group = 1), method = "lm", se = TRUE,
                  colour = ACCENT, fill = "#DBEAFE", linewidth = 0.8) +
      geom_point(colour = ACCENT, size = 3) +
      scale_y_continuous(labels = comma) +
      labs(x = NULL, y = "Mean mobility (deliveries/ULS)",
           subtitle = annot) +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank(),
            plot.subtitle = element_text(size = 10, colour = "#6B7280",
                                          margin = margin(b = 6)))
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })

  output$plot_heatmap <- renderPlotly({
    df <- mobility |>
      left_join(uls_short, by = c("unit_id" = "NOME_ULS")) |>
      group_by(unit_id, NOME_PRETTY) |>
      mutate(overall = mean(mobility)) |>
      ungroup() |>
      mutate(NOME_PRETTY = fct_reorder(NOME_PRETTY, overall))
    p <- ggplot(df, aes(year, NOME_PRETTY, fill = mobility,
                        text = sprintf("%s — %d<br>Mobility: %s",
                                       NOME_PRETTY, year,
                                       fmt_signed(mobility)))) +
      geom_tile(colour = "white", linewidth = 0.4) +
      scale_fill_gradient2(low = EXPORT, mid = NEUTRAL, high = IMPORT,
                            midpoint = 0, labels = comma, name = "Mobility") +
      labs(x = NULL, y = NULL) +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid = element_blank(),
            axis.text.y = element_text(size = 9, colour = "#374151"),
            axis.text.x = element_text(colour = "#374151"))
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })

  output$table_ppp <- renderDT({
    ppp_panel |>
      mutate(across(c(deliveries, cesarianas), round)) |>
      transmute(Hospital = unit_id, Year = year,
                Deliveries = deliveries, Caesareans = cesarianas) |>
      arrange(Hospital, Year) |>
      datatable(rownames = FALSE,
                options = list(pageLength = 8, dom = "tip"))
  })

  # =====================================================================
  # Hypotheses tab — UI helpers + plots
  # =====================================================================
  verdict_pill <- function(p) {
    ok <- !is.na(p) && p < 0.05
    cls <- if (ok) "verdict-pill verdict-reject" else "verdict-pill verdict-ns"
    tag <- if (ok) "Reject H₀" else "n.s."
    tags$span(class = cls, tag)
  }
  hyp_outcome_class <- function(p) {
    if (!is.na(p) && p < 0.05) "hyp-out reject" else "hyp-out ns"
  }
  hyp_header <- function(label, p) {
    tagList(span(label), verdict_pill(p))
  }

  # ---- H1 -----------------------------------------------------------------
  output$h1_header <- renderUI({
    hyp_header("H1 · Mean ULS mobility ≠ 0",
               as.numeric(headline["h1_p"]))
  })
  output$h1_result <- renderUI({
    p_val <- as.numeric(headline["h1_p"])
    div(class = hyp_outcome_class(p_val),
        tags$strong("Result. "),
        sprintf("t = %s (df 38) · p = %s · mean = %s deliv./yr · 95%% CI %s. ",
                headline["h1_t"], headline["h1_p"],
                headline["h1_estimate"], headline["h1_ci"]),
        if (!is.na(p_val) && p_val < 0.05)
          tags$em("Most ULS are net exporters; the gap is real.") else
          tags$em("Cannot reject the null."))
  })
  output$plot_h1 <- renderPlotly({
    df <- models$uls_means |>
      left_join(uls_short, by = c("unit_id" = "NOME_ULS")) |>
      mutate(NOME_PRETTY = uls_short_name(unit_id)) |>
      arrange(mean_mobility) |>
      mutate(NOME_PRETTY = factor(NOME_PRETTY, levels = NOME_PRETTY))
    mean_val <- as.numeric(headline["h1_estimate"])
    ci_lo <- models$h1$conf.int[1]
    ci_hi <- models$h1$conf.int[2]
    p <- ggplot(df, aes(x = mean_mobility, y = NOME_PRETTY,
                        text = sprintf("%s<br>Mean mobility: %s",
                                       NOME_PRETTY, fmt_signed(mean_mobility)))) +
      annotate("rect", xmin = ci_lo, xmax = ci_hi,
               ymin = -Inf, ymax = Inf, fill = ACCENT, alpha = 0.08) +
      geom_vline(xintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_vline(xintercept = mean_val, colour = ACCENT, linewidth = 0.8) +
      geom_point(aes(colour = mean_mobility), size = 2.4) +
      scale_colour_gradient2(low = EXPORT, mid = NEUTRAL, high = IMPORT,
                             midpoint = 0, guide = "none") +
      scale_x_continuous(labels = comma) +
      labs(x = "Mean mobility (deliveries / yr)", y = NULL,
           subtitle = sprintf("Vertical line: sample mean (%s). Shaded band: 95%% CI %s.",
                              fmt_signed(mean_val), headline["h1_ci"])) +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank(),
            axis.text.y = element_text(size = 7, colour = "#374151"),
            plot.subtitle = element_text(size = 9, colour = "#6B7280"))
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })

  # ---- H2 -----------------------------------------------------------------
  output$h2_header <- renderUI({
    hyp_header("H2 · Urban tertiary > peripheral",
               as.numeric(headline["h2_p"]))
  })
  output$h2_result <- renderUI({
    p_val <- as.numeric(headline["h2_p"])
    div(class = hyp_outcome_class(p_val),
        tags$strong("Result. "),
        sprintf("W = %s · p = %s · 95%% CI %s. ",
                headline["h2_W"], headline["h2_p"], headline["h2_diff_ci"]),
        if (p_val < 0.05) tags$em("Group difference detected.") else
          tags$em("The label is not predictive — Coimbra is the country's biggest magnet, while Lisboa Ocidental is among its biggest exporters."))
  })
  output$plot_h2 <- renderPlotly({
    df <- models$uls_means |>
      mutate(group = ifelse(urban_tertiary, "Urban tertiary", "Peripheral"),
             NOME_PRETTY = uls_short_name(unit_id))
    p <- ggplot(df, aes(x = group, y = mean_mobility,
                        text = sprintf("%s<br>%s<br>Mean mobility: %s",
                                       NOME_PRETTY, group, fmt_signed(mean_mobility)))) +
      geom_hline(yintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_boxplot(aes(group = group), width = 0.45,
                   fill = "#F1F5F9", colour = "#94A3B8",
                   outlier.shape = NA) +
      geom_jitter(aes(colour = mean_mobility), width = 0.12, size = 2.6,
                  alpha = 0.92) +
      scale_colour_gradient2(low = EXPORT, mid = NEUTRAL, high = IMPORT,
                             midpoint = 0, guide = "none") +
      scale_y_continuous(labels = comma) +
      labs(x = NULL, y = "Mean mobility (deliveries / yr)") +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank(),
            axis.text = element_text(colour = "#374151"))
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })

  # ---- H3 -----------------------------------------------------------------
  output$h3_header <- renderUI({
    hyp_header("H3 · Mobility drifts over time",
               as.numeric(headline["h3_year_p"]))
  })
  output$h3_result <- renderUI({
    p_val <- as.numeric(headline["h3_year_p"])
    div(class = hyp_outcome_class(p_val),
        tags$strong("Result. "),
        sprintf("β = %s deliveries/ULS/yr · 95%% CI %s · p = %s. ",
                headline["h3_year_coef"], headline["h3_year_ci"],
                headline["h3_year_p"]),
        if (p_val < 0.05) tags$em("Each year, the average ULS loses ~7.5 more deliveries than the year before — the gap is widening.") else
          tags$em("No detectable trend."))
  })
  output$plot_h3 <- renderPlotly({
    yearly <- mobility |>
      group_by(year) |>
      summarise(mean_mobility = mean(mobility, na.rm = TRUE), .groups = "drop")
    p <- ggplot(mobility, aes(year, mobility)) +
      geom_hline(yintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_jitter(aes(text = sprintf("%s — %d<br>Mobility: %s",
                                      uls_short_name(unit_id), year,
                                      fmt_signed(mobility))),
                  width = 0.18, height = 0, size = 1.4,
                  colour = "#CBD5E1", alpha = 0.65) +
      geom_smooth(data = yearly,
                  mapping = aes(year, mean_mobility),
                  method = "lm", se = TRUE,
                  colour = ACCENT, fill = "#DBEAFE",
                  linewidth = 0.9, inherit.aes = FALSE) +
      geom_point(data = yearly,
                 mapping = aes(year, mean_mobility,
                               text = sprintf("%d national mean<br>%s",
                                              year, fmt_signed(mean_mobility))),
                 colour = ACCENT, size = 3, inherit.aes = FALSE) +
      scale_y_continuous(labels = comma) +
      labs(x = NULL, y = "Mobility (deliveries / yr)",
           subtitle = sprintf("Blue line: lmer year coefficient β = %s/yr (p = %s). Grey points = ULS-year observations.",
                              headline["h3_year_coef"], headline["h3_year_p"])) +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank(),
            plot.subtitle = element_text(size = 9, colour = "#6B7280",
                                          margin = margin(b = 4)))
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })

  # ---- H4 -----------------------------------------------------------------
  output$h4_header <- renderUI({
    hyp_header("H4 · Spatial clustering (Moran's I)",
               as.numeric(headline["h4_moran_p"]))
  })
  output$h4_result <- renderUI({
    p_val <- as.numeric(headline["h4_moran_p"])
    div(class = hyp_outcome_class(p_val),
        tags$strong("Result. "),
        sprintf("I = %s · p = %s. ",
                headline["h4_moran_I"], headline["h4_moran_p"]),
        if (p_val < 0.05) tags$em("Modest but significant — magnets cluster (Porto-Braga-Matosinhos corridor) and so do exporters (the Lisbon ring).") else
          tags$em("Spatial pattern not distinguishable from random."))
  })
  output$plot_h4 <- renderPlotly({
    df <- models$moran_scatter |>
      mutate(NOME_PRETTY = uls_short_name(unit_id))
    slope <- as.numeric(headline["h4_moran_I"])
    p <- ggplot(df, aes(x, y,
                        text = sprintf("%s<br>Standardised mobility: %.2f<br>Neighbour mean: %.2f<br>Quadrant: %s",
                                       NOME_PRETTY, x, y, quadrant))) +
      geom_hline(yintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_vline(xintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_abline(slope = slope, intercept = 0,
                  colour = ACCENT, linewidth = 0.9) +
      geom_point(aes(colour = quadrant), size = 2.6, alpha = 0.92) +
      scale_colour_manual(values = c("high-high" = IMPORT,
                                       "low-low"   = EXPORT,
                                       "high-low"  = "#94A3B8",
                                       "low-high"  = "#94A3B8"),
                          name = "Quadrant") +
      labs(x = "Mobility (z-score)",
           y = "Mean of 5 nearest neighbours (z-score)",
           subtitle = sprintf("Slope of the blue line is Moran's I = %s. High-high + low-low quadrants = positive autocorrelation.",
                              headline["h4_moran_I"])) +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank(),
            plot.subtitle = element_text(size = 9, colour = "#6B7280",
                                          margin = margin(b = 4)))
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })
}

shinyApp(ui, server)
