# =============================================================================
# Trends module
#
# Pick one school + one variable and see the year-over-year trajectory
# against a comparison group (most recent peer search, current cohort, or
# the full ranked universe). The chart shows:
#   - the school's own line (bold purple, with year markers)
#   - the comparison group's 25th-75th percentile band (faint purple)
#   - the comparison group's median (dashed gray line)
#
# Why this tab exists: most surfaces in the app collapse multi-year facts
# into a 5-year mean. Trends preserves the panel so the user can see
# directional movement and compare trajectories, not just levels.
#
# Data source: .FACTS (long, unitid x year x metric x value), not
# .SCHOOLS_WIDE (which is already mean-collapsed).
#
# Cross-module inputs:
#   peer_result          reactive returning the Peer Search peer_result list
#                         (or NULL if no search has been run)
#   cohort_state         reactive returning the cohortServer's tibble of
#                         (unitid, action, origin, ...)
#   cohort_anchor_uid    reactive returning the cohort's anchor unitid
# =============================================================================

trendsUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Trends"),
    p(class = "section-intro",
      "Year-over-year trajectory for any variable, plotted against a ",
      "comparison group. Most variables are a 5-year panel (2020-2024); ",
      "a few are single-year snapshots and show as a single dot."),

    # ---- Top control bar (no sidebar; mirrors the Aspirant layout) ----
    tags$div(class = "trend-control-bar",
      tags$div(class = "trend-control-school",
        tags$label("Anchor school"),
        selectizeInput(ns("school_unitid"),
                       label = NULL,
                       choices = NULL,
                       width = "100%",
                       options = list(
                         placeholder = "Type to search institutions",
                         maxOptions  = 50
                       ))
      ),
      tags$div(class = "trend-control-variable",
        tags$label("Variable"),
        selectizeInput(ns("metric"),
                       label = NULL,
                       choices = NULL,
                       width = "100%",
                       options = list(
                         placeholder = "Type to search variables"
                       ))
      ),
      tags$div(class = "trend-control-compare",
        tags$label("Compare against"),
        # Choices populated server-side so the labels can reflect live
        # state — e.g. "Peer Search results (none yet, using universe)"
        # vs "Peer Search results (20 peers)".
        selectInput(ns("compare_group"),
                    label = NULL,
                    choices = NULL,
                    selected = "universe_usnews",
                    width = "100%")
      )
    ),

    uiOutput(ns("variable_header")),

    # Plotly chart sits directly in the static UI (not inside a renderUI)
    # so Shiny registers and binds the output reliably. The pill above it
    # is a thin UI block that updates with the comparison group, and the
    # chart itself hides cleanly when there's no data via req() inside
    # renderPlotly.
    uiOutput(ns("compare_pill")),

    # Hard container: forces plotly to live inside a fixed-height block
    # with overflow hidden, so its SVG doesn't auto-stretch and overlap
    # the table below. Without this, plotly's autosize sometimes renders
    # past the declared 440px and the DT table ends up visually inside
    # the chart area.
    tags$div(class = "trend-chart-container",
      plotlyOutput(ns("trend_plot"), height = "440px", width = "100%")
    ),

    # Table section in its own block with clear: both so it's guaranteed
    # to start below the chart container regardless of any sibling
    # positioning quirks.
    tags$div(class = "trend-table-container",
      uiOutput(ns("table_section"))
    )
  )
}

trendsServer <- function(id,
                          peer_result        = reactive(NULL),
                          cohort_state       = reactive(NULL),
                          cohort_anchor_uid  = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- School picker ---
    school_choices <- {
      vals <- .SCHOOLS$unitid
      names(vals) <- sprintf("%s (%s)", .SCHOOLS$instnm, .SCHOOLS$stabbr)
      vals
    }
    updateSelectizeInput(session, "school_unitid",
                         choices  = school_choices,
                         selected = .DEFAULT_ANCHOR_UNITID,
                         server   = TRUE)

    # --- Compare-against choices: built from live cross-tab state so
    # each option says exactly what it'll resolve to right now. The
    # "Peer Search" and "Cohort" labels show counts when data exists, or
    # a clear "(none yet)" suffix when not.
    observe({
      pr <- peer_result()
      cs <- cohort_state()

      peer_label <- if (!is.null(pr) && !is.null(pr$peers))
        sprintf("Peer Search results (%d peers)", nrow(pr$peers))
      else
        "Peer Search results (none yet — falls back to universe)"

      cohort_label <- if (!is.null(cs)) {
        n_in <- sum(cs$action %in% c("Keep", "Maybe", "Proposed"))
        sprintf("Cohort Builder cohort (%d in-cohort + anchor)", n_in)
      } else {
        "Cohort Builder cohort (none loaded — falls back to universe)"
      }

      choices <- c(
        "peers"           = peer_label,
        "cohort"          = cohort_label,
        "universe_usnews" = "Ranked universe — same US News class as anchor",
        "universe_ic"     = "Ranked universe — same Carnegie IC as anchor",
        "universe"        = "Ranked universe (all ranked 4-year nonprofit)"
      )
      # selectInput choices want names = display label, values = key.
      sel_choices <- setNames(names(choices), unname(choices))

      updateSelectInput(session, "compare_group",
                        choices  = sel_choices,
                        selected = isolate(input$compare_group) %||%
                                    "universe_usnews")
    })

    # --- Variable picker (grouped by category; only metrics that exist in
    # .FACTS, so classifications living only in schools.csv don't appear) ---
    metric_choices <- reactive({
      vars_in_facts <- unique(.FACTS$metric)
      df <- .VARIABLES %>%
        dplyr::filter(metric %in% vars_in_facts) %>%
        dplyr::filter(!is.na(display_name))
      df <- df[order(df$category, df$display_name), ]
      split_df <- split(df, df$category)
      lapply(split_df, function(g) {
        v <- g$metric
        names(v) <- g$display_name
        v
      })
    })

    observe({
      updateSelectizeInput(session, "metric",
                           choices  = metric_choices(),
                           selected = "total_enrollment",
                           server   = FALSE)
    })

    # Helper: ranked-universe schools matching the anchor's value on a
    # given classification column. Returns the full ranked universe as a
    # safe fallback if the anchor's value is NA.
    .universe_matching_anchor <- function(class_col) {
      uid <- as.integer(input$school_unitid)
      base_uids <- .SCHOOLS$unitid[.SCHOOLS$in_ranked_universe %in% TRUE]
      if (is.na(uid) || !class_col %in% names(.SCHOOLS)) return(base_uids)
      anchor_val <- .SCHOOLS[[class_col]][.SCHOOLS$unitid == uid][1]
      if (is.na(anchor_val) || !nzchar(as.character(anchor_val)))
        return(base_uids)
      matching <- .SCHOOLS$unitid[
        .SCHOOLS$in_ranked_universe %in% TRUE &
        !is.na(.SCHOOLS[[class_col]]) &
        .SCHOOLS[[class_col]] == anchor_val
      ]
      if (!length(matching)) base_uids else as.integer(matching)
    }

    # ----- Comparison group resolution -----
    # Returns a character/integer vector of unitids defining the comparison
    # group, given the user's choice. Falls back to ranked universe if the
    # chosen source is empty (e.g. no peer search run yet).
    compare_uids <- reactive({
      choice <- input$compare_group %||% "peers"
      uids <- integer(0)

      if (choice == "peers") {
        pr <- peer_result()
        if (!is.null(pr) && !is.null(pr$peers))
          uids <- as.integer(pr$peers$unitid)
      } else if (choice == "cohort") {
        cs <- cohort_state(); a_uid <- cohort_anchor_uid()
        if (!is.null(cs)) {
          cohort_uids <- cs$unitid[cs$action %in% c("Keep", "Maybe", "Proposed")]
          uids <- as.integer(unique(c(a_uid, cohort_uids)))
        }
      } else if (choice == "universe_usnews") {
        uids <- .universe_matching_anchor("usnews_classification")
      } else if (choice == "universe_ic") {
        uids <- .universe_matching_anchor("ic2025_label")
      }
      # Fallback: ranked universe (also the explicit "universe" choice).
      if (!length(uids) || choice == "universe") {
        uids <- .SCHOOLS$unitid[.SCHOOLS$in_ranked_universe %in% TRUE]
      }
      uids
    })

    compare_label <- reactive({
      choice <- input$compare_group %||% "peers"
      pr <- peer_result(); cs <- cohort_state()
      uid <- as.integer(input$school_unitid)
      n   <- length(compare_uids())

      # Pull the anchor's classification value to mention in the label, so
      # the user sees exactly which class is being used (e.g. "National
      # Liberal Arts Colleges" instead of an opaque code).
      anchor_class_val <- function(class_col, prettify = NULL) {
        if (is.na(uid)) return(NA_character_)
        v <- .SCHOOLS[[class_col]][.SCHOOLS$unitid == uid][1]
        if (is.na(v)) return(NA_character_)
        if (!is.null(prettify)) prettify(v) else as.character(v)
      }

      switch(choice,
        peers = if (!is.null(pr) && !is.null(pr$peers))
                  sprintf("Most recent peer search (%d peers)",
                          nrow(pr$peers))
                else "Ranked universe (no peer search run yet)",
        cohort = if (!is.null(cs))
                   sprintf("Current cohort (%d in-cohort + anchor)",
                           sum(cs$action %in% c("Keep","Maybe","Proposed")))
                 else "Ranked universe (no cohort loaded)",
        universe_usnews = {
          cls <- anchor_class_val("usnews_classification",
                                   .prettify_classification)
          if (is.na(cls))
            sprintf("Ranked universe (anchor has no US News class; %d schools)", n)
          else
            sprintf("Ranked universe, same US News class as anchor — %s (%d schools)",
                    cls, n)
        },
        universe_ic = {
          cls <- anchor_class_val("ic2025_label")
          if (is.na(cls))
            sprintf("Ranked universe (anchor has no Carnegie IC; %d schools)", n)
          else
            sprintf("Ranked universe, same Carnegie IC as anchor — %s (%d schools)",
                    cls, n)
        },
        universe = sprintf("Ranked universe — all %d schools", n)
      )
    })

    # ----- Time-series data for the school -----
    school_series <- reactive({
      uid <- as.integer(input$school_unitid)
      m   <- input$metric
      if (is.na(uid) || is.null(m) || !nzchar(m)) return(NULL)
      .FACTS %>%
        dplyr::filter(unitid == uid, metric == m, is.finite(value)) %>%
        dplyr::select(year, value) %>%
        dplyr::arrange(year)
    })

    # ----- Per-year stats for the comparison group -----
    compare_stats <- reactive({
      uids <- compare_uids()
      m    <- input$metric
      if (!length(uids) || is.null(m) || !nzchar(m)) return(NULL)
      .FACTS %>%
        dplyr::filter(unitid %in% uids, metric == m, is.finite(value)) %>%
        dplyr::group_by(year) %>%
        dplyr::summarise(
          n      = dplyr::n(),
          q1     = stats::quantile(value, 0.25, na.rm = TRUE, names = FALSE),
          median = stats::quantile(value, 0.50, na.rm = TRUE, names = FALSE),
          q3     = stats::quantile(value, 0.75, na.rm = TRUE, names = FALSE),
          minv   = min(value, na.rm = TRUE),
          maxv   = max(value, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        dplyr::arrange(year)
    })

    var_meta <- reactive({
      m <- input$metric
      if (is.null(m) || !nzchar(m)) return(NULL)
      r <- .VARIABLES[match(m, .VARIABLES$metric), , drop = FALSE]
      if (!nrow(r)) return(NULL)
      r
    })

    # =========================================================================
    # Variable header card
    # =========================================================================
    output$variable_header <- renderUI({
      m  <- input$metric; req(m)
      vm <- var_meta();   req(vm)

      dn  <- vm$display_name %||% m
      src <- if (exists(".simplify_source", envir = globalenv()))
               .simplify_source(vm$source) else vm$source
      computed <- exists(".is_computed_source", envir = globalenv()) &&
                  .is_computed_source(vm$source)
      yrs <- .VAR_YEARS_LABEL[[m]] %||% "panel info unavailable"
      cat_label <- if (!is.na(vm$category)) vm$category else "(uncategorized)"

      desc <- if (!is.na(vm$notes) && nzchar(vm$notes)) vm$notes
              else if (!is.na(vm$coverage_note) && nzchar(vm$coverage_note))
                vm$coverage_note
              else NULL

      tagList(
        tags$div(class = "trend-var-header",
          tags$div(class = "trend-var-title",
            tags$span(class = "trend-var-name", dn),
            tags$span(class = "trend-var-cat",
                      toupper(cat_label))
          ),
          tags$div(class = "trend-var-chips",
            if (!is.null(src) && !is.na(src) && nzchar(src))
              tags$span(class = "trend-chip", tags$strong("Source: "), src),
            if (computed)
              tags$span(class = "trend-chip trend-chip-computed",
                        "Computed"),
            if (!is.na(vm$format))
              tags$span(class = "trend-chip", tags$strong("Format: "),
                         vm$format),
            tags$span(class = "trend-chip", tags$strong("Years: "), yrs)
          ),
          if (!is.null(desc))
            tags$p(class = "trend-var-desc", desc)
        )
      )
    })

    # =========================================================================
    # Chart
    # =========================================================================

    # Comparison label pill. Renders independently of the plot so the user
    # gets an immediate "what am I looking at" cue even before the chart
    # has fired.
    output$compare_pill <- renderUI({
      req(input$metric)
      tags$div(class = "trend-compare-pill",
        tags$small(tags$strong("Comparison: "), compare_label()))
    })

    output$trend_plot <- renderPlotly({
      m  <- input$metric; req(m)
      ss <- school_series(); req(ss, nrow(ss))
      cs <- compare_stats()

      vm   <- var_meta()
      fmt  <- if (!is.null(vm)) vm$format else NA
      ylab <- if (!is.null(vm) && !is.na(vm$display_name))
                vm$display_name else m

      anchor_uid  <- as.integer(input$school_unitid)
      anchor_name <- .SCHOOLS$instnm[.SCHOOLS$unitid == anchor_uid][1]

      # Plotly hovertemplate token for the value axis. Mirrors the cohort
      # inspector / Side-by-Side modal formatting.
      yfmt <- switch(
        as.character(fmt) %||% "",
        currency   = "$%{y:,.0f}",
        percentage = "%{y:.1f}%%",
        count      = "%{y:,.0f}",
        ratio      = "%{y:.2f}",
        "%{y:.4g}"
      )

      # --- Y-axis scale: log for heavily-tailed variables ---
      # Variables like HERD, endowments, and enrollment counts span 4-6
      # orders of magnitude across the universe; on a linear axis the
      # box compresses to a single line at the bottom. Use log scale for
      # any variable that the peer pipeline already flags as log-worthy
      # (LOG_TRANSFORM_VARS) AND whose values are all positive.
      use_log <- exists("LOG_TRANSFORM_VARS", envir = globalenv()) &&
                  m %in% LOG_TRANSFORM_VARS &&
                  all(ss$value > 0, na.rm = TRUE) &&
                  (is.null(cs) || all(cs$minv > 0, na.rm = TRUE))

      yaxis_cfg <- list(title = ylab, gridcolor = "#F4EDEC",
                         zeroline = FALSE)
      if (use_log) {
        yaxis_cfg$type <- "log"
        # SI-prefix tick formatting reads naturally on a log scale
        # ($1k, $10k, $100k, $1M, ...). plotly's d3 format ",.2~s"
        # gives 1k / 100k / 1M / 1B style labels.
        if (identical(as.character(fmt), "currency"))
          yaxis_cfg$tickformat <- "$,.2~s"
        else if (identical(as.character(fmt), "count"))
          yaxis_cfg$tickformat <- ",.2~s"
        yaxis_cfg$title <- paste0(ylab, "  (log scale)")
      } else {
        if (identical(as.character(fmt), "percentage"))
          yaxis_cfg$ticksuffix <- "%"
        if (identical(as.character(fmt), "currency"))
          yaxis_cfg$tickprefix <- "$"
      }

      base_layout <- list(
        # Centered horizontal legend below the chart. Anchoring left
        # at x=0 pushes the legend under the y-axis label and labels
        # like "Comparison distribution (719 schools)" end up crammed
        # against the y-axis ticks. Centered + a deeper bottom margin
        # gives the labels room to breathe.
        legend = list(orientation = "h",
                       x = 0.5, xanchor = "center",
                       y = -0.22, yanchor = "top",
                       bgcolor = "rgba(255,255,255,0.85)",
                       bordercolor = "rgba(0,0,0,0)"),
        plot_bgcolor  = "#FFFFFF",
        paper_bgcolor = "#FFFFFF",
        hoverlabel = list(bgcolor = "#251230", bordercolor = "#251230",
                           font = list(color = "#FFFFFF", size = 12)),
        margin = list(t = 20, r = 30, b = 100, l = 80)
      )
      plotly_config <- function(p) {
        config(p,
          displayModeBar = TRUE,
          displaylogo    = FALSE,
          modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d")
        )
      }

      # --- Single-year snapshot branch ---
      # When a variable is a one-year snapshot (e.g. HERD as a 3-yr-avg
      # Carnegie release stored at year=2024), the time-series view
      # collapses to one point with no context. Switch to a vertical
      # boxplot of the comparison-group distribution with the anchor's
      # value marked as a labeled diamond on top.
      n_years_comp <- if (!is.null(cs)) nrow(cs) else 0L
      single_year  <- nrow(ss) <= 1 && n_years_comp <= 1
      if (single_year) {
        yr <- if (!is.null(cs) && nrow(cs)) cs$year[1] else ss$year[1]
        uids <- compare_uids()
        raw_vals <- .FACTS$value[.FACTS$year == yr &
                                   .FACTS$metric == m &
                                   .FACTS$unitid %in% uids]
        raw_vals <- raw_vals[is.finite(raw_vals)]
        validate(need(length(raw_vals) >= 5,
                      "Comparison group has too few values to plot."))

        hover_school <- paste0("<b>", anchor_name, "</b><br>",
                                yfmt, "<extra></extra>")

        # x grouping label so the box has a name; we hide the tick text
        # because there's nothing meaningful to put there.
        grp <- "Comparison distribution"

        p <- plot_ly() %>%
          add_boxplot(
            y = raw_vals,
            x = rep(grp, length(raw_vals)),
            name = sprintf("Comparison distribution (%d schools)",
                           length(raw_vals)),
            boxpoints = "outliers",
            jitter = 0.3,
            marker = list(color = "rgba(172, 158, 148, 0.6)", size = 4),
            fillcolor = "rgba(96, 45, 137, 0.18)",
            line = list(color = "#602D89", width = 1.5),
            hovertemplate = paste0(yfmt, "<extra></extra>")
          ) %>%
          add_markers(
            x = grp, y = ss$value[1],
            name = anchor_name,
            marker = list(color = "#602D89", size = 14, symbol = "diamond",
                          line = list(color = "#FFFFFF", width = 2)),
            hovertemplate = hover_school
          )

        # Annotation pointing at the anchor marker so it's clearly labeled.
        annots <- list(list(
          x = grp, y = ss$value[1],
          text = sprintf("<b>%s</b>", anchor_name),
          showarrow = TRUE, arrowhead = 2, arrowsize = 1,
          arrowwidth = 1.5, arrowcolor = "#602D89",
          ax = 45, ay = 0,
          bgcolor = "#251230", bordercolor = "#251230",
          font = list(color = "#FFFFFF", size = 11),
          xanchor = "left", yanchor = "middle"
        ))

        # No in-plot title — the variable header card above the chart
        # already shows the year via the "Years: snapshot (2024)" chip.
        # Use "closest" hover here (not unified) — there's only one
        # x-position, so unified mode is meaningless.
        return(
          p %>%
            layout(
              xaxis = list(title = "", showticklabels = FALSE,
                            gridcolor = "#F4EDEC", zeroline = FALSE),
              annotations = annots
            ) %>%
            cohc_plotly_theme(hovermode = "closest", yaxis = yaxis_cfg) %>%
            cohc_modebar(filename_root = "trend_boxplot")
        )
      }

      p <- plot_ly()

      # --- Comparison group: ribbon (Q1-Q3) + dashed median line ---
      if (!is.null(cs) && nrow(cs) >= 1) {
        # add_ribbons takes ymin/ymax and a dummy y; needs at least 2 points
        # for an actual ribbon. For 1-year cases we degrade to markers.
        if (nrow(cs) >= 2) {
          p <- p %>%
            add_ribbons(
              x = cs$year, ymin = cs$q1, ymax = cs$q3,
              name = "Comparison IQR (25th-75th)",
              line  = list(color = "rgba(96, 45, 137, 0.0)"),
              fillcolor = "rgba(96, 45, 137, 0.18)",
              hoverinfo = "skip"   # the median line carries the hover info;
                                    # ribbon hover with customdata indexing
                                    # was unreliable across plotly versions
            ) %>%
            add_lines(
              x = cs$year, y = cs$median,
              name = "Comparison median",
              line = list(color = "#6e6360", width = 2, dash = "dash"),
              hovertemplate = paste0("Year %{x}<br>Median ", yfmt,
                                      "<extra></extra>")
            )
        } else {
          # Single-year comparison: drop a median marker.
          p <- p %>% add_markers(
            x = cs$year, y = cs$median,
            name = "Comparison median",
            marker = list(color = "#6e6360", size = 9, symbol = "diamond"),
            hovertemplate = paste0("Year %{x}<br>Median ", yfmt,
                                    "<extra></extra>")
          )
        }
      }

      # --- School line + markers ---
      hover_school <- paste0("<b>", anchor_name, "</b><br>Year %{x}<br>",
                              yfmt, "<extra></extra>")
      if (nrow(ss) >= 2) {
        p <- p %>%
          add_lines(
            x = ss$year, y = ss$value,
            name = anchor_name,
            line   = list(color = "#602D89", width = 3),
            marker = list(color = "#602D89", size = 8),
            hovertemplate = hover_school
          ) %>%
          add_markers(
            x = ss$year, y = ss$value,
            name = anchor_name,
            marker = list(color = "#602D89", size = 9,
                          line = list(color = "#FFFFFF", width = 1.5)),
            hovertemplate = hover_school,
            showlegend = FALSE
          )
      } else {
        # Single-year snapshot: just a marker.
        p <- p %>%
          add_markers(
            x = ss$year, y = ss$value,
            name = anchor_name,
            marker = list(color = "#602D89", size = 12,
                          line = list(color = "#FFFFFF", width = 2)),
            hovertemplate = hover_school
          )
      }

      # yaxis_cfg is already defined above (shared with the single-year
      # branch). Just compute the year axis tick positions here.
      #
      # Year axis: explicit per-year ticks so plotly doesn't auto-generate
      # half-year tick positions (2020.5, 2021, 2021.5, ...) which the
      # integer formatter renders as duplicate labels "2020, 2021, 2021,
      # 2022, ...". Use the actual school-series years as tickvals.
      years_axis <- sort(unique(c(ss$year, if (!is.null(cs)) cs$year)))

      # Apply the cohc theme + unified-x hover. "x unified" shows every
      # trace's value at a single year when the user hovers — much
      # cleaner than plotly's default "closest" mode which only labels
      # one series at a time.
      p %>%
        layout(
          xaxis = list(title = "Year", gridcolor = "#F4EDEC",
                       tickmode = "array",
                       tickvals = years_axis,
                       ticktext = as.character(years_axis))
        ) %>%
        cohc_plotly_theme(hovermode = "x unified",
                           yaxis = yaxis_cfg) %>%
        cohc_modebar(filename_root = "trend") %>%
        # Bypass the default to keep the existing config keys live too,
        # in case modebar customization regresses on a plotly upgrade.
        config(
          displayModeBar = "hover",
          displaylogo    = FALSE,
          modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d")
        )
    })

    # =========================================================================
    # Year-by-year detail table
    # =========================================================================
    output$table_section <- renderUI({
      ss <- school_series()
      if (is.null(ss) || !nrow(ss)) return(NULL)
      tagList(
        tags$hr(class = "cohort-section-divider"),
        h5("Year-by-year detail"),
        DT::DTOutput(ns("trend_table"))
      )
    })

    output$trend_table <- DT::renderDT({
      ss <- school_series(); req(ss, nrow(ss))
      cs <- compare_stats()
      vm <- var_meta()
      fmt <- if (!is.null(vm)) vm$format else NA

      # Join the school and comparison series on year. Outer-join via merge
      # so years that only exist in one side still appear.
      tbl <- merge(
        ss %>% dplyr::rename(school_value = value),
        cs %>% dplyr::select(year, median, q1, q3, minv, maxv,
                              n_comparison = n),
        by = "year", all = TRUE
      )

      # School percentile vs comparison set (per year).
      tbl$pct <- vapply(seq_len(nrow(tbl)), function(i) {
        v <- tbl$school_value[i]; yr <- tbl$year[i]
        if (!is.finite(v)) return(NA_real_)
        pool <- .FACTS$value[.FACTS$year == yr &
                               .FACTS$metric == input$metric &
                               .FACTS$unitid %in% compare_uids()]
        pool <- pool[is.finite(pool)]
        if (!length(pool)) return(NA_real_)
        100 * mean(pool < v)
      }, numeric(1))

      out <- data.frame(
        Year       = tbl$year,
        School     = vapply(tbl$school_value,
                             function(v) .format_value(v, fmt), character(1)),
        Median     = vapply(tbl$median,
                             function(v) .format_value(v, fmt), character(1)),
        Range      = mapply(function(lo, hi) {
                              if (!is.finite(lo) || !is.finite(hi)) return("—")
                              sprintf("%s — %s",
                                      .format_value(lo, fmt),
                                      .format_value(hi, fmt))
                            }, tbl$minv, tbl$maxv, USE.NAMES = FALSE),
        IQR        = mapply(function(lo, hi) {
                              if (!is.finite(lo) || !is.finite(hi)) return("—")
                              sprintf("%s — %s",
                                      .format_value(lo, fmt),
                                      .format_value(hi, fmt))
                            }, tbl$q1, tbl$q3, USE.NAMES = FALSE),
        Percentile = ifelse(is.na(tbl$pct), "—",
                            sprintf("%.0f", tbl$pct)),
        `N pool`   = ifelse(is.na(tbl$n_comparison), 0,
                            tbl$n_comparison),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )

      DT::datatable(
        out,
        rownames = FALSE,
        selection = "none",
        options = list(
          pageLength = 10,
          dom = "tip",
          order = list(list(0, "asc")),
          columnDefs = list(
            list(className = "dt-center", targets = 0),
            list(className = "dt-right",  targets = c(1, 2, 5, 6))
          )
        ),
        class = "compact stripe hover"
      )
    })

    invisible(NULL)
  })
}
