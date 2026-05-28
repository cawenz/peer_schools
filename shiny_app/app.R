# =============================================================================
# Peer Schools Explorer — entry point
#
# Launches the Shiny app. The wd at startup is shiny_app/; global.R loads
# the data layer (compute_peers + schools + facts) and sources the module
# stubs in R/.
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
# UI
# -----------------------------------------------------------------------------
ui <- page_sidebar(
  title = "Peer Schools Explorer",
  theme = cohc_bslib(),
  sidebar = sidebar(
    width = 340,
    open  = "open",        # collapsible (click the chevron to hide/show)
    bg    = "#F4EDEC",
    sidebarUI("sidebar_main")
  ),
  useShinyjs(),
  navset_card_tab(
    nav_panel("Peer Search",      peerTableUI("peer_table")),
    nav_panel("Side-by-Side",     compareUI("compare")),
    nav_panel("Stratified Peers", stratifiedUI("stratified")),
    nav_panel("Saved Searches",   sessionUI("session"))
  )
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
server <- function(input, output, session) {
  saved_searches <- reactiveVal(list())
  restore_signal <- reactiveVal(NULL)

  sidebar_state    <- sidebarServer("sidebar_main",
                                    restore_signal = restore_signal)
  peer_table_state <- peerTableServer("peer_table",
                                      sidebar_state = sidebar_state)
  compareServer("compare",
                peer_selection = peer_table_state$selected_peer,
                peer_result    = peer_table_state$result)
  stratifiedServer("stratified", sidebar_state = sidebar_state)
  sessionServer("session",
                saved_searches  = saved_searches,
                restore_signal  = restore_signal)

  # Save observer: when the user clicks "Save this search", snapshot the
  # current peer_result + sidebar_state into the saved_searches list with
  # an auto-generated label and a unique id.
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
      tagList(
        tags$strong("Saved: "),
        record$label
      ),
      type = "message", duration = 4
    )
  }, ignoreInit = TRUE, ignoreNULL = TRUE)
}

shinyApp(ui, server)
