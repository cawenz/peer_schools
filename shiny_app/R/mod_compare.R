# =============================================================================
# Side-by-Side comparison tab.
#
# This tab is decoupled from the Peer Search tab: a user can pick any two
# institutions and compare them, with or without a peer search behind it.
# When a search exists, the tab auto-syncs to it (anchor matches, clicked
# peer rows propagate here) and exposes a "limit peer choices to the
# current peer group" toggle for quick cycling within the search.
#
# Inputs:
#   peer_selection  reactive returning a 1-row tibble of the peer the user
#                   clicked on the Peer Search tab (or NULL if no click)
#   peer_result     reactive returning the full peer_result list (or NULL
#                   if no search has been run). Provides the precomputed
#                   distance to display when the picked pair matches the
#                   search, and the pool snapshot for distribution bars.
# =============================================================================

.COMPARE_THEME_ORDER <- c(
  "size", "selectivity", "resources", "finance",
  "outcomes", "aid", "student_body", "athletics"
)

# -----------------------------------------------------------------------------
# Institutional classifications shown at the top of the side-by-side.
# Each entry is: { label, fmt(row) -> display string }. The fmt function
# pulls whatever columns it needs from a single row of .SCHOOLS_WIDE and
# returns a human-readable string (or NA for missing).
#
# Order is roughly: external (US News) -> Carnegie (IC, SAEC, Research,
# Setting, APM) -> structural (sector, religious, region, locale).
# -----------------------------------------------------------------------------
.CLASSIFICATION_FIELDS <- list(
  list(label = "US News classification",
       fmt   = function(row) .prettify_classification(row$usnews_classification),
       match_key = function(row) row$usnews_classification),
  list(label = "Carnegie Institutional Classification (2025)",
       fmt   = function(row) row$ic2025_label,
       match_key = function(row) row$ic2025_label),
  list(label = "Carnegie Access & Earnings (SAEC 2025)",
       fmt   = function(row) row$saec2025_label,
       match_key = function(row) row$saec2025_label),
  list(label = "Carnegie Research Activity (2025)",
       fmt   = function(row) row$research2025_label,
       match_key = function(row) row$research2025_label),
  list(label = "Carnegie Setting / Residential (2025)",
       fmt   = function(row) row$setting2025_label,
       match_key = function(row) row$setting2025_label),
  list(label = "Carnegie Highest Degree (2025)",
       fmt   = function(row) row$highest_degree_2025_label,
       match_key = function(row) row$highest_degree_2025_label),
  list(label = "Carnegie Basic (2021)",
       fmt   = function(row) row$basic2021_label,
       match_key = function(row) row$basic2021_label),
  list(label = "Carnegie Size (2025)",
       fmt   = function(row) row$ic2025size_label,
       match_key = function(row) row$ic2025size_label),
  list(label = "Carnegie Academic Program Mix",
       fmt   = function(row) {
         lbl <- row$apm_label
         if (is.na(lbl) || !nzchar(lbl)) return(NA_character_)
         dom <- row$apm_max_cip2_name
         pct <- row$apm_max_cip2percent
         if (!is.na(dom) && !is.na(pct)) {
           dom <- sub("\\.$", "", dom)
           dom <- stringr::str_to_title(tolower(dom))
           lbl <- sprintf("%s  (largest CIP: %s, %.0f%%)",
                          lbl, dom, 100 * as.numeric(pct))
         }
         lbl
       },
       # Match on the APM category only — different dominant-CIP %s
       # shouldn't break a match between two SF Arts and Sciences schools.
       match_key = function(row) row$apm_label),
  list(label = "Sector / control",
       fmt   = function(row) .prettify_control(row$control_grp),
       match_key = function(row) row$control_grp),
  list(label = "Religious tradition / affiliation",
       fmt   = function(row) {
         tr <- row$religious_tradition
         aff <- row$religious_affiliation
         if (is.na(tr) || !nzchar(tr)) return("(none)")
         if (!is.na(aff) && nzchar(aff) && aff != tr)
           sprintf("%s  (%s)", tr, aff) else tr
       },
       # Match on the broad tradition (Catholic = Catholic regardless of
       # specific affiliation differences).
       match_key = function(row) row$religious_tradition),
  list(label = "Geographic region",
       fmt   = function(row) {
         st <- row$stabbr
         if (is.na(st)) return(NA_character_)
         keys <- names(.REGIONS)[
           vapply(.REGIONS, function(s) st %in% s, logical(1))
         ]
         if (!length(keys))
           return(sprintf("%s (outside defined regions)", st))
         paste(.REGION_LABELS[keys], collapse = " · ")
       },
       # Region match uses set overlap: "Northeast + New England" and
       # "Northeast + Mid-Atlantic" share Northeast, count as a match.
       match_key = function(row) {
         st <- row$stabbr
         if (is.na(st)) return(character(0))
         names(.REGIONS)[
           vapply(.REGIONS, function(s) st %in% s, logical(1))
         ]
       }),
  list(label = "Locale (Carnegie / IPEDS)",
       fmt   = function(row) {
         if (!"locale_label" %in% names(row)) return(NA_character_)
         row$locale_label
       },
       # Match on the broad locale category (City / Suburb / Town / Rural),
       # ignoring the size sub-classification. Two Massachusetts cities of
       # different size still count as the same locale type.
       match_key = function(row) {
         if (!"locale_label" %in% names(row)) return(NA_character_)
         loc <- row$locale_label
         if (is.null(loc) || length(loc) != 1 || is.na(loc) || !nzchar(loc))
           return(NA_character_)
         sub(":.*$", "", loc)
       }),
  # ---- EADA athletics classifications ----
  # Three rows, ordered most-to-least likely to register a match. Body
  # (NCAA vs NAIA) matches frequently; division matches often within a
  # sponsoring body; conference matches only for true conference rivals.
  list(label = "Athletics sponsoring body",
       fmt   = function(row) {
         if (!"athletics_body" %in% names(row)) return(NA_character_)
         b <- row$athletics_body
         if (is.null(b) || length(b) != 1 || is.na(b) || !nzchar(b))
           return(NA_character_)
         b
       },
       match_key = function(row) {
         if (!"athletics_body" %in% names(row)) return(NA_character_)
         row$athletics_body
       }),
  list(label = "Athletics division",
       fmt   = function(row) {
         if (!"athletics_division" %in% names(row)) return(NA_character_)
         d <- row$athletics_division
         if (is.null(d) || length(d) != 1 || is.na(d) || !nzchar(d))
           return(NA_character_)
         # Pretty-print: "D1" -> "Division I", "NAIA" passes through.
         switch(as.character(d),
                D1 = "NCAA Division I",
                D2 = "NCAA Division II",
                D3 = "NCAA Division III",
                NAIA = "NAIA",
                d)
       },
       match_key = function(row) {
         if (!"athletics_division" %in% names(row)) return(NA_character_)
         row$athletics_division
       }),
  list(label = "Athletics conference",
       fmt   = function(row) {
         if (!"athletics_conference" %in% names(row)) return(NA_character_)
         c <- row$athletics_conference
         if (is.null(c) || length(c) != 1 || is.na(c) || !nzchar(c))
           return(NA_character_)
         c
       },
       match_key = function(row) {
         if (!"athletics_conference" %in% names(row)) return(NA_character_)
         row$athletics_conference
       })
)
.COMPARE_THEME_LABELS <- c(
  size         = "Size",
  selectivity  = "Selectivity",
  resources    = "Resources",
  finance      = "Finance",
  outcomes     = "Outcomes",
  aid          = "Aid",
  student_body = "Student body",
  athletics    = "Athletics",
  descriptive  = "Descriptive"
)

compareSidebarUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Comparison"),
    tags$div(class = "text-muted small",
             "Pick any two institutions. ",
             "A peer search on the ",
             tags$em("Peer Search"), " page is not required."),
    tags$hr(),

    selectizeInput(ns("anchor_compare"),
                   label   = "Anchor school",
                   choices = NULL, multiple = FALSE,
                   options = list(placeholder = "Type to search",
                                   maxOptions  = 50)),
    selectizeInput(ns("peer_compare"),
                   label   = "Peer",
                   choices = NULL, multiple = FALSE,
                   options = list(placeholder = "Type to search",
                                   maxOptions  = 50)),

    checkboxInput(ns("limit_to_peer_group"),
                  "Limit peer choices to current Peer Search results",
                  value = TRUE),
    helpText(tags$small(class = "text-muted",
      "When checked, the peer dropdown is restricted to anchor + ",
      "the peers returned by the most recent Peer Search. Uncheck to ",
      "pick any institution.")
    )
  )
}

compareUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Side-by-Side"),
    p(class = "section-intro",
      "Compare any two institutions across all variables. Click a row on the ",
      tags$em("Peer Search"), " page to load that institution here, or pick ",
      "any pair using the sidebar controls. When a peer search exists and ",
      "the picked pair matches it, the distance and rank shown reflect that ",
      "search; otherwise the comparison is ad hoc."),
    uiOutput(ns("compare_view"))
  )
}

compareServer <- function(id, peer_selection, peer_result) {
  moduleServer(id, function(input, output, session) {

    # -------------------------------------------------------------------------
    # Selectize initialization
    # Anchor picker covers all ~2,598 institutions; peer picker is either
    # the same set or restricted to the current peer group depending on
    # the toggle.
    # -------------------------------------------------------------------------
    # Reuse the global .ANCHOR_CHOICES (built once at app startup).
    anchor_choices_all <- .ANCHOR_CHOICES

    updateSelectizeInput(session, "anchor_compare",
                         choices  = anchor_choices_all,
                         selected = .DEFAULT_ANCHOR_UNITID,
                         server   = TRUE)
    updateSelectizeInput(session, "peer_compare",
                         choices  = anchor_choices_all,
                         selected = character(0),
                         server   = TRUE)

    # -------------------------------------------------------------------------
    # Peer choices react to the toggle and to peer_result changes.
    # When the toggle is on AND a search exists, peer choices = anchor +
    # search results. Otherwise, peer choices = all institutions.
    # The anchor picker is never restricted; the user can pick any anchor
    # regardless of what's in the current peer group.
    # -------------------------------------------------------------------------
    peer_choices <- reactive({
      res <- peer_result()
      if (isTRUE(input$limit_to_peer_group) && !is.null(res)) {
        uids <- c(res$meta$anchor_unitid, res$peers$unitid)
        uids <- intersect(uids, .SCHOOLS$unitid)
        if (!length(uids)) return(anchor_choices_all)
        rows <- .SCHOOLS[match(uids, .SCHOOLS$unitid), , drop = FALSE]
        vals <- rows$unitid
        names(vals) <- sprintf("%s (%s)", rows$instnm, rows$stabbr)
        vals
      } else {
        anchor_choices_all
      }
    })

    observe({
      # Update the peer picker's choice list whenever peer_choices changes.
      # Preserve the current selection if it survives the new list, so a
      # restricted-pool toggle doesn't blow away a valid pick.
      ch <- peer_choices()
      cur <- isolate(input$peer_compare)
      sel <- if (length(cur) && cur %in% as.character(ch)) cur else character(0)
      # server = TRUE: peer choices can include the full ranked
       # universe (~1,500 schools) when no peer search is loaded.
       # Paging via the server keeps initial-load cheap.
      updateSelectizeInput(session, "peer_compare",
                           choices = ch, selected = sel, server = TRUE)
    })

    # When a new search lands, sync the anchor picker to that search's anchor
    # so the user lands in a sensible default state.
    observeEvent(peer_result(), {
      res <- peer_result()
      if (!is.null(res)) {
        updateSelectizeInput(session, "anchor_compare",
                             selected = res$meta$anchor_unitid)
      }
    }, ignoreNULL = TRUE)

    # When the user clicks a row in the Peer Search tab, mirror that
    # selection into the peer picker.
    observeEvent(peer_selection(), {
      sel <- peer_selection()
      if (!is.null(sel) && nrow(sel))
        updateSelectizeInput(session, "peer_compare", selected = sel$unitid[1])
    }, ignoreNULL = TRUE)

    # -------------------------------------------------------------------------
    # Resolved current selections (unitids)
    # -------------------------------------------------------------------------
    anchor_uid <- reactive({
      uid <- suppressWarnings(as.integer(input$anchor_compare))
      if (length(uid) != 1 || is.na(uid)) return(NULL)
      uid
    })
    peer_uid <- reactive({
      uid <- suppressWarnings(as.integer(input$peer_compare))
      if (length(uid) != 1 || is.na(uid)) return(NULL)
      uid
    })

    anchor_row <- reactive({
      uid <- anchor_uid()
      if (is.null(uid)) return(NULL)
      r <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid == uid, , drop = FALSE]
      if (nrow(r)) r else NULL
    })
    peer_row <- reactive({
      uid <- peer_uid()
      if (is.null(uid)) return(NULL)
      r <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid == uid, , drop = FALSE]
      if (nrow(r)) r else NULL
    })

    # -------------------------------------------------------------------------
    # Pool slice for distribution bars.
    # If the picked pair matches a peer search, use that search's pool.
    # Otherwise fall back to the ranked universe so bars still render.
    # -------------------------------------------------------------------------
    pool_slice <- reactive({
      res <- peer_result()
      if (!is.null(res) && !is.null(res$pool_unitids))
        .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid %in% res$pool_unitids, , drop = FALSE]
      else
        .SCHOOLS_WIDE[.SCHOOLS_WIDE$in_ranked_universe %in% TRUE, , drop = FALSE]
    })

    # -------------------------------------------------------------------------
    # Distance/rank info. Returns NULL unless the picked pair actually
    # matches a row in the most recent peer search (same anchor, peer in
    # the result set).
    # -------------------------------------------------------------------------
    distance_info <- reactive({
      res <- peer_result()
      a   <- anchor_uid()
      p   <- peer_uid()
      if (is.null(res) || is.null(a) || is.null(p)) return(NULL)
      if (a != res$meta$anchor_unitid) return(NULL)
      match_row <- res$peers[res$peers$unitid == p, , drop = FALSE]
      if (!nrow(match_row)) return(NULL)
      list(
        distance = match_row$distance[1],
        rank     = match_row$rank[1],
        total    = nrow(res$peers),
        metric   = res$meta$distance_metric
      )
    })

    # -------------------------------------------------------------------------
    # Variable catalog (independent of peer_result so the side-by-side
    # works without a search)
    # -------------------------------------------------------------------------
    variable_catalog <- reactive({
      available <- intersect(.VARIABLES$metric, colnames(.WIDE_ALL))
      meta <- .VARIABLES[match(available, .VARIABLES$metric), , drop = FALSE]
      themes <- vapply(available, .var_theme, character(1))
      themes[is.na(themes)] <- "descriptive"
      data.frame(
        metric       = available,
        display_name = ifelse(is.na(meta$display_name),
                              available, meta$display_name),
        theme        = themes,
        format       = meta$format,
        use_type     = meta$use_type,
        stringsAsFactors = FALSE
      )
    })

    # -------------------------------------------------------------------------
    # Header card builder
    # -------------------------------------------------------------------------
    header_card <- function(a_row, p_row, dist) {
      # School block is just the institution name now. Full classification
      # detail lives in the "Institutional classifications & groupings"
      # section directly below the header.
      school_block <- function(row) {
        tagList(
          tags$div(class = "compare-school-name", row$instnm)
        )
      }

      center_block <- if (!is.null(dist)) {
        metric_label <- switch(
          dist$metric,
          euclidean   = "weighted Euclidean distance",
          mahalanobis = "weighted Mahalanobis distance",
          dist$metric
        )
        tagList(
          tags$div(class = "compare-distance-value",
                   sprintf("%.3f", dist$distance)),
          tags$div(class = "compare-distance-label", metric_label),
          tags$div(class = "compare-rank-label",
                   sprintf("Rank %d of %d peers in the current search",
                           dist$rank, dist$total))
        )
      } else {
        tagList(
          tags$div(class = "compare-distance-value compare-distance-na", "—"),
          tags$div(class = "compare-distance-label",
                   "Ad hoc comparison"),
          tags$div(class = "compare-rank-label",
                   tags$small(class = "text-muted",
                              "No precomputed distance: this pair is ",
                              "not the anchor + a peer from the current ",
                              "search."))
        )
      }

      div(class = "compare-header",
          div(class = "compare-anchor",
              tags$div(class = "compare-role", "Anchor"),
              school_block(a_row)),
          div(class = "compare-distance", center_block),
          div(class = "compare-peer",
              tags$div(class = "compare-role", "Peer"),
              school_block(p_row))
      )
    }

    # -------------------------------------------------------------------------
    # Classifications & groupings section. Built once per render from
    # .CLASSIFICATION_FIELDS; shows a ✓ on rows where anchor and peer share
    # the same value.
    # -------------------------------------------------------------------------
    classification_section <- function(a_row, p_row) {
      # Helper: does a key vector contain any real (non-NA, non-empty) value?
      has_real <- function(x) {
        if (is.null(x) || !length(x)) return(FALSE)
        any(!is.na(x) & nzchar(as.character(x)))
      }

      # First pass: compute match flags so the section header can summarize
      # them. Then build the row HTML using the precomputed flags.
      match_flags <- vapply(.CLASSIFICATION_FIELDS, function(f) {
        a_key <- if (is.function(f$match_key)) f$match_key(a_row)
                 else tryCatch(f$fmt(a_row), error = function(e) NA_character_)
        p_key <- if (is.function(f$match_key)) f$match_key(p_row)
                 else tryCatch(f$fmt(p_row), error = function(e) NA_character_)
        has_real(a_key) && has_real(p_key) &&
          length(intersect(as.character(a_key),
                            as.character(p_key))) > 0
      }, logical(1))

      n_match <- sum(match_flags)
      n_total <- length(match_flags)

      rows <- lapply(seq_along(.CLASSIFICATION_FIELDS), function(i) {
        f <- .CLASSIFICATION_FIELDS[[i]]
        a_val <- tryCatch(f$fmt(a_row), error = function(e) NA_character_)
        p_val <- tryCatch(f$fmt(p_row), error = function(e) NA_character_)
        is_match <- match_flags[i]

        tags$tr(
          class = if (is_match) "classification-row match"
                  else "classification-row",
          tags$td(class = "cf-label", f$label),
          tags$td(class = "cf-value cf-anchor",
                  if (is.na(a_val) || !nzchar(a_val)) "(n/a)" else a_val),
          tags$td(class = "cf-value cf-peer",
                  if (is.na(p_val) || !nzchar(p_val)) "(n/a)" else p_val),
          tags$td(class = "cf-match",
                  if (is_match) HTML("&#10004;") else "")
        )
      })

      # Color the match-count tag based on coverage, so the eye gets a
      # quick read: high overlap (>=75%) green, moderate (>=50%) brand
      # purple, low (<50%) muted taupe.
      pct_match <- n_match / n_total
      tag_class <- if (pct_match >= 0.75) "ccount-tag ccount-high"
                   else if (pct_match >= 0.5) "ccount-tag ccount-mid"
                   else "ccount-tag ccount-low"

      tags$section(class = "classification-section",
        tags$h5(
          "Institutional classifications & groupings",
          tags$span(class = tag_class,
                    sprintf("%d of %d match", n_match, n_total))
        ),
        p(class = "text-muted",
          tags$small(
            "Categorical classifications from IPEDS, US News, and the ",
            "Carnegie 2025 release. ", tags$strong(HTML("&#10004;")),
            " marks rows where the two institutions share the same value."
          )),
        tags$table(class = "classification-table",
          tags$thead(
            tags$tr(
              tags$th("Classification"),
              tags$th("Anchor"),
              tags$th("Peer"),
              tags$th(class = "th-match", "Match")
            )
          ),
          tags$tbody(rows)
        )
      )
    }

    # -------------------------------------------------------------------------
    # Per-variable row + theme section
    # -------------------------------------------------------------------------
    inspect_link <- function(metric) {
      # Click sends {metric: ..., t: timestamp} to inspect_metric. The
      # timestamp ensures clicking the same row twice still fires the
      # observer.
      js <- sprintf(
        "Shiny.setInputValue('%s', {metric: '%s', t: Date.now()}, {priority: 'event'}); return false;",
        session$ns("inspect_metric"), metric
      )
      tags$a(href = "#", class = "inspect-icon",
             title = "Show full pool distribution for this variable",
             onclick = js,
             HTML("&#x1F4CA;"))   # 📊
    }

    var_row <- function(metric, display_name, fmt, use_type, years_label,
                        a_row, p_row, pool_vals) {
      a_val <- a_row[[metric]]
      p_val <- p_row[[metric]]
      tags$tr(
        class = if (identical(use_type, "clustering"))
          "compare-row clustering-var" else "compare-row",
        tags$td(class = "var-name", display_name),
        tags$td(class = "var-years", years_label %||% "(unknown)"),
        tags$td(class = "var-value var-anchor",
                .format_value(a_val, fmt)),
        tags$td(class = "var-value var-peer",
                .format_value(p_val, fmt)),
        tags$td(class = "var-diff",
                .format_diff(p_val, a_val, fmt)),
        tags$td(class = "var-dist",
                .compare_distribution_svg(pool_vals, a_val, p_val, fmt = fmt)),
        tags$td(class = "var-inspect", inspect_link(metric))
      )
    }

    theme_section <- function(theme_key, vars_df, a_row, p_row, pool_df) {
      if (nrow(vars_df) == 0) return(NULL)
      header <- .COMPARE_THEME_LABELS[theme_key]
      if (is.na(header)) header <- stringr::str_to_title(theme_key)

      rows <- lapply(seq_len(nrow(vars_df)), function(i) {
        v <- vars_df[i, ]
        years_label <- .VAR_YEARS_LABEL[v$metric]
        var_row(v$metric, v$display_name, v$format, v$use_type, years_label,
                a_row, p_row, pool_df[[v$metric]])
      })

      tags$section(class = "compare-section",
        tags$h5(header,
                tags$small(class = "compare-section-count",
                           sprintf(" (%d variables)", nrow(vars_df)))),
        tags$table(class = "compare-table",
          tags$thead(
            tags$tr(
              tags$th("Variable"),
              tags$th(class = "th-years", "Years"),
              tags$th(class = "th-value", "Anchor"),
              tags$th(class = "th-value", "Peer"),
              tags$th(class = "th-value", "Difference"),
              tags$th(class = "th-dist", "Pool position"),
              tags$th(class = "th-inspect", "")
            )
          ),
          tags$tbody(rows)
        )
      )
    }

    # -------------------------------------------------------------------------
    # Click-to-expand: distribution modal
    # -------------------------------------------------------------------------
    inspected_metric <- reactiveVal(NULL)

    observeEvent(input$inspect_metric, {
      payload <- input$inspect_metric
      metric  <- if (is.list(payload)) payload$metric else payload
      if (is.null(metric) || !is.character(metric) || metric == "") return()
      inspected_metric(metric)

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      display_name <- if (nrow(meta_row) && !is.na(meta_row$display_name))
                        meta_row$display_name else metric
      years_label <- .VAR_YEARS_LABEL[metric] %||% "(unknown)"

      # --- Definition block: source label, computed flag, format, plus the
      # variable's notes/coverage_note as a description. Same vocabulary as
      # the cohort dashboard card modal so the app reads consistently. ---
      .source_lbl_map <- c(
        ipeds          = "IPEDS",
        ipeds_derived  = "IPEDS",
        ccihe          = "Carnegie 2025 Data File",
        cds_ai         = "Common Data Set",
        cds_ai_derived = "Common Data Set",
        scorecard      = "College Scorecard",
        eada           = "EADA",
        eada_derived   = "EADA"
      )
      .derived_sources <- c("ipeds_derived", "cds_ai_derived",
                             "ccihe", "eada_derived")

      def_chips <- tagList()
      def_desc  <- NULL
      if (nrow(meta_row)) {
        src    <- meta_row$source
        src_lbl <- if (!is.na(src) && nzchar(src))
                     (.source_lbl_map[[src]] %||% src) else "Unknown source"
        is_derived <- !is.na(src) && src %in% .derived_sources

        def_chips <- tagList(
          tags$span(class = "dash-modal-chip",
                    tags$strong("Source: "), src_lbl),
          if (!is.na(meta_row$category))
            tags$span(class = "dash-modal-chip",
                      tags$strong("Category: "), meta_row$category),
          if (!is.na(meta_row$format))
            tags$span(class = "dash-modal-chip",
                      tags$strong("Format: "), meta_row$format),
          tags$span(class = "dash-modal-chip",
                    tags$strong("Years: "), years_label),
          if (is_derived)
            tags$span(class = "dash-modal-chip dash-modal-chip-computed",
                      title = "Derived from one or more raw inputs.",
                      "Computed")
        )

        def_desc <- if (!is.na(meta_row$notes) && nzchar(meta_row$notes))
                      meta_row$notes
                    else if (!is.na(meta_row$coverage_note) &&
                              nzchar(meta_row$coverage_note))
                      meta_row$coverage_note
                    else NULL
      }

      showModal(modalDialog(
        title = tagList(
          tags$div(display_name),
          tags$div(class = "modal-subtitle",
                   tags$small(sprintf("Aggregation: %s", years_label)))
        ),
        size = "l",
        easyClose = TRUE,
        fade = TRUE,
        footer = modalButton("Close"),
        div(class = "distribution-modal-body",
            # Definition first — answers "what am I looking at" before the
            # chart shows where the schools sit.
            tags$div(class = "dash-modal-chips", def_chips),
            if (!is.null(def_desc))
              tags$p(class = "dash-modal-desc", def_desc),
            uiOutput(session$ns("pool_description")),
            checkboxInput(session$ns("modal_show_peers"),
                          "Overlay other peers from the current search",
                          value = TRUE),
            plotlyOutput(session$ns("distribution_plot"), height = "420px"),
            uiOutput(session$ns("distribution_stats"))
        )
      ))
    })

    # ---- Pool description shown above the chart ----
    output$pool_description <- renderUI({
      metric <- inspected_metric()
      req(metric)
      pool_df <- pool_slice()
      n <- nrow(pool_df)
      res <- peer_result()

      filter_label <- if (!is.null(res) && !is.null(res$pool_filter))
                        .describe_pool_filter(res$pool_filter)
                      else "Ranked universe (no search has been run)"

      tags$div(class = "pool-description",
               tags$strong("Pool: "),
               sprintf("%s institutions ", format(n, big.mark = ",")),
               tags$em(sprintf("(%s)", filter_label)))
    })

    # ---- Interactive chart via Plotly ----
    output$distribution_plot <- renderPlotly({
      metric <- inspected_metric()
      req(metric)

      pool_df <- pool_slice()
      pool_vals <- pool_df[[metric]]
      pool_vals <- pool_vals[is.finite(pool_vals)]
      validate(need(length(pool_vals) >= 5,
                    "Not enough pool values to plot a distribution."))

      a_row <- anchor_row(); p_row <- peer_row()
      a_val <- if (!is.null(a_row)) a_row[[metric]] else NA_real_
      p_val <- if (!is.null(p_row)) p_row[[metric]] else NA_real_

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA
      x_label <- if (nrow(meta_row) && !is.na(meta_row$display_name))
                   meta_row$display_name else metric
      anchor_name <- if (!is.null(a_row)) a_row$instnm else "Anchor"
      peer_name   <- if (!is.null(p_row)) p_row$instnm else "Peer"

      # Freedman-Diaconis binwidth, floored by data range
      iqr <- diff(stats::quantile(pool_vals, c(0.25, 0.75),
                                  na.rm = TRUE, names = FALSE))
      bw  <- max(2 * iqr / length(pool_vals)^(1/3),
                 diff(range(pool_vals)) / 40)

      # Density rescaled to count axis so it overlays cleanly on the bars
      dens <- stats::density(pool_vals)
      dens_y_count <- dens$y * length(pool_vals) * bw

      # Plotly hover format placeholder depends on whether it's a percentage
      # variable, so the rendered tooltips read naturally for currency
      # vs counts vs rates.
      x_hover_fmt <- switch(
        as.character(fmt) %||% "",
        currency   = "$%{x:,.0f}",
        # NB: plotly hovertemplate treats bare `%` as literal unless
        # followed by `{`. Escaping with `%%` would render two literal
        # percent signs in the tooltip (the historical d3-style escape
        # does not apply here). One `%` is correct.
        percentage = "%{x:.1f}%",
        count      = "%{x:,.0f}",
        ratio      = "%{x:.2f}",
        "%{x:.4g}"
      )

      p <- plot_ly() %>%
        add_histogram(
          x    = pool_vals,
          name = "Pool distribution",
          xbins = list(start = min(pool_vals),
                       end   = max(pool_vals) + bw,
                       size  = bw),
          marker = list(color = "#F4EDEC",
                        line  = list(color = "#AC9E94", width = 0.5)),
          hovertemplate = paste0(
            "<b>Pool bin</b><br>Around ", x_hover_fmt,
            ": %{y} institutions<extra></extra>")
        ) %>%
        add_lines(
          x = dens$x, y = dens_y_count,
          name = "Density estimate",
          line = list(color = "#251230", width = 2),
          hovertemplate = paste0("Density at ", x_hover_fmt,
                                  "<extra></extra>")
        )

      # Other peers as a scatter rug at y = 0
      res <- peer_result()
      if (isTRUE(input$modal_show_peers) && !is.null(res)) {
        anchor_uid <- if (!is.null(a_row)) a_row$unitid else NA
        peer_uid_v <- if (!is.null(p_row)) p_row$unitid else NA
        peer_uids  <- setdiff(res$peers$unitid, c(anchor_uid, peer_uid_v))
        ix <- which(pool_df$unitid %in% peer_uids &
                    is.finite(pool_df[[metric]]))
        if (length(ix)) {
          p <- p %>% add_markers(
            x = pool_df[[metric]][ix],
            y = rep(0, length(ix)),
            name = "Other peers in current search",
            text = pool_df$instnm[ix],
            marker = list(symbol = "diamond", size = 9, color = "#251230",
                          line = list(color = "#FFFFFF", width = 1)),
            hovertemplate = paste0("<b>%{text}</b><br>", x_label,
                                    ": ", x_hover_fmt, "<extra></extra>")
          )
        }
      }

      # Anchor and peer vertical lines + labeled chips above the chart
      shapes <- list(); annots <- list()
      if (is.finite(a_val)) {
        shapes <- c(shapes, list(list(
          type = "line", xref = "x", yref = "paper",
          x0 = a_val, x1 = a_val, y0 = 0, y1 = 1,
          line = list(color = "#602D89", width = 2.5)
        )))
        annots <- c(annots, list(list(
          x = a_val, y = 1, xref = "x", yref = "paper",
          yanchor = "bottom", xanchor = "left",
          text = sprintf("<b>Anchor: %s (%s)</b>",
                          anchor_name, .format_value(a_val, fmt)),
          showarrow = FALSE,
          bgcolor = "#602D89", bordercolor = "#602D89",
          font = list(color = "#FFFFFF", size = 11),
          xshift = 4, yshift = 2
        )))
      }
      if (is.finite(p_val)) {
        shapes <- c(shapes, list(list(
          type = "line", xref = "x", yref = "paper",
          x0 = p_val, x1 = p_val, y0 = 0, y1 = 1,
          line = list(color = "#AC9E94", width = 2.5, dash = "dash")
        )))
        annots <- c(annots, list(list(
          x = p_val, y = 1, xref = "x", yref = "paper",
          yanchor = "bottom", xanchor = "left",
          text = sprintf("<b>Peer: %s (%s)</b>",
                          peer_name, .format_value(p_val, fmt)),
          showarrow = FALSE,
          bgcolor = "#AC9E94", bordercolor = "#AC9E94",
          font = list(color = "#FFFFFF", size = 11),
          xshift = 4, yshift = 22   # nudged down so it sits below the anchor chip
        )))
      }

      p %>%
        layout(
          # No chart title — the modal's header already shows the variable name.
          xaxis  = list(title = x_label, gridcolor = "#F4EDEC",
                        zeroline = FALSE),
          yaxis  = list(title = "Number of institutions",
                        gridcolor = "#F4EDEC"),
          shapes = shapes,
          annotations = annots
        ) %>%
        cohc_plotly_theme(hovermode = "closest") %>%
        cohc_modebar(filename_root = "side_by_side_distribution")
    })

    output$distribution_stats <- renderUI({
      metric <- inspected_metric()
      req(metric)

      pool_df <- pool_slice()
      pool_vals <- pool_df[[metric]]
      pool_vals <- pool_vals[is.finite(pool_vals)]
      req(length(pool_vals) >= 5)

      a_row <- anchor_row(); p_row <- peer_row()
      a_val <- if (!is.null(a_row)) a_row[[metric]] else NA_real_
      p_val <- if (!is.null(p_row)) p_row[[metric]] else NA_real_

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA

      qs <- stats::quantile(pool_vals, c(0, 0.25, 0.5, 0.75, 1),
                            na.rm = TRUE, names = FALSE)
      pct <- function(v) {
        if (is.null(v) || length(v) != 1 || !is.finite(v))
          return("(n/a)")
        sprintf("%.0fth", 100 * mean(pool_vals < v))
      }

      tags$dl(class = "distribution-stats",
        tags$dt("Pool size"),      tags$dd(format(length(pool_vals), big.mark = ",")),
        tags$dt("Pool min"),       tags$dd(.format_value(qs[1], fmt)),
        tags$dt("Q1"),             tags$dd(.format_value(qs[2], fmt)),
        tags$dt("Median"),         tags$dd(.format_value(qs[3], fmt)),
        tags$dt("Q3"),             tags$dd(.format_value(qs[4], fmt)),
        tags$dt("Pool max"),       tags$dd(.format_value(qs[5], fmt)),
        tags$dt("Anchor"),
        tags$dd(sprintf("%s  (%s percentile)",
                        .format_value(a_val, fmt), pct(a_val))),
        tags$dt("Peer"),
        tags$dd(sprintf("%s  (%s percentile)",
                        .format_value(p_val, fmt), pct(p_val)))
      )
    })

    # -------------------------------------------------------------------------
    # Main view assembly
    # -------------------------------------------------------------------------
    output$compare_view <- renderUI({
      a_row <- anchor_row()
      p_row <- peer_row()

      # Empty / invalid states
      if (is.null(a_row)) {
        return(div(class = "note-box",
                   "Pick an anchor institution in the sidebar."))
      }
      if (is.null(p_row)) {
        return(div(class = "note-box",
                   "Pick a peer institution in the sidebar to compare against ",
                   tags$strong(a_row$instnm), "."))
      }
      if (identical(a_row$unitid, p_row$unitid)) {
        return(div(class = "note-box",
                   "Anchor and peer are the same institution. ",
                   "Pick a different peer."))
      }

      tryCatch({
        cat_df  <- variable_catalog()
        pool_df <- pool_slice()
        dist    <- distance_info()

        theme_order <- c(.COMPARE_THEME_ORDER, "descriptive")
        sections <- lapply(theme_order, function(th) {
          vars_df <- cat_df[cat_df$theme == th, , drop = FALSE]
          if (!nrow(vars_df)) return(NULL)
          vars_df <- vars_df[order(vars_df$use_type != "clustering",
                                   vars_df$display_name), ]
          theme_section(th, vars_df, a_row, p_row, pool_df)
        })

        legend <- tags$div(class = "compare-legend",
          tags$span(class = "legend-dot legend-anchor"), " Anchor",
          tags$span(class = "legend-spacer"),
          tags$span(class = "legend-dot legend-peer"), " Peer",
          tags$span(class = "legend-spacer"),
          tags$small(class = "text-muted",
            if (!is.null(peer_result()))
              "Pool position bars cover the 5th to 95th percentile range of the current search's candidate pool."
            else
              "Pool position bars cover the 5th to 95th percentile range of the ranked universe (no search has been run)."))

        tagList(
          header_card(a_row, p_row, dist),
          legend,
          classification_section(a_row, p_row),
          sections
        )
      }, error = function(e) {
        # Surface unexpected errors as a visible message instead of
        # silently returning NULL (which makes the page look blank).
        message(sprintf("[compare] render error: %s", conditionMessage(e)))
        div(class = "note-box",
            tags$strong("Comparison render error: "),
            conditionMessage(e),
            tags$br(),
            tags$small(class = "text-muted",
              "The R console has a more detailed message."))
      })
    })
  })
}
