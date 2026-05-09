# shiny/app.R
# Single-file Shiny entry point. Self-contained — reads pre-computed artefacts
# from shiny/data/, populated by deploy_app.R (or shiny::runApp from the repo
# root after run_all.R has produced fresh data/processed/*.rds).
#
# All paths in this file are RELATIVE to the app directory so the bundle works
# both locally and on shinyapps.io (where here::here() cannot find a project
# root). Do not reintroduce here::here() — see prompts.md 2026-05-09.

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
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

# Urban tertiary ULS used by the H2 grouping (inlined from R/region_crosswalk.R
# so the bundle has no out-of-folder dependencies). Names are NFC-normalised so
# joins behave on both macOS (NFD by default in some text editors) and Linux.
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

partos_uls   <- readRDS(file.path(proc_dir, "partos_uls.rds")) |>
  mutate(unit_id = nfc(unit_id))
pordata_uls  <- readRDS(file.path(proc_dir, "pordata_uls.rds")) |>
  mutate(uls = nfc(uls))
mobility     <- readRDS(file.path(proc_dir, "mobility_panel.rds")) |>
  mutate(unit_id = nfc(unit_id))
hospitals    <- readRDS(file.path(proc_dir, "hospitals.rds")) |>
  mutate(NOME_ULS = nfc(NOME_ULS), instituicao = nfc(instituicao))
models       <- readRDS(file.path(proc_dir, "models.rds"))

uls_map <- ulsportugal() |>
  mutate(NOME_ULS   = nfc(NOME_ULS),
         NOME_CURTO = nfc(NOME_CURTO))

uls_means <- models$uls_means |>
  left_join(uls_map |> st_drop_geometry() |> as_tibble() |>
              select(NOME_ULS, NOME_CURTO),
            by = c("unit_id" = "NOME_ULS"))

ppp_panel <- models$ppp_panel

# ---- Headline numbers ------------------------------------------------------
headline_path <- file.path(proc_dir, "headline.csv")
headline <- if (file.exists(headline_path)) {
  readr::read_csv(headline_path, show_col_types = FALSE) |> tibble::deframe()
} else c()

answer_text <- if (length(headline) > 0) {
  sprintf("Across %s ULS over %s, %s%% are net importers of deliveries (Mobility > 0). The mean ULS-level mobility is %s deliveries/year (95%% CI %s); spatial clustering is significant (Moran's I = %s, p = %s).",
          headline["n_uls"], headline["year_range"],
          headline["share_positive_mobility"], headline["h1_estimate"],
          headline["h1_ci"], headline["h4_moran_I"], headline["h4_moran_p"])
} else {
  "Pending analysis."
}

ui <- page_navbar(
  title  = "Births in Portugal — Hospital vs Resident Mobility",
  theme  = bs_theme(bootswatch = "flatly"),

  # ---- Tab 1: ANSWER --------------------------------------------------------
  nav_panel(
    "Answer",
    layout_column_wrap(
      width = 1,
      card(
        card_header("In one sentence"),
        card_body(
          h4(answer_text),
          p(em("Source: PORDATA (resident births by concelho) + Transparência SNS (hospital deliveries) + ulsportugal (concelho→ULS map). Period: 2014–2024."))
        )
      ),
      card(
        card_header("Methodological pivot"),
        card_body(
          p("This project initially used a capacity-weighted ", em("expected"), " formula to attribute regional births to hospitals. We replaced it with a ", strong("direct two-source comparison"), ":"),
          tags$pre("Mobility(ULS, year) = HospitalDeliveries(ULS, year) − ResidentBirths(ULS, year)"),
          p("Where ", strong("HospitalDeliveries"), " comes from Transparência SNS (where the baby was born) and ", strong("ResidentBirths"), " comes from PORDATA aggregated to ULS via the concelho→ULS map in the ", code("ulsportugal"), " package (where the mother lives). No capacity proxy, no redistribution. The difference IS the mobility.")
        )
      ),
      card(
        card_header("Statistical evidence"),
        card_body(
          tags$table(class = "table table-sm",
            tags$thead(tags$tr(
              tags$th("Hypothesis"), tags$th("Test"), tags$th("Result"))),
            tags$tbody(
              tags$tr(tags$td("H1: Mobility ≠ 0 across the 39 ULS"),
                      tags$td("One-sample t-test on per-ULS means"),
                      tags$td(sprintf("t = %s, p = %s; mean = %s",
                                      headline["h1_t"], headline["h1_p"],
                                      headline["h1_estimate"]))),
              tags$tr(tags$td("H2: urban tertiary ULS absorb more"),
                      tags$td("Wilcoxon (6 vs 33 ULS)"),
                      tags$td(sprintf("W = %s, p = %s",
                                      headline["h2_W"], headline["h2_p"]))),
              tags$tr(tags$td("H3: temporal drift"),
                      tags$td("lmer year coefficient"),
                      tags$td(sprintf("β = %s/year, 95%% CI %s, p = %s",
                                      headline["h3_year_coef"],
                                      headline["h3_year_ci"],
                                      headline["h3_year_p"]))),
              tags$tr(tags$td("H4: spatial clustering"),
                      tags$td("Moran's I on ULS centroids, k=5 NN"),
                      tags$td(sprintf("I = %s, p = %s",
                                      headline["h4_moran_I"],
                                      headline["h4_moran_p"])))
            )
          )
        )
      )
    )
  ),

  # ---- Tab 2: MAP -----------------------------------------------------------
  nav_panel(
    "Map",
    layout_sidebar(
      sidebar = sidebar(
        sliderInput("year_map", "Year",
                    min = min(mobility$year), max = max(mobility$year),
                    value = max(mobility$year), step = 1, sep = ""),
        radioButtons("metric_map", "Metric",
                     choices = c("Mean mobility (2014–2024)" = "mean_mobility",
                                 "Mobility (selected year)"  = "mobility_year",
                                 "Hospital deliveries"        = "deliveries",
                                 "Resident births"            = "resident_births"),
                     selected = "mean_mobility"),
        tags$small(em("Choropleth uses the 39 ULS sf polygons from the ulsportugal package."))
      ),
      leafletOutput("map_choropleth", height = 700)
    )
  ),

  # ---- Tab 3: ULS EXPLORER --------------------------------------------------
  nav_panel(
    "ULS Explorer",
    layout_sidebar(
      sidebar = sidebar(
        sliderInput("year_explorer", "Year",
                    min = min(mobility$year), max = max(mobility$year),
                    value = max(mobility$year), step = 1, sep = "")
      ),
      plotlyOutput("plot_obs_vs_exp", height = 450),
      DTOutput("table_uls")
    )
  ),

  # ---- Tab 4: HEATMAP -------------------------------------------------------
  nav_panel(
    "Heatmap",
    layout_sidebar(
      sidebar = sidebar(
        helpText("Mobility per ULS × year. Blue = net inflow, red = net outflow. ULS ordered by overall mean mobility.")
      ),
      plotlyOutput("plot_heatmap", height = 700)
    )
  ),

  # ---- Tab 5: PPP TABLE -----------------------------------------------------
  nav_panel(
    "PPP hospitals",
    card(
      card_header("Public-private partnership hospitals"),
      card_body(
        p("PPPs (Cascais, Loures, Braga, Vila Franca de Xira) are SNS-funded but operated by private contractors. They are reported here separately because they have hospital-level deliveries but no defined catchment area — assigning them to a ULS would distort that ULS's mobility figure."),
        p(strong("Excluded from H1–H4."), " See paper Discussion §Limitations."),
        DTOutput("table_ppp")
      )
    )
  ),

  # ---- Tab 6: METHODS -------------------------------------------------------
  nav_panel(
    "Methods (plain language)",
    card(
      card_header("How we got the answer"),
      card_body(
        p(strong("The question."), " For each of Portugal's 39 mainland ULS, do mothers living in that ULS deliver in that ULS's hospitals?"),
        p(strong("Two datasets."),
          tags$ol(
            tags$li(strong("PORDATA"), " — annual live births by ", em("concelho de residência da mãe"), " (where the mother lives). Aggregated to ULS via the ", code("ulsportugal"), " concelho→ULS map. For the 3 split concelhos (Lisboa, Loures, Porto) we allocate proportionally to the number of freguesias in each ULS."),
            tags$li(strong("Transparência SNS"), " — monthly cumulative-YTD deliveries per public hospital. The annual total per hospital is the December value; hospitals are mapped to ULS by direct name match (for the 39 hospitals named exactly after a ULS) and by spatial point-in-polygon for the rest.")
          )),
        p(strong("The metric."),
          tags$pre("Mobility(ULS, year) = HospitalDeliveries(ULS, year) − ResidentBirths(ULS, year)")),
        p("ULS where ", em("Mobility > 0"), " absorb deliveries from outside their catchment; ULS where ", em("Mobility < 0"), " export — their residents deliver elsewhere (other ULS, private hospitals, at home, abroad)."),
        p(strong("Why not capacity-weighted expected?"), " A previous draft used ", code("Expected = TotalBirths × Capacity / Σ Capacity"), ", which is circular — capacity is itself proxied by historical deliveries, so a hospital that has been a magnet for 50 years gets a high capacity, which makes its expected = observed and its mobility ≈ 0 by construction. The direct comparison above avoids this."),
        p(strong("The four hypotheses."),
          tags$ul(
            tags$li(strong("H1"), " — t-test: is mean ULS mobility different from zero?"),
            tags$li(strong("H2"), " — Wilcoxon: do urban tertiary ULS (Santa Maria, São José, Lisboa Ocidental, São João, Santo António, Coimbra) absorb more than peripheral ULS?"),
            tags$li(strong("H3"), " — mixed-effects model: is mobility drifting over time?"),
            tags$li(strong("H4"), " — Moran's I: does mobility cluster geographically across ULS centroids?")
          )),
        p(strong("Caveat."), " SNS captures roughly 80–87 % of Portugal's continental live births; the remaining 13–20 % go to private hospitals (concentrated in Lisboa, Porto, Algarve), at home, or abroad. National mean mobility is therefore biased downward by ~15 %. Spatial clustering and per-ULS rankings remain interpretable.")
      )
    )
  ),

  # ---- Tab 7: DATA ----------------------------------------------------------
  nav_panel(
    "Data",
    p("Source attribution and full reproducibility."),
    tags$ul(
      tags$li(tags$a("Transparência SNS — Partos e Cesarianas",
                     href = "https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/",
                     target = "_blank")),
      tags$li(tags$a("PORDATA — Nados-vivos por município",
                     href = "https://www.pordata.pt", target = "_blank")),
      tags$li(tags$a("ulsportugal R package",
                     href = "https://github.com/danielrodriguescode/ulsportugal",
                     target = "_blank"),
              " — sf geometries for the 39 ULS + concelho/freguesia → ULS dictionary"),
      tags$li(tags$a("Project repository",
                     href = "https://github.com/danielrodriguescode/births-portugal-data-portability",
                     target = "_blank"))
    )
  )
)

server <- function(input, output, session) {

  # ---- Map ------------------------------------------------------------------
  map_data <- reactive({
    base <- uls_map |>
      left_join(uls_means |> select(unit_id, mean_mobility),
                by = c("NOME_ULS" = "unit_id"))
    if (input$metric_map == "mean_mobility") {
      base$value <- base$mean_mobility
    } else {
      yr_data <- mobility |>
        filter(year == input$year_map) |>
        select(unit_id, mobility, deliveries, resident_births)
      base <- base |>
        left_join(yr_data, by = c("NOME_ULS" = "unit_id"))
      base$value <- switch(input$metric_map,
                            mobility_year   = base$mobility,
                            deliveries      = base$deliveries,
                            resident_births = base$resident_births)
    }
    base
  })

  output$map_choropleth <- renderLeaflet({
    df <- map_data()
    if (input$metric_map %in% c("mean_mobility", "mobility_year")) {
      pal <- colorNumeric(c("#b2182b", "#f7f7f7", "#2166ac"),
                          domain = c(-max(abs(df$value), na.rm = TRUE),
                                      max(abs(df$value), na.rm = TRUE)))
    } else {
      pal <- colorNumeric("YlOrRd", domain = df$value, na.color = "#cccccc")
    }
    label <- sprintf("%s: %s", df$NOME_CURTO,
                     ifelse(is.na(df$value), "n/a",
                             scales::comma(round(df$value))))
    leaflet(df) |>
      addProviderTiles(providers$CartoDB.Positron) |>
      addPolygons(fillColor = ~pal(value),
                  weight = 0.5, color = "white",
                  fillOpacity = 0.85,
                  label = label,
                  highlightOptions = highlightOptions(weight = 2, color = "#666",
                                                     bringToFront = TRUE)) |>
      addLegend("bottomright", pal = pal, values = ~value,
                title = switch(input$metric_map,
                                mean_mobility   = "Mean mobility",
                                mobility_year   = sprintf("Mobility %s", input$year_map),
                                deliveries      = "Deliveries",
                                resident_births = "Resident births"),
                opacity = 0.85, na.label = "n/a")
  })

  # ---- ULS Explorer (deliveries vs residents) -------------------------------
  filtered_explorer <- reactive({
    mobility |> filter(year == input$year_explorer)
  })

  output$plot_obs_vs_exp <- renderPlotly({
    df <- filtered_explorer() |>
      left_join(uls_map |> st_drop_geometry() |> as_tibble() |>
                  select(NOME_ULS, NOME_CURTO),
                by = c("unit_id" = "NOME_ULS"))
    if (nrow(df) == 0) return(NULL)
    p <- ggplot(df, aes(resident_births, deliveries,
                        colour = unit_id %in% URBAN_TERTIARY_ULS,
                        text = sprintf("%s<br>Deliveries: %s<br>Residents: %s<br>Mobility: %s",
                                       NOME_CURTO,
                                       comma(round(deliveries)),
                                       comma(round(resident_births)),
                                       comma(round(mobility))))) +
      geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "dashed") +
      geom_point(size = 3, alpha = 0.85) +
      scale_colour_manual(values = c("FALSE" = "#1f78b4", "TRUE" = "#b2182b"),
                          labels = c("Peripheral", "Urban tertiary"),
                          name = NULL) +
      scale_x_continuous(labels = comma) +
      scale_y_continuous(labels = comma) +
      labs(x = "Resident births (PORDATA)", y = "Hospital deliveries (SNS)",
           title = paste("Hospital deliveries vs resident births,", input$year_explorer)) +
      theme_minimal()
    ggplotly(p, tooltip = "text")
  })

  output$table_uls <- renderDT({
    filtered_explorer() |>
      left_join(uls_map |> st_drop_geometry() |> as_tibble() |>
                  select(NOME_ULS, NOME_CURTO),
                by = c("unit_id" = "NOME_ULS")) |>
      transmute(ULS = NOME_CURTO,
                Deliveries = round(deliveries),
                `Resident births` = round(resident_births),
                Mobility = round(mobility),
                `Mobility ratio` = round(mobility_ratio, 2)) |>
      datatable(rownames = FALSE, options = list(pageLength = 12)) |>
      formatStyle("Mobility",
                  background = styleColorBar(c(-3500, 3500),
                                              c("#fdb863", "#b2abd2")))
  })

  # ---- Heatmap --------------------------------------------------------------
  output$plot_heatmap <- renderPlotly({
    df <- mobility |>
      left_join(uls_map |> st_drop_geometry() |> as_tibble() |>
                  select(NOME_ULS, NOME_CURTO),
                by = c("unit_id" = "NOME_ULS")) |>
      group_by(unit_id, NOME_CURTO) |>
      mutate(overall = mean(mobility)) |>
      ungroup() |>
      mutate(NOME_CURTO = fct_reorder(NOME_CURTO, overall))
    p <- ggplot(df, aes(year, NOME_CURTO, fill = mobility,
                        text = sprintf("%s — %s<br>Mobility: %s",
                                       NOME_CURTO, year, comma(round(mobility))))) +
      geom_tile(colour = "white") +
      scale_fill_gradient2(low = "#b2182b", mid = "#f7f7f7", high = "#2166ac",
                            midpoint = 0, labels = comma) +
      labs(x = NULL, y = NULL, fill = "Mobility") +
      theme_minimal() +
      theme(axis.text.y = element_text(size = 8))
    ggplotly(p, tooltip = "text")
  })

  # ---- PPP table ------------------------------------------------------------
  output$table_ppp <- renderDT({
    ppp_panel |>
      mutate(across(c(deliveries, cesarianas), round)) |>
      transmute(Hospital = unit_id, Year = year,
                Deliveries = deliveries, Caesareans = cesarianas) |>
      arrange(Hospital, Year) |>
      datatable(rownames = FALSE, options = list(pageLength = 15))
  })
}

shinyApp(ui, server)
