# =============================================================================
# Peer Search tab — Run button wired to compute_peers_cached().
#
# Displays:
#   - A stats-grid header summary (anchor, pool size, K, distance metric)
#   - DT results table with single-row selection for the side-by-side view
#   - Diagnostics accordion (variables used + weights, dropped by coverage,
#     dropped by anchor NA), expanded by default
#
# Returns from peerTableServer():
#   - $result        reactive peer_result list (NULL until first Run)
#   - $selected_peer reactive single-row tibble for the selected DT row
# =============================================================================

peerTableUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Peer Search"),
    p(class = "section-intro",
      "Set the controls in the sidebar and click ", tags$em("Run search"),
      " to compute peers. Click a row in the results to load that institution ",
      "into the Side-by-Side tab."),

    uiOutput(ns("header_or_empty")),

    # Results section with a clear label above the table so the table reads
    # as the primary result, not as something nested inside another widget.
    uiOutput(ns("results_header")),
    div(class = "peer-results-table",
        DT::DTOutput(ns("peer_table"))),

    # Diagnostics rendered as a native <details>/<summary> below the table.
    # Closed by default; click the summary to expand. Avoids the bslib
    # accordion's collapse-animation overlap with the DT above it.
    uiOutput(ns("diagnostics_ui"))
  )
}

peerTableServer <- function(id, sidebar_state) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # -------------------------------------------------------------------------
    # Run trigger. eventReactive only invalidates when the Run button
    # increments. Reading state() inside is wrapped in isolate() so later
    # sidebar changes do not retrigger compute_peers().
    # -------------------------------------------------------------------------
    peer_result <- eventReactive(sidebar_state$run_trigger(), {
      st <- isolate(sidebar_state$state())
      req(st$anchor_unitid)

      withProgress(
        message = "Computing peers...",
        detail  = sprintf("Anchor: %s",
                          .SCHOOLS$instnm[match(st$anchor_unitid,
                                                .SCHOOLS$unitid)]),
        value = 0.5,
        {
          res <- tryCatch(
            compute_peers_cached(
              anchor_unitid   = st$anchor_unitid,
              candidate_pool  = st$candidate_pool,
              theme_weights   = st$theme_weights,
              distance_metric = st$distance_metric,
              k               = st$k
            ),
            error = function(e) {
              showNotification(
                tags$div(
                  tags$strong("compute_peers() failed: "),
                  tags$br(), e$message
                ),
                type = "error", duration = 12
              )
              NULL
            }
          )

          # Snapshot the pool unitids that compute_peers used. The
          # filter logic mirrors compute_peers() in peer_pipeline.R so
          # the snapshot matches what the methodology saw, including
          # the anchor add-back when filters exclude it.
          if (!is.null(res)) {
            pool_df <- .SCHOOLS
            for (col in names(st$candidate_pool)) {
              pool_df <- pool_df[pool_df[[col]] %in% st$candidate_pool[[col]], ]
            }
            if (!st$anchor_unitid %in% pool_df$unitid) {
              pool_df <- rbind(
                pool_df,
                .SCHOOLS[.SCHOOLS$unitid == st$anchor_unitid, ]
              )
            }
            res$pool_unitids <- pool_df$unitid
            # Also stash the raw filter dict so the Side-by-Side modal
            # can describe the pool (filters applied + resulting size).
            res$pool_filter <- st$candidate_pool
          }
          res
        }
      )
    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # -------------------------------------------------------------------------
    # Header: stats grid before results, empty-state message before first Run.
    # -------------------------------------------------------------------------
    output$header_or_empty <- renderUI({
      res <- peer_result()
      if (is.null(res)) {
        return(div(class = "note-box",
                   tags$strong("No search run yet. "),
                   "Configure the sidebar and click ",
                   tags$em("Run search"), " to compute peers."))
      }

      anchor_name <- res$meta$anchor_name
      pool_n      <- res$meta$candidate_pool_size
      k_actual    <- nrow(res$peers)
      dist_label  <- switch(res$meta$distance_metric,
                            euclidean   = "Euclidean",
                            mahalanobis = "Mahalanobis",
                            res$meta$distance_metric)
      n_vars      <- length(res$meta$variables_used)
      n_dropped_c <- nrow(res$meta$variables_dropped_coverage)
      n_dropped_a <- length(res$meta$variables_dropped_anchor_na)

      div(class = "stats-grid",
          div(class = "stat-card",
              div(class = "stat-title", "Anchor"),
              div(class = "stat-value", style = "font-size: 1.1rem;",
                  anchor_name)),
          div(class = "stat-card",
              div(class = "stat-title", "Candidate pool"),
              div(class = "stat-value", format(pool_n, big.mark = ",")),
              div(class = "stat-subtitle", "schools after filter")),
          div(class = "stat-card",
              div(class = "stat-title", "Peers returned"),
              div(class = "stat-value", k_actual),
              div(class = "stat-subtitle",
                  sprintf("of %d requested",
                          isolate(sidebar_state$state()$k)))),
          div(class = "stat-card",
              div(class = "stat-title", "Distance"),
              div(class = "stat-value", style = "font-size: 1.1rem;",
                  dist_label),
              div(class = "stat-subtitle",
                  sprintf("%d vars used, %d dropped",
                          n_vars, n_dropped_c + n_dropped_a)))
      )
    })

    # -------------------------------------------------------------------------
    # Results section header (only visible once a result exists)
    # -------------------------------------------------------------------------
    output$results_header <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      tagList(
        h5(sprintf("Top %d peers (click a row to compare)",
                   nrow(res$peers))),
        p(class = "text-muted",
          tags$small("Sorted by distance ascending. Click any column ",
                     "header to re-sort."))
      )
    })

    # -------------------------------------------------------------------------
    # Peer results table
    # -------------------------------------------------------------------------
    output$peer_table <- DT::renderDT({
      res <- peer_result()
      req(res, nrow(res$peers) > 0)
      df <- res$peers

      display_df <- data.frame(
        Rank      = df$rank,
        School    = df$instnm,
        `Class.`  = .prettify_classification(df$usnews_classification),
        Sector    = .prettify_control(df$control_grp),
        State     = df$stabbr,
        Religious = ifelse(is.na(df$religious_affiliation), "",
                           df$religious_affiliation),
        Distance  = round(df$distance, 3),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )

      DT::datatable(
        display_df,
        rownames  = FALSE,
        selection = list(mode = "single", target = "row"),
        options = list(
          pageLength = 50,
          dom        = "tip",
          order      = list(list(0, "asc")),
          columnDefs = list(
            list(className = "dt-right",  targets = c("Distance", "Rank")),
            list(className = "dt-center", targets = "State")
          )
        ),
        class = "compact stripe hover"
      ) |>
        DT::formatRound("Distance", digits = 3)
    })

    # -------------------------------------------------------------------------
    # Selected peer row → exposed reactive for the Side-by-Side tab
    # -------------------------------------------------------------------------
    selected_peer <- reactive({
      res <- peer_result()
      sel <- input$peer_table_rows_selected
      if (is.null(res) || !length(sel)) return(NULL)
      res$peers[sel, , drop = FALSE]
    })

    # -------------------------------------------------------------------------
    # Diagnostics (always rendered below the table once a result exists).
    # Rendered as plain block sections under a clear h4. Earlier attempts
    # used bslib accordion and native <details>; both had layout quirks
    # interacting with the surrounding card_body, so this is intentionally
    # boring HTML.
    # -------------------------------------------------------------------------
    output$diagnostics_ui <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)

      m <- res$meta
      n_vars     <- length(m$variables_used)
      n_drop_cov <- nrow(m$variables_dropped_coverage)
      n_drop_anc <- length(m$variables_dropped_anchor_na)

      summary_text <- sprintf(
        "%d variables used, %d dropped by coverage, %d dropped because the anchor has no value",
        n_vars, n_drop_cov, n_drop_anc
      )

      tagList(
        tags$hr(class = "peer-section-divider"),
        h4("Diagnostics"),
        p(class = "section-intro", summary_text),

        h5("Variables used (with per-variable weights)"),
        p(class = "text-muted",
          tags$small(
            "Weights are theme weight divided by the number of variables ",
            "in that theme, with detail race variables at half weight in ",
            "Composition. Sort by Weight to see what's driving the result."
          )),
        DT::DTOutput(ns("weights_table")),

        if (n_drop_cov > 0) tagList(
          h5("Variables dropped (below coverage threshold)"),
          p(class = "text-muted",
            tags$small(sprintf(
              "%d variables had fewer than %d%% of candidate-pool ",
              n_drop_cov,
              round(100 * m$coverage_threshold)),
              "schools reporting a value, and were excluded from the ",
              "distance calculation.")),
          DT::DTOutput(ns("dropped_cov_table"))
        ),

        if (n_drop_anc > 0) tagList(
          h5("Variables dropped (anchor has no value)"),
          p(class = "text-muted",
            tags$small(
              "These variables were available for some candidates but the ",
              "anchor itself was missing a value, so they could not ",
              "contribute to the distance.")),
          tags$ul(lapply(m$variables_dropped_anchor_na, tags$li))
        )
      )
    })

    # ---- Diagnostics: weights table ----
    output$weights_table <- DT::renderDT({
      res <- peer_result()
      req(res)
      m <- res$meta

      vars <- names(m$weights)
      themes <- vapply(vars, .var_theme, character(1))
      labels <- .VARIABLES$display_name[match(vars, .VARIABLES$metric)]
      labels <- ifelse(is.na(labels), vars, labels)

      df <- data.frame(
        Variable = labels,
        Metric   = vars,
        Theme    = ifelse(is.na(themes), "(unassigned)",
                          stringr::str_to_title(themes)),
        Weight   = unname(m$weights),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
      df <- df[order(-df$Weight), ]

      DT::datatable(
        df,
        rownames = FALSE,
        options  = list(pageLength = 15, dom = "tip",
                        order = list(list(3, "desc"))),
        class    = "compact stripe"
      ) |>
        DT::formatRound("Weight", digits = 4)
    })

    # ---- Diagnostics: dropped-by-coverage table ----
    output$dropped_cov_table <- DT::renderDT({
      res <- peer_result()
      req(res, nrow(res$meta$variables_dropped_coverage) > 0)
      d <- res$meta$variables_dropped_coverage
      labels <- .VARIABLES$display_name[match(d$metric, .VARIABLES$metric)]
      labels <- ifelse(is.na(labels), d$metric, labels)

      df <- data.frame(
        Variable = labels,
        Metric   = d$metric,
        Coverage = sprintf("%.1f%%", 100 * d$coverage),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        df,
        rownames = FALSE,
        options  = list(pageLength = 10, dom = "tip"),
        class    = "compact stripe"
      )
    })

    # -------------------------------------------------------------------------
    # Exports
    # -------------------------------------------------------------------------
    list(
      result        = peer_result,
      selected_peer = selected_peer
    )
  })
}
