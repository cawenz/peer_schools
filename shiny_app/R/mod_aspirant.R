# =============================================================================
# Aspirant Peers module
#
# Finds schools that are similar to the anchor in context (size, sector,
# Carnegie class, region — set via the candidate pool) but BETTER than the
# anchor on user-chosen aspirational metrics (lower acceptance rate,
# higher grad rate, higher endowment, etc.).
#
# Two-section result:
#   Strict aspirants — beat the anchor on every chosen aspirational metric
#   Near-miss aspirants — beat the anchor on all but one
#
# Layout choice: no sidebar. The essential interaction (anchor + which
# metrics to aspire on + Run) sits in a compact control bar at the top of
# the page. Pool filters, theme weights, and output counts live behind a
# collapsed "Advanced" accordion. This keeps the simpler-than-Peer-Search
# nature of the tool obvious.
#
# Row click opens a focused "Aspirational gap" modal showing per-metric
# anchor → candidate diffs.
#
# Methodology lives in R/peer_pipeline.R:
#   ASPIRANT_DIRECTIONS  named list  metric -> "higher" | "lower"
#   ASPIRANT_LABELS      named list  metric -> "Acceptance rate (more selective)"
#   compute_aspirant_peers()         wraps compute_peers + directional filter
# =============================================================================

# -----------------------------------------------------------------------------
# Main UI (everything lives here — no sidebar)
# -----------------------------------------------------------------------------
aspirantUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Aspirant Peers"),
    p(class = "section-intro",
      "Schools that look like the anchor in ", tags$em("context"),
      " (size, sector, classification, region) but ",
      tags$strong("beat"), " it on the metrics you choose. The ",
      tags$strong("strict"), " list contains aspirants that exceed the ",
      "anchor on every chosen metric. The ", tags$strong("near-miss"),
      " list contains schools that exceed the anchor on all but one ",
      "metric (so you can see what's just out of reach)."),

    # ---- Essential controls (top bar) ----
    tags$div(class = "asp-control-bar",
      tags$div(class = "asp-control-anchor",
        tags$label("Anchor school"),
        selectizeInput(ns("anchor_unitid"),
                       label = NULL,
                       choices = NULL,
                       width = "100%",
                       options = list(
                         placeholder = "Type to search institutions",
                         maxOptions  = 50
                       ))
      ),
      tags$div(class = "asp-control-metrics",
        tags$label("Aspire higher on (pick one or more)"),
        selectizeInput(ns("aspirant_metrics"),
                       label = NULL,
                       choices = NULL, multiple = TRUE,
                       width = "100%",
                       options = list(
                         placeholder = "Add metrics",
                         plugins = list("remove_button")
                       ))
      ),
      tags$div(class = "asp-control-run",
        actionButton(ns("run"), "Run aspirant search",
                     icon = icon("play"),
                     class = "btn btn-primary btn-lg")
      )
    ),

    # ---- Advanced (collapsed by default) ----
    accordion(
      id = ns("advanced"),
      open = FALSE,
      accordion_panel(
        title = tagList(icon("sliders"), " Advanced"),
        value = "advanced",   # bslib needs an explicit string when title is a tagList
        tags$div(class = "asp-advanced-grid",

          # Candidate pool
          tags$div(class = "asp-advanced-section",
            tags$h6("Candidate pool"),
            checkboxInput(ns("pool_ranked"),
                          "Ranked universe only", value = TRUE),
            tags$div(class = "asp-pool-row",
              checkboxInput(ns("pool_class_same"),
                            "Same US News classification as anchor",
                            value = TRUE),
              selectInput(ns("pool_class"), label = NULL,
                          choices = NULL, multiple = TRUE, selectize = TRUE)
            ),
            tags$div(class = "asp-pool-row",
              checkboxInput(ns("pool_control_same"),
                            "Same sector as anchor", value = TRUE),
              selectInput(ns("pool_control"), label = NULL,
                          choices = NULL, multiple = TRUE, selectize = TRUE)
            )
          ),

          # Context theme weights
          tags$div(class = "asp-advanced-section",
            tags$h6("Context theme weights"),
            helpText(tags$small(class = "text-muted",
              "Weight the similarity ranking among candidates that pass ",
              "the aspirational filter. Athletics defaults to 0.")
            ),
            tags$div(class = "asp-weights-grid",
              lapply(.THEMES, function(th) {
                dv <- if (exists(".theme_default_weight",
                                  envir = globalenv()))
                        .theme_default_weight(th)
                      else if (th == "athletics") 0 else 1.0
                sliderInput(ns(paste0("weight_", th)),
                            label = stringr::str_to_title(th),
                            min = 0, max = 3, value = dv,
                            step = 0.25, ticks = FALSE)
              })
            )
          ),

          # Output sizes
          tags$div(class = "asp-advanced-section",
            tags$h6("Output"),
            sliderInput(ns("k"), "Strict aspirants to return",
                        min = 5, max = 50, value = 20, step = 1,
                        ticks = FALSE),
            sliderInput(ns("near_miss_k"), "Near-miss candidates to show",
                        min = 0, max = 30, value = 10, step = 1,
                        ticks = FALSE)
          )
        )
      )
    ),

    # ---- Results ----
    uiOutput(ns("header_or_empty")),
    uiOutput(ns("strict_section")),
    uiOutput(ns("near_miss_section"))
  )
}

# -----------------------------------------------------------------------------
# Server (single moduleServer — no separate sidebar)
# -----------------------------------------------------------------------------
aspirantServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Populate choices ---
    anchor_choices <- {
      vals <- .SCHOOLS$unitid
      names(vals) <- sprintf("%s (%s)", .SCHOOLS$instnm, .SCHOOLS$stabbr)
      vals[order(names(vals))]
    }
    updateSelectizeInput(session, "anchor_unitid",
                         choices = anchor_choices,
                         selected = .DEFAULT_ANCHOR_UNITID,
                         server = FALSE)

    raw_classes  <- sort(unique(stats::na.omit(.SCHOOLS$usnews_classification)))
    class_choices <- setNames(raw_classes, .prettify_classification(raw_classes))
    updateSelectInput(session, "pool_class", choices = class_choices)

    control_labels <- c("public" = "Public",
                        "private_nfp" = "Private (nonprofit)")
    raw_controls <- sort(unique(stats::na.omit(.SCHOOLS$control_grp)))
    control_choices <- setNames(
      raw_controls,
      ifelse(raw_controls %in% names(control_labels),
             control_labels[raw_controls], raw_controls)
    )
    updateSelectInput(session, "pool_control",
                      choices = control_choices, selected = raw_controls)

    asp_choices <- {
      v <- names(ASPIRANT_LABELS)
      names(v) <- unname(unlist(ASPIRANT_LABELS))
      v
    }
    updateSelectizeInput(session, "aspirant_metrics",
                         choices = asp_choices,
                         selected = character(0),
                         server = FALSE)

    anchor_row <- reactive({
      uid <- as.integer(input$anchor_unitid)
      if (is.na(uid)) return(NULL)
      .SCHOOLS[.SCHOOLS$unitid == uid, , drop = FALSE]
    })

    # --- Build the search state on demand ---
    search_state <- reactive({
      ar <- anchor_row()
      anchor_uid <- as.integer(input$anchor_unitid)
      if (is.na(anchor_uid)) anchor_uid <- .DEFAULT_ANCHOR_UNITID

      pool <- list()
      if (isTRUE(input$pool_ranked)) pool$in_ranked_universe <- TRUE
      if (isTRUE(input$pool_class_same)) {
        if (!is.null(ar) && !is.na(ar$usnews_classification))
          pool$usnews_classification <- ar$usnews_classification
      } else if (length(input$pool_class)) {
        pool$usnews_classification <- input$pool_class
      }
      if (isTRUE(input$pool_control_same)) {
        if (!is.null(ar) && !is.na(ar$control_grp))
          pool$control_grp <- ar$control_grp
      } else if (length(input$pool_control)) {
        pool$control_grp <- input$pool_control
      }

      theme_w <- setNames(
        lapply(.THEMES, function(th) input[[paste0("weight_", th)]]),
        .THEMES
      )

      list(
        anchor_unitid    = anchor_uid,
        candidate_pool   = pool,
        theme_weights    = theme_w,
        aspirant_metrics = input$aspirant_metrics %||% character(0),
        k                = input$k,
        near_miss_k      = input$near_miss_k
      )
    })

    aspirant_result <- reactiveVal(NULL)

    observeEvent(input$run, {
      st <- isolate(search_state())
      req(st$anchor_unitid)
      if (!length(st$aspirant_metrics)) {
        showNotification(
          "Pick at least one aspirational metric before running.",
          type = "warning", duration = 5)
        return()
      }

      anchor_name <- .SCHOOLS$instnm[match(st$anchor_unitid, .SCHOOLS$unitid)]
      withProgress(
        message = "Finding aspirant peers...",
        detail  = sprintf("Anchor: %s", anchor_name),
        value   = 0.5,
        {
          res <- tryCatch(
            compute_aspirant_peers(
              anchor_unitid    = st$anchor_unitid,
              candidate_pool   = st$candidate_pool,
              theme_weights    = st$theme_weights,
              k                = st$k,
              aspirant_metrics = st$aspirant_metrics,
              near_miss_k      = st$near_miss_k,
              # Critical: point at the Shiny app's resolved output path
              # rather than the relative "output" default. Without this
              # compute_aspirant_peers tries to read shiny_app/output
              # which doesn't exist.
              output_dir       = .OUTPUT_DIR
            ),
            error = function(e) {
              showNotification(
                tags$div(tags$strong("Aspirant search failed: "),
                          tags$br(), e$message),
                type = "error", duration = 12)
              NULL
            }
          )
          aspirant_result(res)
        }
      )
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    # -------------------------------------------------------------------------
    # Header / empty state
    # -------------------------------------------------------------------------
    output$header_or_empty <- renderUI({
      res <- aspirant_result()
      if (is.null(res)) {
        return(div(class = "note-box",
                   tags$strong("No aspirant search run yet. "),
                   "Pick an anchor, choose at least one aspirational metric, ",
                   "and click ", tags$em("Find aspirant peers"), "."))
      }
      n_metrics <- length(res$aspirant_metrics)
      anchor_uid <- res$meta$anchor_unitid %||% NA
      anchor_name <- if (!is.na(anchor_uid))
        .SCHOOLS$instnm[.SCHOOLS$unitid == anchor_uid][1] else "(unknown)"
      div(class = "stats-grid",
        div(class = "stat-card",
            div(class = "stat-title", "Anchor"),
            div(class = "stat-value", style = "font-size: 1.1rem;",
                anchor_name)),
        div(class = "stat-card",
            div(class = "stat-title", "Aspirational metrics"),
            div(class = "stat-value", n_metrics),
            div(class = "stat-subtitle",
                paste(names(res$aspirant_metrics), collapse = ", "))),
        div(class = "stat-card",
            div(class = "stat-title", "Strict aspirants"),
            div(class = "stat-value", nrow(res$strict_peers))),
        div(class = "stat-card",
            div(class = "stat-title", "Near-miss"),
            div(class = "stat-value", nrow(res$near_miss_peers)))
      )
    })

    # -------------------------------------------------------------------------
    # Per-section DT builder
    # -------------------------------------------------------------------------
    .build_table <- function(df, asp_metrics, anchor_values,
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

      dt_df <- do.call(data.frame,
                        c(cols, list(stringsAsFactors = FALSE,
                                      check.names = FALSE)))

      target_cols <- which(names(dt_df) %in%
                            vapply(asp_metrics,
                                    function(m) ASPIRANT_LABELS[[m]] %||% m,
                                    character(1))) - 1L

      DT::datatable(
        dt_df,
        escape = FALSE,
        rownames = FALSE,
        selection = list(mode = "single", target = "row"),
        options = list(
          pageLength = 50,
          dom = "tip",
          order = list(list(0, "asc")),
          columnDefs = list(
            list(className = "dt-right",  targets = c(0, 3)),
            list(className = "dt-center", targets = 2),
            list(className = "asp-metric-cell", targets = target_cols)
          )
        ),
        class = "compact stripe hover"
      )
    }

    # -------------------------------------------------------------------------
    # Strict + near-miss sections
    # -------------------------------------------------------------------------
    output$strict_section <- renderUI({
      res <- aspirant_result(); req(res)
      tagList(
        h5(sprintf("Strict aspirants (%d) — beat the anchor on every chosen metric",
                   nrow(res$strict_peers))),
        if (nrow(res$strict_peers))
          DT::DTOutput(ns("strict_table"))
        else
          div(class = "note-box",
              "No schools in the candidate pool beat the anchor on every ",
              "chosen metric. Try removing one of the aspirational metrics, ",
              "or widening the candidate pool in Advanced.")
      )
    })

    output$strict_table <- DT::renderDT({
      res <- aspirant_result(); req(res, nrow(res$strict_peers) > 0)
      .build_table(res$strict_peers, names(res$aspirant_metrics),
                   res$anchor_values, near_miss = FALSE)
    })

    output$near_miss_section <- renderUI({
      res <- aspirant_result(); req(res)
      if (!nrow(res$near_miss_peers)) return(NULL)
      tagList(
        tags$hr(class = "cohort-section-divider"),
        h5(sprintf("Near-miss (%d) — beat the anchor on all but one metric",
                   nrow(res$near_miss_peers))),
        p(class = "section-intro",
          tags$small(
            "Schools just out of reach. The ", tags$strong("Missed"),
            " column names the single metric they fell short on.")),
        DT::DTOutput(ns("near_miss_table"))
      )
    })

    output$near_miss_table <- DT::renderDT({
      res <- aspirant_result(); req(res, nrow(res$near_miss_peers) > 0)
      .build_table(res$near_miss_peers, names(res$aspirant_metrics),
                   res$anchor_values, near_miss = TRUE)
    })

    # -------------------------------------------------------------------------
    # Row click -> Aspirational gap modal
    # -------------------------------------------------------------------------
    .open_modal <- function(row, anchor_values, asp_metrics) {
      anchor_uid  <- aspirant_result()$meta$anchor_unitid
      anchor_name <- .SCHOOLS$instnm[.SCHOOLS$unitid == anchor_uid][1]
      anchor_st   <- .SCHOOLS$stabbr[.SCHOOLS$unitid == anchor_uid][1]

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
                 else tags$span(class = "asp-down", HTML("&#9660;"))
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
              sprintf("(%+s)", .format_value(gap, fmt))
            )
          )
        )
      })

      showModal(modalDialog(
        title = tagList(
          tags$div(class = "asp-modal-title", "Aspirational gap"),
          tags$div(class = "asp-modal-subtitle",
            tags$strong(row$instnm),
            sprintf(" (%s) vs ", row$stabbr),
            tags$strong(anchor_name),
            sprintf(" (%s)", anchor_st))
        ),
        size = "l", easyClose = TRUE, fade = TRUE,
        footer = tagList(modalButton("Close")),
        div(class = "asp-modal-body", gap_rows)
      ))
    }

    observeEvent(input$strict_table_rows_selected, {
      res <- aspirant_result(); req(res, nrow(res$strict_peers) > 0)
      ix <- input$strict_table_rows_selected
      if (!length(ix)) return()
      .open_modal(res$strict_peers[ix, ],
                   res$anchor_values,
                   names(res$aspirant_metrics))
      DT::dataTableProxy("strict_table") %>% DT::selectRows(NULL)
    })

    observeEvent(input$near_miss_table_rows_selected, {
      res <- aspirant_result(); req(res, nrow(res$near_miss_peers) > 0)
      ix <- input$near_miss_table_rows_selected
      if (!length(ix)) return()
      .open_modal(res$near_miss_peers[ix, ],
                   res$anchor_values,
                   names(res$aspirant_metrics))
      DT::dataTableProxy("near_miss_table") %>% DT::selectRows(NULL)
    })

    invisible(NULL)
  })
}
