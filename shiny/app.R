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
  library(ulsportugal)
})

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

uls_map <- ulsportugal() |>
  mutate(NOME_ULS = nfc(NOME_ULS), NOME_CURTO = nfc(NOME_CURTO))

uls_short <- uls_map |> st_drop_geometry() |> as_tibble() |>
  select(NOME_ULS, NOME_CURTO)

uls_means <- models$uls_means |>
  left_join(uls_short, by = c("unit_id" = "NOME_ULS"))

ppp_panel <- models$ppp_panel

# Period derived directly from the panel — never trust the CSV string.
year_range <- range(mobility$year)
period_label <- sprintf("%d-%d", year_range[1], year_range[2])
year_choices <- c("Mean of all years" = "mean",
                  setNames(as.character(seq(year_range[1], year_range[2])),
                           seq(year_range[1], year_range[2])))

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
"

# ---- UI helpers ------------------------------------------------------------
mobility_palette <- function(domain_abs) {
  colorNumeric(c(EXPORT, NEUTRAL, IMPORT),
               domain = c(-domain_abs, domain_abs),
               na.color = "#E5E7EB")
}

rank_block <- function(df, value_col, css_class, n = 5) {
  df <- df |> head(n)
  rows <- mapply(function(name, val) {
    tags$div(class = paste("rank-row", css_class),
             tags$span(class = "name", name),
             tags$span(class = "val", fmt_signed(val)))
  }, df$NOME_CURTO, df[[value_col]], SIMPLIFY = FALSE, USE.NAMES = FALSE)
  do.call(tagList, rows)
}

# ---- UI --------------------------------------------------------------------
ui <- page_navbar(
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

    layout_column_wrap(
      width = 1, gap = "1rem",
      div(
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
        )
      ),
      div(class = "explainer",
          tags$strong("What is mobility? "),
          "For each ULS, ", tags$em("Hospital deliveries"), " (Transparência SNS) minus ",
          tags$em("Resident births"), " (PORDATA aggregated to ULS). ",
          "Positive = net importer (magnet). Negative = net exporter."
      ),
      div(class = "year-bar",
          tags$label("Filter by year"),
          div(style = "min-width: 220px;",
              selectInput("year_overview", label = NULL,
                          choices = year_choices,
                          selected = as.character(year_range[2]),
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
        full_screen = TRUE,
        card_header(textOutput("map_title", inline = TRUE)),
        leafletOutput("map_choropleth", height = 720)
      ),
      div(
        card(
          card_header("Top 5 net importers"),
          div(style = "padding: 0.5rem 1rem 0.75rem 1rem;",
              uiOutput("rank_import"))
        ),
        br(),
        card(
          card_header("Top 5 net exporters"),
          div(style = "padding: 0.5rem 1rem 0.75rem 1rem;",
              uiOutput("rank_export"))
        )
      )
    ),

    br(),

    card(
      card_header("Statistical evidence"),
      div(style = "padding: 0.5rem 1.5rem 0.9rem 1.5rem;",
          uiOutput("stat_evidence"))
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

  # ---- Tab 4: SOURCES ------------------------------------------------------
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

  # Reactive: per-ULS data for the selected year (or per-ULS mean over all years)
  uls_for_year <- reactive({
    sel <- input$year_overview
    if (is.null(sel) || sel == "mean") {
      uls_map |>
        left_join(uls_means |> select(unit_id, mean_mobility),
                  by = c("NOME_ULS" = "unit_id")) |>
        rename(value = mean_mobility)
    } else {
      yr <- as.integer(sel)
      yr_data <- mobility |> filter(year == yr) |>
        select(unit_id, mobility, deliveries, resident_births, mobility_ratio)
      uls_map |>
        left_join(yr_data, by = c("NOME_ULS" = "unit_id")) |>
        rename(value = mobility)
    }
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
    if (all(is.na(df$value))) "—" else fmt_signed(mean(df$value, na.rm = TRUE))
  })
  output$kpi_mean_label <- renderText({
    sel <- input$year_overview
    if (is.null(sel) || sel == "mean") "Mean mobility (per ULS / yr)" else
      sprintf("Mean mobility, %s", sel)
  })

  # Map title reflects selection
  output$map_title <- renderText({
    sel <- input$year_overview
    if (is.null(sel) || sel == "mean") "Mean ULS mobility" else
      sprintf("ULS mobility, %s", sel)
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

  # Statistical evidence (static — uses headline numbers, not year-filtered)
  output$stat_evidence <- renderUI({
    if (length(headline) == 0) return(p("Headline numbers unavailable."))
    rows <- list(
      list("H1 · mean ULS mobility ≠ 0",
           sprintf("t = %s, p = %s, mean = %s",
                   headline["h1_t"], headline["h1_p"], headline["h1_estimate"])),
      list("H2 · urban tertiary > peripheral",
           sprintf("W = %s, p = %s (n.s.)",
                   headline["h2_W"], headline["h2_p"])),
      list("H3 · drift over time (lmer)",
           sprintf("β = %s/yr, p = %s",
                   headline["h3_year_coef"], headline["h3_year_p"])),
      list("H4 · spatial clustering (Moran's I)",
           sprintf("I = %s, p = %s",
                   headline["h4_moran_I"], headline["h4_moran_p"]))
    )
    cells <- lapply(rows, function(r) {
      tags$div(style = "padding: 0.5rem 1rem; border-left: 1px solid #F3F4F6;",
               tags$div(style = "color: #6B7280; font-size: 0.74rem; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 0.25rem;", r[[1]]),
               tags$div(class = "stat-num", style = "color: #1F2937; font-size: 0.95rem;", r[[2]]))
    })
    # Drop the leading divider on the first cell so it doesn't show against the card edge.
    cells[[1]]$attribs$style <- sub("border-left: 1px solid #F3F4F6;", "",
                                    cells[[1]]$attribs$style, fixed = TRUE)
    tags$div(style = "display: grid; grid-template-columns: repeat(4, 1fr); gap: 0;",
             tagList(cells))
  })

  # Choropleth
  output$map_choropleth <- renderLeaflet({
    df <- uls_for_year()
    finite_vals <- df$value[is.finite(df$value)]
    if (length(finite_vals) == 0) {
      return(leaflet() |> addProviderTiles(providers$CartoDB.PositronNoLabels))
    }
    domain_abs <- max(abs(finite_vals), na.rm = TRUE)
    pal <- mobility_palette(domain_abs)
    df$mobility_ratio_pct <- if ("mobility_ratio" %in% names(df))
      ifelse(is.na(df$mobility_ratio), "",
             sprintf(" (%s)", fmt_pct(ratio_to_surplus(df$mobility_ratio)))) else ""
    label <- sprintf(
      "<div style='font-weight:600; color:#0F172A;'>%s</div>
       <div style='color:#374151;'>%s%s</div>",
      df$NOME_CURTO,
      ifelse(is.na(df$value), "n/a", fmt_signed(df$value)),
      df$mobility_ratio_pct
    ) |> lapply(htmltools::HTML)
    leaflet(df) |>
      addProviderTiles(providers$CartoDB.PositronNoLabels) |>
      addPolygons(fillColor = ~pal(value),
                  weight = 0.6, color = "#FFFFFF",
                  fillOpacity = 0.78,
                  label = label,
                  highlightOptions = highlightOptions(weight = 2,
                                                     color = ACCENT,
                                                     bringToFront = TRUE)) |>
      addLegend("bottomright", pal = pal, values = ~value,
                title = "Mobility", opacity = 0.85, na.label = "n/a")
  })

  # By-ULS scatter + table
  filtered_explorer <- reactive({
    mobility |> filter(year == input$year_explorer) |>
      left_join(uls_short, by = c("unit_id" = "NOME_ULS"))
  })

  output$plot_obs_vs_exp <- renderPlotly({
    df <- filtered_explorer()
    if (nrow(df) == 0) return(NULL)
    df$urban <- df$unit_id %in% URBAN_TERTIARY_ULS
    p <- ggplot(df, aes(resident_births, deliveries,
                        text = sprintf(
                          "%s<br>Deliveries: %s<br>Residents: %s<br>Mobility: %s (%s)",
                          NOME_CURTO,
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
    filtered_explorer() |>
      transmute(ULS = NOME_CURTO,
                Deliveries = round(deliveries),
                `Resident births` = round(resident_births),
                Mobility = round(mobility),
                Ratio = fmt_pct(ratio_to_surplus(mobility_ratio))) |>
      datatable(rownames = FALSE,
                options = list(pageLength = 12, dom = "tip",
                               order = list(list(3, "asc"))))
  })

  # Over-time plots
  output$plot_trend <- renderPlotly({
    df <- mobility |>
      group_by(year) |>
      summarise(mean_mobility = mean(mobility, na.rm = TRUE), .groups = "drop")
    p <- ggplot(df, aes(year, mean_mobility,
                        text = sprintf("Year %d<br>Mean mobility: %s",
                                       year, fmt_signed(mean_mobility)))) +
      geom_hline(yintercept = 0, colour = "#9CA3AF", linetype = "dashed") +
      geom_smooth(aes(group = 1), method = "lm", se = TRUE,
                  colour = ACCENT, fill = "#DBEAFE", linewidth = 0.8) +
      geom_point(colour = ACCENT, size = 3) +
      scale_y_continuous(labels = comma) +
      labs(x = NULL, y = "Mean mobility (deliveries/ULS)") +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid.minor = element_blank())
    ggplotly(p, tooltip = "text") |> config(displayModeBar = FALSE)
  })

  output$plot_heatmap <- renderPlotly({
    df <- mobility |>
      left_join(uls_short, by = c("unit_id" = "NOME_ULS")) |>
      group_by(unit_id, NOME_CURTO) |>
      mutate(overall = mean(mobility)) |>
      ungroup() |>
      mutate(NOME_CURTO = fct_reorder(NOME_CURTO, overall))
    p <- ggplot(df, aes(year, NOME_CURTO, fill = mobility,
                        text = sprintf("%s — %d<br>Mobility: %s",
                                       NOME_CURTO, year,
                                       fmt_signed(mobility)))) +
      geom_tile(colour = "white", linewidth = 0.4) +
      scale_fill_gradient2(low = EXPORT, mid = NEUTRAL, high = IMPORT,
                            midpoint = 0, labels = comma, name = "Mobility") +
      labs(x = NULL, y = NULL) +
      theme_minimal(base_family = "Inter") +
      theme(panel.grid = element_blank(),
            axis.text.y = element_text(size = 8, colour = "#374151"),
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
}

shinyApp(ui, server)
