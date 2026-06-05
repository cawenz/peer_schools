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

    # ---- Follow-up sections that consume the just-run peer result ----
    # Aspirant: filter the top K to those that beat the anchor on chosen
    # metrics. Stratified: re-run compute_peers per value of a chosen
    # classification dimension. Both share the sidebar's anchor + pool +
    # theme weights, so the user doesn't reconfigure.
    uiOutput(ns("aspirant_refine_section")),
    uiOutput(ns("stratified_expand_section")),

    # ---- Reference: diagnostics ----
    # Collapsed by default so the headline result + the action sections
    # above stay uncluttered. The diagnostics matter when interpreting
    # the result but the user can ignore them most of the time.
    uiOutput(ns("diagnostics_accordion"))
  )
}

peerTableServer <- function(id, sidebar_state) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # -------------------------------------------------------------------------
    # Peer-result state. Stored as a reactiveVal (rather than an
    # eventReactive) so that downstream consumers (Side-by-Side's
    # peer_choices, pool_slice, distance_info, etc.) get a clean NULL
    # before the user has run any search. eventReactive with ignoreInit
    # raises a silent reactive error when called before its first trigger,
    # which would propagate up and make Side-by-Side render nothing.
    # -------------------------------------------------------------------------
    peer_result <- reactiveVal(NULL)

    observeEvent(sidebar_state$run_trigger(), {
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

          # Snapshot the pool unitids and filter dict the search actually
          # used so Side-by-Side can describe and slice that pool.
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
            res$pool_filter  <- st$candidate_pool
          }
          peer_result(res)
        }
      )
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

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

      # External rankings — populated by the pipeline:
      #   usnews_rank   : Academic Insights metric 24 (Overall Rank).
      #   wamo_rank     : Washington Monthly category rank.
      #   wamo_category : WM category short label (LA / Bacc / Mas / Nat).
      # NA for unranked schools or for older schools.csv files that don't
      # have these columns yet — display as blank in either case.
      usn_rank_disp <- if ("usnews_rank" %in% names(df)) {
        ifelse(is.na(df$usnews_rank), "", as.character(df$usnews_rank))
      } else {
        rep("", nrow(df))
      }
      wamo_short <- c("Liberal Arts" = "LA", "Baccalaureate" = "Bacc",
                      "Master's" = "Mas",  "National" = "Nat")
      wamo_disp <- if ("wamo_rank" %in% names(df)) {
        cat <- if ("wamo_category" %in% names(df)) df$wamo_category
               else rep(NA_character_, nrow(df))
        sfx <- ifelse(is.na(cat), "", paste0(" (", wamo_short[cat], ")"))
        ifelse(is.na(df$wamo_rank), "",
               paste0(as.character(df$wamo_rank), sfx))
      } else {
        rep("", nrow(df))
      }

      display_df <- data.frame(
        Rank        = df$rank,
        School      = df$instnm,
        `Class.`    = .prettify_classification(df$usnews_classification),
        `USN Rank`  = usn_rank_disp,
        `WM Rank`   = wamo_disp,
        Sector      = .prettify_control(df$control_grp),
        State       = df$stabbr,
        Religious   = ifelse(is.na(df$religious_affiliation), "",
                             df$religious_affiliation),
        Distance    = round(df$distance, 3),
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
            list(className = "dt-right",  targets = c("Distance", "Rank",
                                                       "USN Rank",
                                                       "WM Rank")),
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
    # Wrap the diagnostics output in a collapsed bslib accordion at the
    # bottom of the page, so the headline result + action sections above
    # stay clean and the user only sees diagnostics on demand.
    output$diagnostics_accordion <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      tagList(
        tags$hr(class = "peer-refine-divider"),
        accordion(
          open = FALSE,
          accordion_panel(
            title = tagList(icon("magnifying-glass-chart"),
                             " Search diagnostics"),
            value = "diagnostics",
            uiOutput(ns("diagnostics_ui"))
          )
        )
      )
    })

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

    # =========================================================================
    # Follow-up section 1: Refine — aspirant peers from the top K
    # =========================================================================
    # Filters the already-computed peer set to those that beat the anchor
    # on every user-chosen aspirational metric (strict) or all but one
    # (near-miss). Does NOT re-run compute_peers — operates on the table
    # the user just got. Vocabulary, gap-modal, colors all mirror the
    # standalone Aspirant Peers tab (now removed).

    aspirant_filter <- reactive({
      res <- peer_result(); if (is.null(res)) return(NULL)
      metrics <- input$aspirant_metrics
      if (!length(metrics)) return(NULL)

      a_uid <- res$meta$anchor_unitid %||%
                isolate(sidebar_state$state())$anchor_unitid
      if (is.null(a_uid)) return(NULL)

      # Aspirant pool size: defaults to main K. When the user bumps the
      # slider above the main K, fetch a wider candidate set via the
      # cached peer compute (free if same args were used before).
      st     <- isolate(sidebar_state$state())
      pool_k <- input$aspirant_pool_k %||% nrow(res$peers)
      if (is.finite(pool_k) && pool_k != nrow(res$peers)) {
        bigger <- tryCatch(
          compute_peers_cached(
            anchor_unitid   = a_uid,
            candidate_pool  = st$candidate_pool,
            theme_weights   = st$theme_weights,
            distance_metric = if (isTRUE(st$mahalanobis)) "mahalanobis"
                              else (st$distance_metric %||% "euclidean"),
            k               = as.integer(pool_k)
          ),
          error = function(e) NULL
        )
        if (!is.null(bigger)) res <- bigger
      }

      # Look up anchor + peer values for each chosen metric.
      anchor_values <- vapply(metrics, function(m) {
        if (!m %in% names(.SCHOOLS_WIDE)) return(NA_real_)
        as.numeric(.SCHOOLS_WIDE[[m]][.SCHOOLS_WIDE$unitid == a_uid][1])
      }, numeric(1))

      peers <- res$peers
      uids  <- peers$unitid
      # Per-metric value matrix (one column per metric, one row per peer).
      mvals <- vapply(metrics, function(m) {
        if (!m %in% names(.SCHOOLS_WIDE)) return(rep(NA_real_, length(uids)))
        as.numeric(.SCHOOLS_WIDE[[m]][match(uids, .SCHOOLS_WIDE$unitid)])
      }, numeric(length(uids)))
      if (!is.matrix(mvals)) mvals <- matrix(mvals, ncol = length(metrics))
      colnames(mvals) <- metrics

      # Boolean "beats anchor in preferred direction" per (peer, metric).
      beats <- vapply(metrics, function(m) {
        dir <- ASPIRANT_DIRECTIONS[[m]]
        if (is.null(dir)) return(rep(FALSE, nrow(mvals)))
        v <- mvals[, m]; a <- anchor_values[[m]]
        if (!is.finite(a)) return(rep(FALSE, length(v)))
        if (dir == "higher") v > a else v < a
      }, logical(nrow(mvals)))
      if (!is.matrix(beats)) beats <- matrix(beats, ncol = length(metrics))
      beats[is.na(beats)] <- FALSE
      colnames(beats) <- metrics

      beats_per_row <- rowSums(beats)
      n_metrics     <- length(metrics)

      strict_ix    <- which(beats_per_row == n_metrics)
      near_miss_ix <- if (n_metrics >= 2)
                       which(beats_per_row == (n_metrics - 1L)) else integer(0)

      attach_vals <- function(df, idx) {
        if (!length(idx)) return(df[0, , drop = FALSE])
        out <- df[idx, , drop = FALSE]
        for (m in metrics) out[[m]] <- mvals[idx, m]
        out
      }
      strict    <- attach_vals(peers, strict_ix)
      near_miss <- attach_vals(peers, near_miss_ix)
      if (nrow(near_miss)) {
        near_miss$missed_metric <- vapply(near_miss_ix, function(i) {
          mi <- which(!beats[i, ])
          if (length(mi) == 1L) metrics[mi] else NA_character_
        }, character(1))
      }

      # Re-rank within each filtered set.
      if (nrow(strict))    strict$rank    <- seq_len(nrow(strict))
      if (nrow(near_miss)) near_miss$rank <- seq_len(nrow(near_miss))

      list(strict = strict, near_miss = near_miss,
           aspirant_metrics = metrics, anchor_values = anchor_values)
    })

    output$aspirant_refine_section <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)

      asp_choices <- {
        v <- names(ASPIRANT_LABELS)
        names(v) <- unname(unlist(ASPIRANT_LABELS))
        v
      }

      main_k <- nrow(res$peers)

      tagList(
        tags$hr(class = "peer-refine-divider"),
        h5("Refine: aspirant peers from this search",
           tags$small(class = "text-muted",
             "  — schools above that beat the anchor on the metrics you pick")),
        p(class = "section-intro",
          tags$small(
            "Strict aspirants beat the anchor on ", tags$em("every"),
            " chosen metric. Near-miss beats it on all but one.")),
        tags$div(class = "peer-refine-controls",
          tags$div(class = "peer-refine-row",
            tags$div(class = "peer-refine-cell peer-refine-cell-wide",
              selectizeInput(ns("aspirant_metrics"),
                              label = "Aspire higher on",
                              choices = asp_choices,
                              multiple = TRUE,
                              width = "100%",
                              options = list(
                                placeholder = "Pick one or more metrics",
                                plugins = list("remove_button")))
            ),
            tags$div(class = "peer-refine-cell peer-refine-cell-narrow",
              sliderInput(ns("aspirant_pool_k"),
                          label = "Evaluate top N peers",
                          min = 5, max = 100,
                          value = main_k, step = 5, ticks = FALSE)
            )
          )
        ),
        uiOutput(ns("aspirant_results"))
      )
    })

    # When the main search re-runs (peer_result changes), sync the
    # aspirant-pool slider back to the new K. Without this, a fresh
    # search would leave a stale value (e.g. user had bumped to 60,
    # then re-ran with K=20; the slider still showed 60).
    observeEvent(peer_result(), {
      res <- peer_result()
      if (is.null(res)) return()
      main_k <- nrow(res$peers)
      updateSliderInput(session, "aspirant_pool_k",
                        value = main_k)
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    .aspirant_table <- function(df, asp_metrics, anchor_values,
                                  near_miss = FALSE) {
      if (!nrow(df)) return(NULL)
      cols <- list(
        Rank     = df$rank,
        School   = df$instnm,
        State    = df$stabbr,
        Distance = round(df$distance, 3)
      )
      if (near_miss) cols[["Missed"]] <- vapply(
        df$missed_metric,
        function(m) if (is.na(m)) "—" else (ASPIRANT_LABELS[[m]] %||% m),
        character(1))

      for (m in asp_metrics) {
        a_val <- anchor_values[[m]]
        dir   <- ASPIRANT_DIRECTIONS[[m]]
        fmt_row <- .VARIABLES[match(m, .VARIABLES$metric), , drop = FALSE]
        fmt <- if (nrow(fmt_row)) fmt_row$format else NA
        col_label <- ASPIRANT_LABELS[[m]] %||% m
        vals <- df[[m]]
        cells <- vapply(seq_along(vals), function(i) {
          v <- vals[i]
          if (!is.finite(v)) return("—")
          gap <- v - a_val
          beats <- if (dir == "higher") gap > 0 else gap < 0
          arrow <- if (is.na(beats)) ""
                   else if (beats) "<span class=\"asp-up\">&#9650;</span>"
                   else            "<span class=\"asp-down\">&#9660;</span>"
          sprintf("%s  %s",
                  .format_value(v, fmt),
                  paste0(arrow, " ",
                          sprintf("%+s", .format_value(abs(gap), fmt))))
        }, character(1))
        cols[[col_label]] <- cells
      }

      dt_df <- do.call(data.frame, c(cols, list(stringsAsFactors = FALSE,
                                                  check.names = FALSE)))

      target_cols <- which(names(dt_df) %in%
                            vapply(asp_metrics,
                                    function(m) ASPIRANT_LABELS[[m]] %||% m,
                                    character(1))) - 1L
      DT::datatable(
        dt_df, escape = FALSE, rownames = FALSE,
        selection = list(mode = "single", target = "row"),
        options = list(pageLength = 25, dom = "tip",
                       order = list(list(0, "asc")),
                       columnDefs = list(
                         list(className = "dt-right",  targets = c(0, 3)),
                         list(className = "dt-center", targets = 2),
                         list(className = "asp-metric-cell",
                              targets = target_cols))),
        class = "compact stripe hover"
      )
    }

    output$aspirant_results <- renderUI({
      ar <- aspirant_filter()
      if (is.null(ar)) return(NULL)
      n_s <- nrow(ar$strict)
      n_n <- nrow(ar$near_miss)

      tagList(
        h6(sprintf("Strict aspirants (%d) — beat the anchor on every chosen metric",
                   n_s)),
        if (n_s)
          DT::DTOutput(ns("aspirant_strict_tbl"))
        else
          div(class = "note-box",
              "None of the top peers beat the anchor on every chosen ",
              "metric. Try removing a metric, or widen the peer count ",
              "in the sidebar."),
        if (n_n > 0) tagList(
          h6(sprintf("Near-miss (%d) — beat the anchor on all but one metric",
                     n_n)),
          DT::DTOutput(ns("aspirant_near_tbl"))
        )
      )
    })

    output$aspirant_strict_tbl <- DT::renderDT({
      ar <- aspirant_filter(); req(ar, nrow(ar$strict) > 0)
      .aspirant_table(ar$strict, ar$aspirant_metrics, ar$anchor_values,
                       near_miss = FALSE)
    })
    output$aspirant_near_tbl <- DT::renderDT({
      ar <- aspirant_filter(); req(ar, nrow(ar$near_miss) > 0)
      .aspirant_table(ar$near_miss, ar$aspirant_metrics, ar$anchor_values,
                       near_miss = TRUE)
    })

    # Row click → aspirational gap modal (same format as the standalone
    # tab used). Pulls the school's row from the appropriate table.
    .open_aspirant_modal <- function(row, anchor_values, asp_metrics) {
      res <- peer_result()
      a_uid <- res$meta$anchor_unitid %||% NA
      anchor_name <- if (!is.na(a_uid))
        .SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1] else "Anchor"
      anchor_st <- if (!is.na(a_uid))
        .SCHOOLS$stabbr[.SCHOOLS$unitid == a_uid][1] else ""

      gap_rows <- lapply(asp_metrics, function(m) {
        dir   <- ASPIRANT_DIRECTIONS[[m]]
        a_val <- anchor_values[[m]]
        c_val <- row[[m]]
        fmt_row <- .VARIABLES[match(m, .VARIABLES$metric), , drop = FALSE]
        fmt <- if (nrow(fmt_row)) fmt_row$format else NA
        gap <- c_val - a_val
        beats <- if (!is.finite(gap)) NA
                 else if (dir == "higher") gap > 0
                 else gap < 0
        arrow <- if (is.na(beats)) ""
                 else if (beats) tags$span(class = "asp-up", HTML("&#9650;"))
                 else            tags$span(class = "asp-down", HTML("&#9660;"))
        tags$div(class = "asp-gap-row",
          tags$div(class = "asp-gap-label",
                    ASPIRANT_LABELS[[m]] %||% m),
          tags$div(class = "asp-gap-values",
            tags$div(class = "asp-gap-anchor",
              tags$span(class = "asp-gap-tag", "Anchor"),
              .format_value(a_val, fmt)),
            tags$div(class = "asp-gap-arrow", arrow),
            tags$div(class = "asp-gap-cand",
              tags$span(class = "asp-gap-tag", "Aspirant"),
              .format_value(c_val, fmt)),
            tags$div(class = "asp-gap-delta",
              sprintf("(%+s)", .format_value(gap, fmt)))))
      })

      showModal(modalDialog(
        title = tagList(
          tags$div(class = "asp-modal-title", "Aspirational gap"),
          tags$div(class = "asp-modal-subtitle",
            tags$strong(row$instnm), sprintf(" (%s) vs ", row$stabbr),
            tags$strong(anchor_name), sprintf(" (%s)", anchor_st))),
        size = "l", easyClose = TRUE, fade = TRUE,
        footer = tagList(modalButton("Close")),
        div(class = "asp-modal-body", gap_rows)))
    }

    observeEvent(input$aspirant_strict_tbl_rows_selected, {
      ar <- aspirant_filter(); req(ar, nrow(ar$strict) > 0)
      ix <- input$aspirant_strict_tbl_rows_selected
      if (!length(ix)) return()
      .open_aspirant_modal(ar$strict[ix, ],
                            ar$anchor_values, ar$aspirant_metrics)
      DT::dataTableProxy("aspirant_strict_tbl") %>% DT::selectRows(NULL)
    })
    observeEvent(input$aspirant_near_tbl_rows_selected, {
      ar <- aspirant_filter(); req(ar, nrow(ar$near_miss) > 0)
      ix <- input$aspirant_near_tbl_rows_selected
      if (!length(ix)) return()
      .open_aspirant_modal(ar$near_miss[ix, ],
                            ar$anchor_values, ar$aspirant_metrics)
      DT::dataTableProxy("aspirant_near_tbl") %>% DT::selectRows(NULL)
    })

    # =========================================================================
    # Follow-up section 2: Expand — stratified peers
    # =========================================================================
    # Pick a classification dimension. For each non-anchor value of that
    # dimension, run a fresh compute_peers_cached with the SAME anchor
    # + theme weights + pool, plus a pool filter narrowing to that
    # stratum value. Show top-3 peers per stratum as a compact card.
    #
    # Reuses .STRATIFY_DIMS from mod_stratified.R (still sourced even
    # though that tab is no longer in the navbar).

    output$stratified_expand_section <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      if (!exists(".STRATIFY_DIMS", envir = globalenv()))
        return(NULL)   # safety: mod_stratified.R not sourced

      dim_choices <- setNames(
        names(.STRATIFY_DIMS),
        vapply(.STRATIFY_DIMS, function(d) d$label, character(1))
      )

      tagList(
        tags$hr(class = "peer-refine-divider"),
        h5("Expand search into other groups",
           tags$small(class = "text-muted",
             "  — closest peers within each value of a chosen classification")),
        p(class = "section-intro",
          tags$small(
            "Runs a separate peer search inside each value of the chosen ",
            "dimension, using the same anchor and theme weights from your ",
            "original search. Useful for 'who's our closest R1, R2, LAC?' ",
            "and similar cross-category surveys.")),
        tags$div(class = "peer-refine-controls",
          selectInput(ns("stratify_by"),
                      label = "Stratify by",
                      choices = c("(pick a dimension)" = "", dim_choices),
                      selected = "",
                      width = "100%"),
          sliderInput(ns("stratify_k"), "Peers per stratum",
                       min = 1, max = 8, value = 3, step = 1, ticks = FALSE)
        ),
        uiOutput(ns("stratified_results"))
      )
    })

    stratified_runs <- reactive({
      res <- peer_result();         if (is.null(res)) return(NULL)
      dim_key <- input$stratify_by; if (is.null(dim_key) || dim_key == "")
        return(NULL)
      dim <- .STRATIFY_DIMS[[dim_key]]; if (is.null(dim)) return(NULL)
      st <- isolate(sidebar_state$state())
      a_uid <- res$meta$anchor_unitid %||% st$anchor_unitid

      values <- dim$values()
      # Anchor's own stratum value (for highlighting / placement).
      anchor_val <- if (identical(dim_key, "region")) {
        st_ab <- .SCHOOLS$stabbr[.SCHOOLS$unitid == a_uid][1]
        names(.REGIONS)[vapply(.REGIONS,
                                function(s) st_ab %in% s, logical(1))][1]
      } else {
        .SCHOOLS[[dim$column]][.SCHOOLS$unitid == a_uid][1]
      }

      withProgress(
        message = sprintf("Running stratified search (%d strata)...",
                          length(values)),
        value = 0.2, {
          per_value_k <- input$stratify_k %||% 3
          out <- lapply(values, function(v) {
            pool <- st$candidate_pool
            if (identical(dim_key, "region")) {
              pool$stabbr <- .REGIONS[[v]]
            } else {
              pool[[dim$filter_key]] <- v
            }

            # Pre-check: how many schools survive the pool filter
            # intersection? Lets us distinguish "no candidates exist"
            # from "compute_peers couldn't rank them" downstream.
            cand <- .SCHOOLS
            for (col in names(pool)) {
              if (col %in% names(cand))
                cand <- cand[cand[[col]] %in% pool[[col]], , drop = FALSE]
            }
            n_pool <- nrow(cand)

            if (n_pool == 0) {
              return(list(
                value = v, label = dim$labeler(v),
                is_anchor = identical(v, anchor_val),
                peers = NULL, status = "empty_pool",
                n_pool = 0, reason = "No schools in this stratum match the pool filter"
              ))
            }

            # Suppress the expected "anchor not in pool's filter" note
            # from compute_peers — it fires for every stratum that
            # isn't the anchor's own, by design. That's noise here, not
            # a signal. Errors still propagate to the tryCatch below.
            r <- tryCatch(
              suppressMessages(compute_peers_cached(
                anchor_unitid   = a_uid,
                candidate_pool  = pool,
                theme_weights   = st$theme_weights,
                distance_metric = if (isTRUE(st$mahalanobis))
                                    "mahalanobis" else "euclidean",
                k               = per_value_k
              )),
              error = function(e) {
                # Compress wordy errors into the meaningful clause.
                msg <- conditionMessage(e)
                if (grepl("no variables pass the coverage threshold",
                          msg, ignore.case = TRUE))
                  return("Too few schools in this stratum for any variable to clear the 70% coverage threshold")
                if (grepl("anchor has no values", msg, ignore.case = TRUE))
                  return("Anchor missing data for every variable that survives coverage in this stratum")
                if (grepl("all theme weights are 0", msg, ignore.case = TRUE))
                  return("All theme weights are 0 — no dimensions to rank on")
                # Fallback: surface the raw message but trim length.
                if (nchar(msg) > 140) paste0(substr(msg, 1, 137), "...")
                else msg
              }
            )

            if (is.character(r)) {
              # tryCatch caught an error and returned the explanatory string.
              return(list(
                value = v, label = dim$labeler(v),
                is_anchor = identical(v, anchor_val),
                peers = NULL, status = "errored",
                n_pool = n_pool, reason = r
              ))
            }

            list(value = v, label = dim$labeler(v),
                 is_anchor = identical(v, anchor_val),
                 peers = r$peers, status = "ok",
                 n_pool = n_pool, reason = NA_character_)
          })

          # Order: anchor's stratum first, then alphabetical by label.
          ord <- order(!vapply(out, function(x) x$is_anchor, logical(1)),
                       vapply(out, function(x) as.character(x$label),
                              character(1)))
          out[ord]
        })
    })

    output$stratified_results <- renderUI({
      runs <- stratified_runs()
      if (is.null(runs) || !length(runs)) return(NULL)

      cards <- lapply(runs, function(s) {
        # Card status chip in the header — anchor highlight wins, then
        # an explicit status pill for empty / errored strata.
        status_chips <- tagList(
          if (isTRUE(s$is_anchor))
            tags$span(class = "peer-strat-anchor-chip", "Anchor stratum"),
          if (identical(s$status, "empty_pool"))
            tags$span(class = "peer-strat-status-chip peer-strat-status-empty",
                      "Empty pool"),
          if (identical(s$status, "errored"))
            tags$span(class = "peer-strat-status-chip peer-strat-status-error",
                      "No peers ranked")
        )

        card_class <- "peer-strat-card"
        if (isTRUE(s$is_anchor))
          card_class <- paste(card_class, "peer-strat-card-anchor")
        if (identical(s$status, "empty_pool") ||
            identical(s$status, "errored"))
          card_class <- paste(card_class, "peer-strat-card-empty")

        header <- tags$div(class = "peer-strat-card-title",
          tags$span(class = "peer-strat-card-label",
                    if (is.na(s$label)) as.character(s$value)
                    else as.character(s$label)),
          status_chips
        )

        # Body: either the peer mini-table or an explanatory note.
        body <- if (identical(s$status, "ok") && !is.null(s$peers) &&
                    nrow(s$peers) > 0) {
          peers_df <- s$peers
          rows_html <- paste(
            vapply(seq_len(nrow(peers_df)), function(i) {
              sprintf("<tr><td>%d</td><td>%s</td><td class='dt-center'>%s</td><td class='dt-right'>%.3f</td></tr>",
                      peers_df$rank[i],
                      htmltools::htmlEscape(peers_df$instnm[i]),
                      htmltools::htmlEscape(peers_df$stabbr[i]),
                      peers_df$distance[i])
            }, character(1)),
            collapse = ""
          )
          HTML(sprintf(
            "<table class='peer-strat-card-table'><thead><tr><th>#</th><th>School</th><th class='dt-center'>State</th><th class='dt-right'>Dist.</th></tr></thead><tbody>%s</tbody></table>",
            rows_html))
        } else {
          tags$div(class = "peer-strat-empty-body",
            tags$p(class = "peer-strat-empty-reason", s$reason),
            tags$p(class = "peer-strat-empty-pool-size",
                   sprintf("%d schools in this stratum after pool filter",
                           s$n_pool %||% 0))
          )
        }

        tags$div(class = card_class, header, body)
      })
      tags$div(class = "peer-strat-grid", cards)
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
