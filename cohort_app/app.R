# =============================================================================
# Cohort Builder — standalone Shiny app
#
# Two tabs:
#   - Cohort Builder : the same cohort_state-driven UI lifted from the
#                       main app (table + dashboard + map + inspector +
#                       download).
#   - Side-by-Side   : pairwise comparison of any two institutions.
#                      Untethered from peer_result here (the main app
#                      passes a current search; this app stubs that out).
#
# Shares the project's output/ and data/ via .PROJECT_ROOT, so re-running
# R/schools_pipeline.R refreshes both apps.
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
# UI: page_navbar with two tabs.
# -----------------------------------------------------------------------------
ui <- page_navbar(
  title = "Cohort Builder",
  theme = cohc_bslib(),
  id    = "main_nav",
  navbar_options = navbar_options(bg = "#602D89", theme = "dark"),
  header = useShinyjs(),

  nav_panel(
    "Cohort Builder",
    layout_sidebar(
      sidebar = sidebar(width = 340, open = "open", bg = "#F4EDEC",
                        cohortSidebarUI("cohort")),
      cohortUI("cohort")
    )
  ),

  nav_panel(
    "Side-by-Side",
    layout_sidebar(
      sidebar = sidebar(width = 320, open = "open", bg = "#F4EDEC",
                        compareSidebarUI("compare")),
      compareUI("compare")
    )
  )
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
server <- function(input, output, session) {
  cohort_module <- cohortServer("cohort")

  # Side-by-Side normally accepts a peer_selection reactive (last clicked
  # peer-table row) and a peer_result reactive (last computed search) so
  # it can auto-sync to a search in progress. Standalone deploy has
  # neither, so stub both as reactive(NULL); the module's UI still
  # works — anchor + peer pickers are populated from .SCHOOLS directly.
  compareServer("compare",
                peer_selection = reactive(NULL),
                peer_result    = reactive(NULL))

  invisible(cohort_module)
}

shinyApp(ui, server)
