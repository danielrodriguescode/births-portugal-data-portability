# shiny/app.R
# Single-file Shiny entry point. Reads pre-computed artefacts from data/processed/.
# Run from project root: shiny::runApp("shiny", launch.browser = TRUE)

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(plotly)
  library(leaflet)
  library(DT)
  library(here)
  library(sf)
  library(stringi)
  library(scales)
  library(ulsportugal)
})

proc_dir <- here::here("data", "processed")

nfc <- function(x) stri_trans_nfc(x)

partos_annual <- readRDS(file.path(proc_dir, "partos_annual.rds")) |>
  mutate(regiao = nfc(regiao))
hospitals     <- readRDS(file.path(proc_dir, "hospitals.rds")) |>
  mutate(regiao = nfc(regiao), instituicao = nfc(instituicao))
flow          <- readRDS(file.path(proc_dir, "flow_index.rds")) |>
  mutate(regiao = nfc(regiao), instituicao = nfc(instituicao))
models        <- readRDS(file.path(proc_dir, "models.rds"))

uls_map <- ulsportugal()

# Spatial join: assign each hospital point to its containing ULS polygon
hospitals_sf <- hospitals |>
  filter(!is.na(lat), !is.na(lng)) |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326, remove = FALSE) |>
  st_join(uls_map, join = st_within)

# ---- Headline numbers from outputs/tables/headline.csv ----------------------
headline_path <- here::here("outputs", "tables", "headline.csv")
headline <- if (file.exists(headline_path)) {
  readr::read_csv(headline_path, show_col_types = FALSE) |>
    tibble::deframe()
} else {
  c()
}

answer_text <- if (length(headline) > 0) {
  sprintf("Of %s SNS maternity hospitals analysed across %s, the cross-regional flow index clusters strongly in space (Moran's I = %s, p %s). The largest negative flows are concentrated in Lisboa, Porto and the Algarve — where private maternity provision is also concentrated.",
          headline["n_hospitals"], headline["year_range"],
          headline["h4_moran_I"], headline["h4_moran_p"])
} else {
  "Pending analysis — once R/03_analyse.R runs against confirmed data, this card shows the project's headline finding."
}

ui <- page_navbar(
  title  = "Births in Portugal — Cross-Regional Flow",
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
          p(em("Source: PORDATA + Transparência SNS, 2013–2024 (cross-referenced) / 2013–2025 (SNS-only). See the 'Methods (plain language)' tab for how this is calculated."))
        )
      ),
      card(
        card_header("Why this matters"),
        card_body(
          p("If a meaningful share of births in Portugal happen at hospitals outside the mother's home region, then her prenatal records — held by her local provider — do not automatically follow her. The receiving team starts blind."),
          p(strong("This is a clinical safety argument for portable, interoperable maternal health records across the SNS."))
        )
      ),
      card(
        card_header("Statistical evidence (the four hypotheses)"),
        card_body(
          tags$table(class = "table table-sm",
            tags$thead(tags$tr(
              tags$th("Hypothesis"), tags$th("Test"), tags$th("Result"))),
            tags$tbody(
              tags$tr(tags$td("H1: flow index ≠ 0"),
                      tags$td("One-sample t (caveat: IID violated)"),
                      tags$td(sprintf("t = %s, p %s", headline["h1_t"], headline["h1_p"]))),
              tags$tr(tags$td("H2: urban tertiary centres absorb more"),
                      tags$td("Wilcoxon (5 vs 34 hospitals)"),
                      tags$td(sprintf("W = %s, p = %s — opposite direction to plan", headline["h2_wilcox_W"], headline["h2_p"]))),
              tags$tr(tags$td("H3: temporal drift"),
                      tags$td("lmer year coefficient"),
                      tags$td(sprintf("β = %s/year, 95%% CI %s", headline["h3_year_coef"], headline["h3_year_ci"]))),
              tags$tr(tags$td("H4: spatial clustering"),
                      tags$td("Moran's I, k=5 NN"),
                      tags$td(sprintf("I = %s, p %s", headline["h4_moran_I"], headline["h4_moran_p"])))
            )
          )
        )
      )
    )
  ),

  # ---- Tab 2: REGIONAL OVERVIEW (choropleth) --------------------------------
  nav_panel(
    "Regional Overview",
    layout_sidebar(
      sidebar = sidebar(
        sliderInput("year_overview", "Year",
                    min = min(partos_annual$year), max = max(partos_annual$year),
                    value = max(partos_annual$year), step = 1, sep = ""),
        radioButtons("metric_overview", "Metric",
                     choices = c("Annual deliveries"   = "deliveries",
                                 "Caesarean rate (%)"  = "csection",
                                 "Mean flow index"     = "flow"),
                     selected = "deliveries"),
        tags$small(em("ULS polygons from the ulsportugal R package; hospital points sized by deliveries that year."))
      ),
      leafletOutput("map_overview", height = 700)
    )
  ),

  # ---- Tab 3: HOSPITAL EXPLORER ---------------------------------------------
  nav_panel(
    "Hospital Explorer",
    layout_sidebar(
      sidebar = sidebar(
        selectInput("regiao_filter", "Região de Saúde",
                    choices = c("All", sort(unique(partos_annual$regiao)))),
        sliderInput("year_explorer", "Year",
                    min = min(flow$year), max = max(flow$year),
                    value = max(flow$year), step = 1, sep = ""),
        tags$small(em("Points above the dashed line are net inflow (absorbing more than capacity-weighted regional share predicts)."))
      ),
      plotlyOutput("plot_obs_vs_exp", height = 450),
      DTOutput("table_hospitals")
    )
  ),

  # ---- Tab 4: CROSS-REGIONAL FLOW (heatmap) ---------------------------------
  nav_panel(
    "Cross-Regional Flow",
    layout_sidebar(
      sidebar = sidebar(
        helpText("Heat map of mean flow index per hospital × year. Blue = net inflow, red = net outflow. Hospitals are ordered by their overall mean flow."),
        radioButtons("flow_scope", "Scope",
                     choices = c("All hospitals"             = "all",
                                 "Top 10 inflow + outflow"   = "top"),
                     selected = "top")
      ),
      plotlyOutput("plot_flow_heatmap", height = 700)
    )
  ),

  # ---- Tab 5: METHODS IN PLAIN LANGUAGE -------------------------------------
  nav_panel(
    "Methods (plain language)",
    card(
      card_header("How we got the answer"),
      card_body(
        p(strong("The question."), " Are Portuguese maternity hospitals delivering babies for mothers from outside their region?"),
        p(strong("Two datasets."), " ",
          tags$ol(
            tags$li(strong("PORDATA"), " — annual live births by region of mother's residence (NUTS 2024)."),
            tags$li(strong("Transparência SNS"), " — monthly cumulative deliveries per public hospital, with hospital region.")
          )),
        p(strong("The reasoning."), " If every mother delivered in her own region, each hospital's share of regional births should match its share of regional capacity. We calculate this expected share and compare it to what hospitals actually delivered. The difference — the ", strong("cross-regional flow index"), " — tells us where the system is moving patients across boundaries."),
        p(strong("The maths, in one line.")),
        tags$pre("Expected(hospital, region, year) = TotalBirthsInRegion(year)\n                                  × HospitalCapacity / RegionalCapacity"),
        p("Hospitals where ", em("observed > expected"), " are absorbing patients from outside; hospitals where ", em("observed < expected"), " are losing residents to other regions or to private hospitals not in this dataset."),
        p(strong("The four tests."),
          tags$ul(
            tags$li(strong("H1"), " — t-test: is the flow index different from zero on average?"),
            tags$li(strong("H2"), " — Wilcoxon: do urban tertiary centres in Lisboa/Porto/Coimbra absorb more than peripheral hospitals?"),
            tags$li(strong("H3"), " — mixed-effects model: is the flow index drifting over time?"),
            tags$li(strong("H4"), " — Moran's I: do hospitals with similar flow indices cluster geographically?")
          )),
        p(strong("Caveat."), " SNS captures roughly 80–87 % of Portugal's continental live births; the remaining 13–20 % go to private hospitals (concentrated in Lisboa, Porto, Algarve), at home, or abroad. Absolute flow values are biased downward by this gap, but the spatial-clustering finding (H4) is robust to it.")
      )
    )
  ),

  # ---- Tab 6: DATA & SOURCES ------------------------------------------------
  nav_panel(
    "Data",
    p("Source attribution and full reproducibility."),
    tags$ul(
      tags$li(tags$a("Transparência SNS — Partos e Cesarianas",
                     href = "https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/",
                     target = "_blank")),
      tags$li(tags$a("PORDATA — Nados-vivos por região",
                     href = "https://www.pordata.pt", target = "_blank")),
      tags$li(tags$a("ulsportugal R package (ULS sf geometries)",
                     href = "https://github.com/danielrodriguescode/ulsportugal",
                     target = "_blank")),
      tags$li(tags$a("Project repository (code, paper, prompts.md)",
                     href = "https://github.com/danielrodriguescode/births-portugal-data-portability",
                     target = "_blank"))
    )
  )
)

server <- function(input, output, session) {

  # ---- Regional Overview map (choropleth + hospital points) -----------------
  region_yearly <- reactive({
    req(input$year_overview)
    df <- partos_annual |>
      filter(year == input$year_overview) |>
      group_by(hospital_id, instituicao, regiao) |>
      summarise(deliveries = sum(partos, na.rm = TRUE),
                cesarianas = sum(cesarianas, na.rm = TRUE),
                .groups = "drop") |>
      mutate(csection = ifelse(deliveries > 0, cesarianas / deliveries, NA))

    # bring flow index for the selected year (only available 2013-2024)
    flow_year <- flow |>
      filter(year == input$year_overview) |>
      select(hospital_id, flow_index)
    df |> left_join(flow_year, by = "hospital_id")
  })

  hospital_points <- reactive({
    df <- region_yearly()
    hospitals |>
      filter(!is.na(lat), !is.na(lng)) |>
      inner_join(df, by = c("hospital_id", "instituicao", "regiao"))
  })

  output$map_overview <- renderLeaflet({
    pts <- hospital_points()
    metric_col <- switch(input$metric_overview,
                         deliveries = pts$deliveries,
                         csection   = pts$csection * 100,
                         flow       = pts$flow_index)
    pal <- if (input$metric_overview == "flow") {
      colorNumeric(c("#b2182b", "#f7f7f7", "#2166ac"),
                   domain = c(-max(abs(metric_col), na.rm = TRUE),
                               max(abs(metric_col), na.rm = TRUE)))
    } else {
      colorNumeric("YlOrRd", domain = metric_col, na.color = "#cccccc")
    }
    label_fmt <- switch(input$metric_overview,
                        deliveries = sprintf("%s — %s deliveries", pts$instituicao, comma(pts$deliveries)),
                        csection   = sprintf("%s — %.1f%% caesarean", pts$instituicao, pts$csection * 100),
                        flow       = sprintf("%s — flow index %s", pts$instituicao, ifelse(is.na(pts$flow_index), "n/a", round(pts$flow_index, 0))))

    leaflet() |>
      addProviderTiles(providers$CartoDB.Positron) |>
      addPolygons(data = uls_map, fillColor = "#dfeaf2",
                  weight = 0.5, color = "white",
                  fillOpacity = 0.6,
                  label = ~NOME_CURTO,
                  highlightOptions = highlightOptions(weight = 2, color = "#666",
                                                     bringToFront = TRUE)) |>
      addCircleMarkers(
        data = pts, lng = ~lng, lat = ~lat,
        radius = 5 + 8 * (pts$deliveries / max(pts$deliveries, na.rm = TRUE)),
        color = pal(metric_col), stroke = TRUE, weight = 1,
        fillOpacity = 0.85,
        label = label_fmt) |>
      addLegend("bottomright", pal = pal, values = metric_col,
                title = switch(input$metric_overview,
                               deliveries = "Deliveries",
                               csection   = "Caesarean rate",
                               flow       = "Flow index"),
                opacity = 0.8)
  })

  # ---- Hospital Explorer (observed vs expected) -----------------------------
  filtered_explorer <- reactive({
    df <- flow |> filter(year == input$year_explorer)
    if (input$regiao_filter != "All") df <- df |> filter(regiao == input$regiao_filter)
    df
  })

  output$plot_obs_vs_exp <- renderPlotly({
    df <- filtered_explorer()
    if (nrow(df) == 0) return(NULL)
    p <- ggplot(df, aes(expected, partos, colour = regiao,
                        text = paste0(instituicao,
                                      "<br>Observed: ", comma(partos),
                                      "<br>Expected: ", comma(round(expected)),
                                      "<br>Flow: ",   comma(round(flow_index))))) +
      geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "dashed") +
      geom_point(size = 3, alpha = 0.8) +
      scale_x_continuous(labels = comma) +
      scale_y_continuous(labels = comma) +
      labs(x = "Expected deliveries", y = "Observed deliveries", colour = NULL,
           title = paste("Observed vs expected,", input$year_explorer)) +
      theme_minimal()
    ggplotly(p, tooltip = "text")
  })

  output$table_hospitals <- renderDT({
    df <- filtered_explorer() |>
      select(instituicao, regiao, partos, expected, flow_index) |>
      mutate(across(c(expected, flow_index), \(x) round(x, 1)))
    datatable(df, rownames = FALSE, options = list(pageLength = 10))
  })

  # ---- Cross-Regional Flow heatmap ------------------------------------------
  flow_for_heatmap <- reactive({
    base <- flow |>
      group_by(hospital_id, instituicao, regiao) |>
      mutate(overall_mean = mean(flow_index, na.rm = TRUE)) |>
      ungroup()
    if (input$flow_scope == "top") {
      ordering <- base |>
        distinct(hospital_id, overall_mean) |>
        arrange(overall_mean)
      keep <- c(head(ordering$hospital_id, 10), tail(ordering$hospital_id, 10))
      base <- base |> filter(hospital_id %in% keep)
    }
    base |>
      mutate(instituicao = forcats::fct_reorder(instituicao, overall_mean))
  })

  output$plot_flow_heatmap <- renderPlotly({
    df <- flow_for_heatmap()
    p <- ggplot(df, aes(year, instituicao, fill = flow_index,
                        text = paste0(instituicao, " — ", year,
                                      "<br>Flow: ", comma(round(flow_index))))) +
      geom_tile(colour = "white") +
      scale_fill_gradient2(low = "#b2182b", mid = "#f7f7f7", high = "#2166ac",
                           midpoint = 0, labels = comma) +
      labs(x = NULL, y = NULL, fill = "Flow",
           title = "Cross-regional flow index per hospital × year") +
      theme_minimal() +
      theme(axis.text.y = element_text(size = 8))
    ggplotly(p, tooltip = "text")
  })
}

shinyApp(ui, server)
