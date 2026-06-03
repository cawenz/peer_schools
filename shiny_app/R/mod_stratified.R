# =============================================================================
# Stratified Peers tab.
#
# Runs compute_peers() once per stratum value (or once per pair of values
# when a second stratification dimension is engaged) and shows the top-K
# peers from each, with raw distance plus comparable metrics (relative
# distance and percentile rank). The anchor's own stratum is highlighted
# and its own row appears at the top of that stratum's table.
#
# Inputs:
#   sidebar_state  reactive list from sidebarServer; used as the source
#                  of defaults for anchor, theme weights, K, distance
#                  metric, and the ranked-universe-only flag.
#
# UI features:
#   - Per-tab anchor selectize (defaults to whatever the sidebar has)
#   - Primary stratification dimension (8 options)
#   - Optional second dimension for interaction-of-strata (default: None)
#   - Peers-per-stratum slider (1-10, default 3)
#   - "Apply sidebar pool filters" toggle (default OFF for wide view)
#   - Run button + cards per stratum, sorted by dim1 value then dim2
#   - Info popover per stratum value when a description exists
# =============================================================================

# Helper to build a simple dim definition for a *_label column in
# schools.csv. Sorts the values alphabetically and uses identity as the
# labeler since these are already human-readable.
.simple_dim <- function(label, column) {
  list(
    label      = label,
    column     = column,
    values     = function() sort(unique(stats::na.omit(.SCHOOLS[[column]]))),
    labeler    = identity,
    filter_key = column
  )
}

.STRATIFY_DIMS <- list(
  usnews_classification = list(
    label    = "US News classification",
    column   = "usnews_classification",
    values   = function() sort(unique(stats::na.omit(.SCHOOLS$usnews_classification))),
    labeler  = function(v) .prettify_classification(v),
    filter_key = "usnews_classification"
  ),
  ic2025_label = .simple_dim(
    "Carnegie Institutional Classification (2025)", "ic2025_label"
  ),
  saec2025_label = .simple_dim(
    "Carnegie Access & Earnings (2025)", "saec2025_label"
  ),
  research2025_label = .simple_dim(
    "Carnegie Research Activity (2025)", "research2025_label"
  ),
  setting2025_label = .simple_dim(
    "Carnegie Setting / Residential Character (2025)", "setting2025_label"
  ),
  religious_tradition = list(
    label    = "Religious tradition",
    column   = "religious_tradition",
    values   = function() sort(unique(stats::na.omit(.SCHOOLS$religious_tradition))),
    labeler  = identity,
    filter_key = "religious_tradition"
  ),
  control_grp = list(
    label    = "Sector (public vs private nonprofit)",
    column   = "control_grp",
    values   = function() sort(unique(stats::na.omit(.SCHOOLS$control_grp))),
    labeler  = function(v) .prettify_control(v),
    filter_key = "control_grp"
  ),
  region = list(
    label    = "Geographic region",
    column   = "region",
    values   = function() names(.REGIONS),
    labeler  = function(v) .REGION_LABELS[v],
    filter_key = "region"
  )
)

# Build the candidate_pool filter dict for a given stratum value, layering
# on top of the base filter. Region is special: it expands to a stabbr
# list and intersects with any pre-existing stabbr filter.
.build_stratum_filter <- function(base_filter, dim_key, stratum_value) {
  dim <- .STRATIFY_DIMS[[dim_key]]
  result <- base_filter
  if (identical(dim_key, "region")) {
    region_states <- .REGIONS[[stratum_value]]
    if (!is.null(base_filter$stabbr) && length(base_filter$stabbr)) {
      region_states <- intersect(region_states, base_filter$stabbr)
    }
    result$stabbr <- region_states
  } else {
    result[[dim$filter_key]] <- stratum_value
  }
  result
}

# Returns the anchor's value on a given dimension. For region, we have to
# reverse-map state abbr to region key, which is one-to-many (e.g. CT is in
# both Northeast and New England), so we return all matching region keys.
.anchor_stratum_value <- function(anchor_uid, dim_key) {
  if (is.null(anchor_uid)) return(NULL)
  if (identical(dim_key, "region")) {
    stabbr <- .SCHOOLS$stabbr[match(anchor_uid, .SCHOOLS$unitid)]
    if (is.na(stabbr)) return(NULL)
    keys <- names(.REGIONS)[vapply(.REGIONS, function(s) stabbr %in% s,
                                   logical(1))]
    return(keys)
  }
  col <- .STRATIFY_DIMS[[dim_key]]$column
  v <- .SCHOOLS[[col]][match(anchor_uid, .SCHOOLS$unitid)]
  if (is.na(v)) return(NULL)
  v
}

# Quick check: does the universe contain at least one school matching the
# (possibly composite) stratum filter? Used to skip compute_peers calls
# for empty cells in interaction stratification.
.stratum_has_schools <- function(base_filter, dim_key, sv,
                                  dim2_key = NULL, sv2 = NULL) {
  s <- .SCHOOLS
  for (col in names(base_filter)) {
    if (col == "in_ranked_universe") {
      if (isTRUE(base_filter[[col]])) s <- s[s$in_ranked_universe %in% TRUE, ]
    } else {
      s <- s[s[[col]] %in% base_filter[[col]], ]
    }
  }
  # Primary stratum
  if (identical(dim_key, "region")) {
    s <- s[s$stabbr %in% .REGIONS[[sv]], ]
  } else {
    col <- .STRATIFY_DIMS[[dim_key]]$column
    s <- s[s[[col]] %in% sv, ]
  }
  # Second stratum (optional)
  if (!is.null(dim2_key) && !is.null(sv2)) {
    if (identical(dim2_key, "region")) {
      s <- s[s$stabbr %in% .REGIONS[[sv2]], ]
    } else {
      col2 <- .STRATIFY_DIMS[[dim2_key]]$column
      s <- s[s[[col2]] %in% sv2, ]
    }
  }
  nrow(s) > 0
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
stratifiedSidebarUI <- function(id) {
  ns <- NS(id)
  dim_choices <- setNames(names(.STRATIFY_DIMS),
                          vapply(.STRATIFY_DIMS, `[[`, character(1), "label"))

  tagList(
    tags$h6("Stratified search"),
    tags$hr(),

    selectizeInput(ns("anchor_strat"),
                   label = "Anchor school",
                   choices = NULL, multiple = FALSE,
                   options = list(placeholder = "Type to search",
                                   maxOptions  = 50)),

    selectInput(ns("stratify_by"),
                label = "Stratify by",
                choices = dim_choices,
                selected = "usnews_classification"),

    selectInput(ns("stratify_by_2"),
                label = tagList("Then by ",
                                tags$small(class = "text-muted",
                                           "(optional)")),
                choices = c("(None)" = "__none__", dim_choices),
                selected = "__none__"),

    sliderInput(ns("k_per"), "Peers per stratum",
                min = 1, max = 10, value = 3, step = 1, ticks = FALSE),

    checkboxInput(ns("ranked_only"), "Ranked universe only", value = TRUE),

    tags$hr(),
    accordion(
      open = FALSE,
      accordion_panel(
        "Theme weights",
        p(class = "text-muted",
          tags$small("Weights apply to every per-stratum compute_peers call. ",
                     "Default is balanced (all = 1.0).")),
        div(class = "d-flex flex-wrap gap-1 mb-2",
            actionButton(ns("preset_balanced"),       "Balanced",
                         class = "btn btn-sm btn-outline-secondary"),
            actionButton(ns("preset_outcomes_heavy"), "Outcomes-heavy",
                         class = "btn btn-sm btn-outline-secondary"),
            actionButton(ns("preset_resources_heavy"),"Resources-heavy",
                         class = "btn btn-sm btn-outline-secondary"),
            actionButton(ns("preset_mission_similar"),"Mission-similar",
                         class = "btn btn-sm btn-outline-secondary")
        ),
        lapply(.THEMES, function(th) {
          # Athletics is opt-in (default 0); academic themes default to 1.
          dv <- if (exists(".theme_default_weight", envir = globalenv()))
                  .theme_default_weight(th)
                else if (th == "athletics") 0 else 1.0
          sliderInput(ns(paste0("weight_", th)),
                      label = stringr::str_to_title(th),
                      min = 0, max = 3, value = dv, step = 0.25,
                      ticks = FALSE)
        })
      ),
      accordion_panel(
        "Advanced",
        checkboxInput(ns("mahalanobis"),
                      "Use Mahalanobis distance instead of Euclidean",
                      value = FALSE)
      )
    ),

    tags$hr(),
    actionButton(ns("run_stratified"), "Run stratified search",
                 icon = icon("play"),
                 class = "btn btn-primary btn-lg w-100")
  )
}

stratifiedUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Stratified Peers"),
    p(class = "section-intro",
      "Run a separate peer search inside each value of a chosen ",
      "stratification dimension. Useful for seeing the closest peer in ",
      "each institutional category at once. Set the anchor and ",
      "stratification dimensions in the sidebar."),
    uiOutput(ns("stratified_view"))
  )
}

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
stratifiedServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Anchor picker ----
    anchor_choices_all <- {
      vals <- .SCHOOLS$unitid
      names(vals) <- sprintf("%s (%s)", .SCHOOLS$instnm, .SCHOOLS$stabbr)
      vals[order(names(vals))]
    }
    updateSelectizeInput(session, "anchor_strat",
                         choices  = anchor_choices_all,
                         selected = character(0),
                         server   = FALSE)

    # ---- Theme weight presets ----
    .THEME_PRESETS_LOCAL <- list(
      # Balanced: every academic theme at 1.0, athletics at 0 (opt-in).
      balanced = setNames(
                   lapply(.THEMES, function(th)
                            if (th == "athletics") 0 else 1.0),
                   .THEMES),
      outcomes_heavy = list(scale = 1, selectivity = 1, resources = 1,
                            finance = 1, outcomes = 2.5, aid = 1,
                            composition = 1, athletics = 0),
      resources_heavy = list(scale = 1, selectivity = 1, resources = 2,
                             finance = 1.5, outcomes = 1, aid = 1,
                             composition = 1, athletics = 0),
      mission_similar = list(scale = 1, selectivity = 1, resources = 1,
                             finance = 1, outcomes = 1, aid = 1,
                             composition = 2, athletics = 0)
    )
    apply_preset <- function(p) {
      v <- .THEME_PRESETS_LOCAL[[p]]
      for (th in names(v))
        updateSliderInput(session, paste0("weight_", th), value = v[[th]])
    }
    observeEvent(input$preset_balanced,        apply_preset("balanced"))
    observeEvent(input$preset_outcomes_heavy,  apply_preset("outcomes_heavy"))
    observeEvent(input$preset_resources_heavy, apply_preset("resources_heavy"))
    observeEvent(input$preset_mission_similar, apply_preset("mission_similar"))

    # -------------------------------------------------------------------------
    # Run the stratified search
    # -------------------------------------------------------------------------
    strata_result <- eventReactive(input$run_stratified, {
      anchor_uid <- suppressWarnings(as.integer(input$anchor_strat))
      req(!is.na(anchor_uid))

      dim_key  <- input$stratify_by
      dim      <- .STRATIFY_DIMS[[dim_key]]
      dim2_key <- input$stratify_by_2
      if (identical(dim2_key, "__none__") ||
          identical(dim2_key, dim_key)) {
        dim2_key <- NULL; dim2 <- NULL
      } else {
        dim2 <- .STRATIFY_DIMS[[dim2_key]]
      }
      k_per <- input$k_per

      # All page-local settings (no shared sidebar)
      theme_weights <- setNames(
        lapply(.THEMES, function(th) input[[paste0("weight_", th)]]),
        .THEMES)
      distance_metric <- if (isTRUE(input$mahalanobis))
                           "mahalanobis" else "euclidean"
      base_filter <- list(in_ranked_universe = isTRUE(input$ranked_only))

      # Build the list of {sv} or {sv, sv2} tuples to run.
      values1 <- dim$values()
      tuples <- if (is.null(dim2)) {
        lapply(values1, function(v) list(sv = v, sv2 = NULL, label_id = v))
      } else {
        values2 <- dim2$values()
        out <- list()
        for (v1 in values1) for (v2 in values2) {
          out[[length(out) + 1]] <- list(sv = v1, sv2 = v2,
                                          label_id = paste(v1, v2, sep = " | "))
        }
        out
      }

      n_total <- length(tuples)
      withProgress(message = "Running stratified search...",
                   value = 0, max = n_total, {
        results <- list()
        for (i in seq_along(tuples)) {
          tup <- tuples[[i]]
          # Build the composite filter
          sf <- .build_stratum_filter(base_filter, dim_key, tup$sv)
          if (!is.null(dim2_key))
            sf <- .build_stratum_filter(sf, dim2_key, tup$sv2)

          inc_detail <- if (is.null(dim2)) {
            sprintf("Stratum: %s", as.character(dim$labeler(tup$sv)))
          } else {
            sprintf("Stratum: %s x %s",
                    as.character(dim$labeler(tup$sv)),
                    as.character(dim2$labeler(tup$sv2)))
          }
          incProgress(1, detail = inc_detail)

          # Skip empties before calling compute_peers
          if (!.stratum_has_schools(base_filter, dim_key, tup$sv,
                                     dim2_key, tup$sv2))
            next
          if (identical(dim_key, "region") && !length(sf$stabbr)) next

          res <- tryCatch(
            compute_peers_cached(
              anchor_unitid   = anchor_uid,
              candidate_pool  = sf,
              theme_weights   = theme_weights,
              distance_metric = distance_metric,
              k               = k_per
            ),
            error = function(e) NULL
          )
          if (!is.null(res) && nrow(res$peers) > 0) {
            results[[tup$label_id]] <- list(
              sv = tup$sv, sv2 = tup$sv2, res = res
            )
          }
        }
        list(
          dim_key  = dim_key,
          dim      = dim,
          dim2_key = dim2_key,
          dim2     = dim2,
          k_per    = k_per,
          results  = results,
          anchor   = anchor_uid,
          run_at   = Sys.time(),
          base_filter = base_filter
        )
      })
    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # -------------------------------------------------------------------------
    # Per-stratum card. When this is the anchor's own stratum (matches on
    # both dims when interaction is active), add a badge and include the
    # anchor as a rank-0 row at the top of the table.
    # -------------------------------------------------------------------------
    stratum_card <- function(item, dim, dim2, anchor_strata1, anchor_strata2) {
      sv  <- item$sv
      sv2 <- item$sv2
      res <- item$res
      meta <- res$meta

      label1 <- as.character(dim$labeler(sv))
      label2 <- if (!is.null(dim2)) as.character(dim2$labeler(sv2)) else NULL
      full_label <- if (is.null(label2)) label1 else
        sprintf("%s   x   %s", label1, label2)

      # Is this the anchor's stratum?
      is_anchor_card <- (sv %in% anchor_strata1) &&
        (is.null(dim2) || (sv2 %in% anchor_strata2))

      # Description (only on the primary dim by default)
      desc <- .lookup_stratum_description(dim$column, sv)
      info_icon <- if (!is.na(desc) && nzchar(desc)) {
        tags$span(class = "stratum-info",
          title = desc,
          HTML("&#9432;")    # ⓘ
        )
      } else NULL

      med <- meta$pool_median_distance
      pool_dists <- meta$pool_distances
      df <- res$peers

      # Anchor row (rank 0) — inserted only on the anchor's card
      anchor_row_html <- NULL
      if (is_anchor_card) {
        anchor_meta <- .SCHOOLS[match(meta$anchor_unitid, .SCHOOLS$unitid), ,
                                drop = FALSE]
        anchor_row_html <- tags$tr(class = "anchor-row",
          tags$td(class = "sp-rank", HTML("&#9733;")),  # ★
          tags$td(class = "sp-school",
                  tags$strong(anchor_meta$instnm),
                  tags$small(class = "text-muted", "  (anchor)")),
          tags$td(class = "sp-state", anchor_meta$stabbr),
          tags$td(class = "sp-dist", "0.000"),
          tags$td(class = "sp-reldist", "0.00"),
          tags$td(class = "sp-pct", "100.0")
        )
      }

      # Peer rows
      rows <- lapply(seq_len(nrow(df)), function(i) {
        d   <- df$distance[i]
        rd  <- .compute_relative_distance(d, med)
        pct <- .compute_percentile_rank(d, pool_dists)
        tags$tr(
          tags$td(class = "sp-rank",   df$rank[i]),
          tags$td(class = "sp-school", df$instnm[i]),
          tags$td(class = "sp-state",  df$stabbr[i]),
          tags$td(class = "sp-dist",   sprintf("%.3f", d)),
          tags$td(class = "sp-reldist",
                  if (is.na(rd)) "(n/a)" else sprintf("%.2f", rd)),
          tags$td(class = "sp-pct",
                  if (is.na(pct)) "(n/a)" else sprintf("%.1f", pct))
        )
      })

      card_class <- if (is_anchor_card)
        "stratum-card stratum-card-anchor" else "stratum-card"

      tags$section(class = card_class,
        tags$div(class = "stratum-header",
          tags$div(class = "stratum-label", full_label, " ", info_icon,
                   if (is_anchor_card)
                     tags$span(class = "anchor-badge",
                               HTML("&#9733;"), " Anchor's category")),
          tags$div(class = "stratum-meta",
                   sprintf("Pool size: %s. ",
                           format(meta$candidate_pool_size, big.mark = ",")),
                   sprintf("Median pair distance in pool: %s",
                           if (is.na(med)) "(n/a)" else sprintf("%.3f", med)))
        ),
        tags$table(class = "stratum-table",
          tags$thead(tags$tr(
            tags$th("Rank"),
            tags$th("School"),
            tags$th("State"),
            tags$th(title = "Raw distance (pool-specific z-scores)", "Distance"),
            tags$th(title = "Distance / median pool-pair distance. Comparable across strata.", "Relative"),
            tags$th(title = "Where this pair sits in the pool's distance distribution. 99.5 = top 0.5% of similarity.", "Percentile")
          )),
          tags$tbody(anchor_row_html, rows)
        )
      )
    }

    # -------------------------------------------------------------------------
    # Main view
    # -------------------------------------------------------------------------
    output$stratified_view <- renderUI({
      sr <- strata_result()
      if (is.null(sr)) {
        return(div(class = "note-box",
                   tags$strong("No stratified search yet. "),
                   "Pick a stratification dimension above and click ",
                   tags$em("Run stratified search"), "."))
      }
      results <- sr$results
      if (!length(results)) {
        return(div(class = "note-box",
                   tags$strong("No strata with matching schools. "),
                   "The current sidebar filters may be too restrictive. ",
                   "Loosen them and try again, or untick ",
                   tags$em("Apply sidebar pool filters"), "."))
      }

      anchor_name <- .SCHOOLS$instnm[match(sr$anchor, .SCHOOLS$unitid)]
      ranked_label <- if (isTRUE(sr$base_filter$in_ranked_universe))
                         "ranked universe" else "full universe"
      dim_summary <- if (is.null(sr$dim2)) sr$dim$label
                     else sprintf("%s  x  %s", sr$dim$label, sr$dim2$label)

      summary_line <- p(class = "stratified-summary",
        tags$strong(sprintf("Anchor: %s  ", anchor_name)),
        tags$span(class = "ssc-sep", "|"),
        sprintf(" Stratified by: %s  ", dim_summary),
        tags$span(class = "ssc-sep", "|"),
        sprintf(" %d strata returned, top %d each  ",
                length(results), sr$k_per),
        tags$span(class = "ssc-sep", "|"),
        tags$small(class = "text-muted",
                   sprintf(" Universe: %s", ranked_label))
      )

      legend <- div(class = "stratified-legend",
        tags$small(class = "text-muted",
          tags$strong("Reading guide: "),
          tags$b("Distance"),
          " is the raw weighted-Euclidean distance against that stratum's pool. ",
          tags$b("Relative"),
          " is distance / median pool-pair distance; lower = closer relative to the pool. ",
          tags$b("Percentile"),
          " is where this pair sits in the pool's distance distribution; 99.5 means top 0.5% of similarity. ",
          "Relative and Percentile are comparable across strata; raw Distance is not. ",
          "Cards marked ", HTML("&#9733;"), " contain the anchor's own category and include the anchor as a rank-0 row."
        )
      )

      # Determine the anchor's strata for highlighting
      anchor_strata1 <- .anchor_stratum_value(sr$anchor, sr$dim_key)
      anchor_strata2 <- if (!is.null(sr$dim2_key))
                          .anchor_stratum_value(sr$anchor, sr$dim2_key)
                        else NULL

      cards <- lapply(results, function(item) {
        stratum_card(item, sr$dim, sr$dim2, anchor_strata1, anchor_strata2)
      })

      tagList(summary_line, legend, cards)
    })
  })
}
