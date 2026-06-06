# =============================================================================
# Cohort Builder — standalone Shiny app
#
# Lifted out of the main Peer Schools Explorer so cohort work can run on
# its own deploy + URL while the main app handles peer search / side-by-side.
# Shares the same output/ and data/ directories via .PROJECT_ROOT so a
# refresh of R/schools_pipeline.R propagates to both apps.
#
# Run from the project root with:
#   shiny::runApp("cohort_app", launch.browser = TRUE)
# =============================================================================

suppressMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(shinyjs)
})

source("global.R", local = FALSE)

# -----------------------------------------------------------------------------
# UI: single page with a per-page sidebar for cohort controls.
# -----------------------------------------------------------------------------
ui <- page_sidebar(
  title = "Cohort Builder",
  theme = cohc_bslib(),
  fillable = FALSE,
  # Holy Cross purple navbar — matches the main app's branding.
  navbar_options = list(bg = "#602D89", theme = "dark"),
  header = useShinyjs(),

  sidebar = sidebar(width = 340, open = "open", bg = "#F4EDEC",
                    cohortSidebarUI("cohort")),

  cohortUI("cohort")
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
server <- function(input, output, session) {
  cohort_module <- cohortServer("cohort")
  # Module returns reactives the main app used to consume (cohort_state,
  # anchor_uid). Standalone deploy doesn't need them but keep the return
  # to mirror the module's API.
  invisible(cohort_module)
}

shinyApp(ui, server)
