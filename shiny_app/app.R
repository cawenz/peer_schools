# =============================================================================
# Peer Schools Explorer — entry point
#
# Page architecture: each top-level page has its own dedicated sidebar
# containing only the controls relevant to that page. Anchor, theme
# weights, and pool filters are all per-page (each defaults to HC and
# can be changed independently). The only state shared across pages is:
#   - peer_result    : most recent Peer Search result (used by Side-by-Side
#                      for distance-context and the peer-group limit)
#   - saved_searches : in-memory list of saved searches; View action
#                      restores into the Peer Search page
#   - restore_signal : channel from Saved Searches View action back to
#                      Peer Search page's sidebar
#
# Run from the project root with:
#   shiny::runApp("shiny_app", launch.browser = TRUE)
# =============================================================================

suppressMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(shinyjs)
})

source("global.R", local = FALSE)

# -----------------------------------------------------------------------------
# UI: page_navbar with per-page sidebars (layout_sidebar inside each nav)
# -----------------------------------------------------------------------------
ui <- page_navbar(
  title = "Peer Schools Explorer",
  theme = cohc_bslib(),
  id    = "main_nav",          # used for programmatic page switching
  navbar_options = navbar_options(bg = "#602D89", theme = "dark"),
  header = useShinyjs(),

  nav_panel(
    "Peer Search",
    layout_sidebar(
      sidebar = sidebar(width = 340, open = "open", bg = "#F4EDEC",
                        peerSearchSidebarUI("peer_search_sidebar")),
      peerTableUI("peer_table")
    )
  ),

  nav_panel(
    "Side-by-Side",
    layout_sidebar(
      sidebar = sidebar(width = 320, open = "open", bg = "#F4EDEC",
                        compareSidebarUI("compare")),
      compareUI("compare")
    )
  ),

  nav_panel(
    "Stratified Peers",
    layout_sidebar(
      sidebar = sidebar(width = 320, open = "open", bg = "#F4EDEC",
                        stratifiedSidebarUI("stratified")),
      stratifiedUI("stratified")
    )
  ),

  nav_panel(
    "Aspirant Peers",
    # No sidebar — the essential controls (anchor + aspirational metrics +
    # Run) live in a compact bar at the top of the page, and the
    # secondary controls (pool filters, theme weights, output sizes) live
    # behind a collapsed Advanced accordion.
    aspirantUI("aspirant")
  ),

  nav_panel(
    "Trends",
    # School + variable + comparison group in a top control bar; no sidebar.
    trendsUI("trends")
  ),

  nav_panel(
    "Cohort Builder",
    layout_sidebar(
      sidebar = sidebar(width = 340, open = "open", bg = "#F4EDEC",
                        cohortSidebarUI("cohort")),
      cohortUI("cohort")
    )
  ),

  nav_panel(
    "Saved Searches",
    sessionUI("session")
  ),

  # Reference tabs at the right end of the navbar.
  nav_panel(
    "Variables",
    variablesUI("variables")
  ),

  nav_panel(
    "Help",
    div(class = "help-doc",
      includeMarkdown(file.path(.PROJECT_ROOT, "docs", "USER_GUIDE.md"))
    )
  )
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
server <- function(input, output, session) {
  saved_searches <- reactiveVal(list())
  restore_signal <- reactiveVal(NULL)

  # Peer Search page (sidebar + main panel)
  sidebar_state    <- peerSearchSidebarServer("peer_search_sidebar",
                                              restore_signal = restore_signal)
  peer_table_state <- peerTableServer("peer_table",
                                      sidebar_state = sidebar_state)

  # Side-by-Side page (uses peer_result + peer_selection from Peer Search)
  compareServer("compare",
                peer_selection = peer_table_state$selected_peer,
                peer_result    = peer_table_state$result)

  # Aspirant Peers page — wholly self-contained, no upstream state.
  aspirantServer("aspirant")

  # Stratified Peers page (fully self-contained; no upstream state)
  stratifiedServer("stratified")

  # Cohort Builder page (returns reactives that other tabs consume)
  cohort_module <- cohortServer("cohort")

  # Trends page (consumes peer_result and the cohort module's state)
  trendsServer("trends",
               peer_result       = peer_table_state$result,
               cohort_state      = cohort_module$cohort_state,
               cohort_anchor_uid = cohort_module$anchor_uid)

  # Saved Searches page
  sessionServer("session",
                saved_searches  = saved_searches,
                restore_signal  = restore_signal)

  # Variables reference tab (self-contained; reads .VARIABLES).
  variablesServer("variables")

  # Save observer (Save button lives in the Peer Search sidebar)
  observeEvent(sidebar_state$save_trigger(), {
    res <- peer_table_state$result()
    if (is.null(res)) {
      showNotification(
        "Run a search first before saving.",
        type = "warning", duration = 5
      )
      return()
    }
    state <- isolate(sidebar_state$state())
    sid <- format(Sys.time(), "ss_%Y%m%d_%H%M%OS3")
    sid <- gsub("[^A-Za-z0-9_]", "_", sid)
    record <- list(
      id            = sid,
      label         = .auto_label(res, state),
      saved_at      = Sys.time(),
      sidebar_state = state,
      peer_result   = res
    )
    current <- saved_searches()
    current[[sid]] <- record
    saved_searches(current)

    showNotification(
      tagList(tags$strong("Saved: "), record$label),
      type = "message", duration = 4
    )
  }, ignoreInit = TRUE, ignoreNULL = TRUE)

  # Saved Searches View action navigates to the Peer Search page
  observeEvent(restore_signal(), {
    nav_select(id = "main_nav", selected = "Peer Search")
  }, ignoreInit = TRUE, ignoreNULL = TRUE)
}

shinyApp(ui, server)
