# shiny/app.R
# Single-file Shiny entry point. Reads pre-computed artefacts from data/processed/.
# Run from project root: shiny::runApp("shiny", launch.browser = TRUE)

library(shiny)
library(bslib)
library(dplyr)
library(ggplot2)
library(plotly)
library(leaflet)
library(DT)
library(here)

proc_dir <- here::here("data", "processed")
partos_annual <- readRDS(file.path(proc_dir, "partos_annual.rds"))
hospitals     <- readRDS(file.path(proc_dir, "hospitals.rds"))
# flow_index  <- readRDS(file.path(proc_dir, "flow_index.rds"))  # populated by 03_analyse.R

# Headline numbers — read from outputs/tables/headline.csv when available.
headline_path <- here::here("outputs", "tables", "headline.csv")
headline <- if (file.exists(headline_path)) {
  readr::read_csv(headline_path, show_col_types = FALSE)
} else {
  NULL
}

# Plain-language one-line answer that opens the app. Update once analysis lands.
answer_text <- if (!is.null(headline)) {
  # Replace with a real templated string once `headline.csv` is populated.
  sprintf("Across %s Portuguese maternity hospitals, %s%% delivered more babies than their Região de Saúde alone could explain — direct evidence of cross-regional patient flow.",
          headline$value[headline$metric == "n_hospitals"],
          headline$value[headline$metric == "share_positive_flow"])
} else {
  "Pending analysis — once the pipeline runs against confirmed data, this card shows the share of Portuguese maternity hospitals that draw deliveries from outside their Região de Saúde."
}

ui <- page_navbar(
  title  = "Births in Portugal — Cross-Regional Flow",
  theme  = bs_theme(bootswatch = "flatly"),

  # ---- Tab 1: ANSWER (the headline, in plain language) -----------------------
  nav_panel(
    "Answer",
    layout_column_wrap(
      width = 1,
      card(
        card_header("In one sentence"),
        card_body(
          h3(answer_text),
          p(em("Source: PORDATA + Transparência SNS, 2013 onwards. See the 'Methods (plain language)' tab for how this is calculated."))
        )
      ),
      card(
        card_header("Why this matters"),
        card_body(
          p("If a meaningful share of births in Portugal happen at hospitals outside the mother's home region, then her prenatal records — held by her local provider — do not automatically follow her. The receiving team starts blind."),
          p(strong("This is a clinical safety argument for portable, interoperable maternal health records across the SNS."))
        )
      )
    )
  ),

  # ---- Tab 2: REGIONAL OVERVIEW ---------------------------------------------
  nav_panel(
    "Regional Overview",
    layout_sidebar(
      sidebar = sidebar(
        sliderInput("year_overview", "Year",
                    min = min(partos_annual$year), max = max(partos_annual$year),
                    value = max(partos_annual$year), step = 1, sep = "")
      ),
      leafletOutput("map_overview", height = 600)
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
                    min = min(partos_annual$year), max = max(partos_annual$year),
                    value = max(partos_annual$year), step = 1, sep = "")
      ),
      plotlyOutput("plot_obs_vs_exp"),
      DTOutput("table_hospitals")
    )
  ),

  # ---- Tab 4: CROSS-REGIONAL FLOW -------------------------------------------
  nav_panel(
    "Cross-Regional Flow",
    p("Heatmap / Sankey of estimated patient flow between regions and hospitals — pending flow_index.rds.")
  ),

  # ---- Tab 5: METHODS IN PLAIN LANGUAGE -------------------------------------
  nav_panel(
    "Methods (plain language)",
    card(
      card_header("How we got the answer"),
      card_body(
        p(strong("The question."), " Are Portuguese maternity hospitals delivering babies for mothers from outside their region? If yes, the mother's prenatal records may not be where the delivery is happening."),
        p(strong("Two datasets."), " ",
          tags$ol(
            tags$li(strong("PORDATA"), " tells us how many babies were born in each region of Portugal each year. This is based on where the mother lives."),
            tags$li(strong("Transparência SNS"), " tells us how many babies were born at each hospital each year. This is based on where the delivery happened.")
          )),
        p(strong("The reasoning."), " If every mother delivered in her own region, each hospital's share of regional births should match its share of regional capacity. We calculate this expected share and compare it to what hospitals actually delivered. The difference — the ", strong("cross-regional flow index"), " — tells us where the system is moving patients across boundaries."),
        p(strong("The maths, in one line.")),
        tags$pre("Expected(hospital, region, year) = TotalBirthsInRegion(year)\n                                  × HospitalCapacity / RegionalCapacity"),
        p("Hospitals where ", em("observed > expected"), " are absorbing patients from outside; hospitals where ", em("observed < expected"), " are losing residents to other regions."),
        p(strong("How we test it."), " A statistical test (t-test) checks whether the cross-regional flow is positive on average across all hospital-years. A mixed-effects model checks whether the pattern has changed over time. A spatial test (Moran's I) checks whether the hospitals with the largest outflows cluster geographically."),
        p(strong("Why we trust it."), " The full pipeline lives in a public GitHub repository; the exact numbers shown above can be reproduced by anyone with R installed. Limitations are listed in ", code("RESULTS.md"), ".")
      )
    )
  ),

  # ---- Tab 6: DATA & SOURCES ------------------------------------------------
  nav_panel(
    "Data",
    p("Source attribution and downloadable filtered datasets."),
    tags$ul(
      tags$li(tags$a("PORDATA", href = "https://www.pordata.pt", target = "_blank")),
      tags$li(tags$a("Transparência SNS",
                     href = "https://transparencia.sns.gov.pt/explore/dataset/partos-e-cesarianas/", target = "_blank"))
    )
  )
)

server <- function(input, output, session) {

  output$map_overview <- renderLeaflet({
    leaflet(hospitals) |>
      addTiles() |>
      addCircleMarkers(
        lng = ~lng, lat = ~lat,
        label = ~instituicao,
        radius = 4, stroke = FALSE, fillOpacity = 0.7
      )
  })

  filtered_explorer <- reactive({
    df <- partos_annual |> filter(year == input$year_explorer)
    if (input$regiao_filter != "All") df <- df |> filter(regiao == input$regiao_filter)
    df
  })

  output$plot_obs_vs_exp <- renderPlotly({
    df <- filtered_explorer()
    p <- ggplot(df, aes(x = reorder(instituicao, partos), y = partos, fill = regiao)) +
      geom_col() +
      coord_flip() +
      labs(x = NULL, y = "Deliveries", fill = NULL) +
      theme_minimal()
    ggplotly(p)
  })

  output$table_hospitals <- renderDT({
    datatable(filtered_explorer(), options = list(pageLength = 10))
  })
}

shinyApp(ui, server)
