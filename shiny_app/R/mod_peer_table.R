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
    # Tagline only — full onboarding lives in the empty-state hero
    # rendered by header_or_empty so the explanation is right where
    # the user's eye is once they're ready to read.
    p(class = "section-intro",
      "Rank institutions by similarity to an anchor school across IPEDS, ",
      "US News, Carnegie, EADA, and Scorecard data."),

    uiOutput(ns("header_or_empty")),
    uiOutput(ns("analysis_indicator")),

    # Results section with a clear label above the table so the table reads
    # as the primary result, not as something nested inside another widget.
    uiOutput(ns("results_header")),
    div(class = "peer-results-table",
        DT::DTOutput(ns("peer_table"))),

    # ---- Analytical surfaces tab strip ----
    # Below the table, every analytical lens on the peer set lives in
    # its own tab so users see all six options at once and can switch
    # between them with one click. The legacy inline sections
    # (Aspirant refine, Stratified expand, Diagnostics) are surfaced
    # via uiOutput from the same renderUI bindings as before — only
    # the wrapping container changes. Three new tabs scaffold the
    # cohort-style lenses (Composition / Map / Dashboard) added in
    # subsequent phases. Whole strip only renders once a search exists.
    uiOutput(ns("analysis_tabs"))
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
        # Empty-state hero — substantial first-run guide. Disappears
        # once the user clicks Run search and a result lands, so
        # repeat users see only the stats grid + table.
        return(div(class = "peer-empty-hero",
          div(class = "peer-empty-headline",
              h3("How this works"),
              p(class = "peer-empty-lede",
                "Pick an anchor school, narrow the candidate pool, ",
                "and the tool ranks every remaining institution by ",
                "weighted similarity. Use the results to find peers ",
                "for benchmarking, cohort building, or aspirant analysis.")
          ),

          div(class = "peer-empty-steps",
            div(class = "peer-step",
                div(class = "peer-step-num", "1"),
                div(class = "peer-step-body",
                    h6("Set your anchor school"),
                    p("Open the ", tags$strong("Anchor school"),
                      " picker in the sidebar and start typing. ",
                      "The anchor is the school we compare every ",
                      "candidate against."))),
            div(class = "peer-step",
                div(class = "peer-step-num", "2"),
                div(class = "peer-step-body",
                    h6("Narrow the candidate pool"),
                    p("Default filters mirror the anchor's US News ",
                      "classification and sector. Loosen them to widen ",
                      "the search, or add state / religious tradition / ",
                      "athletics filters to focus."),
                    p(class = "peer-step-aside",
                      tags$strong("Theme weights"), " let you emphasize ",
                      "Enrollment, Admissions, Finance, etc. Presets ",
                      "exist for common framings (Balanced, ",
                      "Outcomes-heavy).") )),
            div(class = "peer-step",
                div(class = "peer-step-num", "3"),
                div(class = "peer-step-body",
                    h6("Run search"),
                    p("Hit the ", tags$strong("Run search"), " button. ",
                      "Results appear here, sorted by distance ascending. ",
                      "Click any row to load that school into the ",
                      tags$strong("Side-by-Side"), " tab for a direct ",
                      "anchor-vs-peer comparison.")))
          ),

          div(class = "peer-empty-method",
            tags$h6("What's happening under the hood"),
            tags$ol(class = "peer-empty-method-list",
              tags$li(tags$strong("Pool. "),
                      "The universe of 4-year, non-profit institutions ",
                      "is filtered by your sidebar selections."),
              tags$li(tags$strong("Z-score. "),
                      "Each variable is standardized over the pool so ",
                      "different units (dollars, percents, counts) ",
                      "contribute on the same scale."),
              tags$li(tags$strong("Distance. "),
                      "Weighted Euclidean distance from each candidate ",
                      "to the anchor, with your theme weights applied."),
              tags$li(tags$strong("Rank. "),
                      "Candidates sorted ascending by distance; lower ",
                      "is more similar."))),

          div(class = "peer-empty-footer",
            p(tags$small(
              "Full variable definitions are on the ",
              tags$strong("Variables"), " tab. Step-by-step examples ",
              "and methodology notes are on the ", tags$strong("Help"),
              " tab. Once results appear, the ",
              tags$strong("About this table"), " link will explain ",
              "each column.")))
        ))
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
                          isolate(sidebar_state$state()$k))))
          # Distance card retired — the distance metric + var counts
          # live in the Diagnostics accordion below, which is where users
          # need them when interpreting results. Top-of-page should
          # surface the headline counts, not methodology details.
      )
    })

    # ---- More-analysis-below indicator ---------------------------------
    # Sits between the stats grid and the results table, so the user
    # sees right away that there's a tab strip of additional views
    # further down. Click smooth-scrolls to the analysis tab area.
    output$analysis_indicator <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      tags$div(
        class = "peer-analysis-indicator",
        onclick = sprintf(
          "document.getElementById('%s').scrollIntoView({behavior:'smooth', block:'start'});",
          ns("analysis_tabs")),
        title = "Jump to additional analytical views",
        tags$span(class = "peer-ai-icon", HTML("&#8595;")),
        tags$span(class = "peer-ai-text",
                   tags$strong("More analysis below:"),
                   " Composition · Map · Dashboard · Aspirant · ",
                   "Stratified · Diagnostics")
      )
    })

    # -------------------------------------------------------------------------
    # Results section header (only visible once a result exists)
    # -------------------------------------------------------------------------
    output$results_header <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      tagList(
        div(class = "peer-results-header",
            h5(sprintf("Top %d peers (click a row to compare)",
                       nrow(res$peers))),
            actionButton(ns("about_table_btn"),
                         label = tagList(
                           tags$span(class = "peer-about-icon",
                                      HTML("&#9432;")),
                           "About this table"),
                         class = "btn peer-about-btn")),
        p(class = "text-muted",
          tags$small("Anchor school appears highlighted at the top. ",
                     "Peers below sorted by distance ascending. Click ",
                     "any column header to re-sort."))
      )
    })

    # ---- About-this-table modal ------------------------------------------
    # Explains every column in the peer table, including the three external
    # rankings (USN, WM, Forbes) and what the Distance metric represents.
    # Triggered from the link rendered next to the "Top N peers" heading.
    observeEvent(input$about_table_btn, {
      showModal(modalDialog(
        title = "About the peer search results table",
        size  = "l",
        easyClose = TRUE,
        footer = modalButton("Close"),
        div(class = "peer-about-body",
          p("Each row is one candidate peer, ordered by similarity to ",
            "the anchor school. Lower ", tags$em("Distance"),
            " values are more similar."),
          tags$h6("Columns"),
          tags$dl(class = "peer-about-dl",
            tags$dt("Rank"),
            tags$dd("Position in this search's peer ranking. 1 = most ",
                    "similar candidate to the anchor on the weighted ",
                    "Euclidean distance over the chosen variables."),

            tags$dt("School"),
            tags$dd("Institution name from IPEDS. Click any row to load ",
                    "this school into the Side-by-Side tab for a direct ",
                    "anchor-vs-peer comparison."),

            tags$dt("Class."),
            tags$dd("US News classification — the published category the ",
                    "school is grouped in (National Liberal Arts College, ",
                    "Regional University–North, etc.). Source: US News ",
                    "Academic Insights ", tags$code("schools/undergraduate"),
                    " endpoint."),

            tags$dt("USN Rank"),
            tags$dd("US News & World Report ", tags$em("overall rank"),
                    " within the school's classification. Blank for ",
                    "unranked schools (US News only ranks schools that ",
                    "appear in the published list). Source: Academic ",
                    "Insights metric_id 24, latest available year. ",
                    "Different categories are NOT directly comparable — ",
                    "a rank of #5 in Liberal Arts is not equivalent to ",
                    "#5 in National Universities."),

            tags$dt("WM Rank"),
            tags$dd("Washington Monthly College Guide rank. Format is ",
                    tags$code("rank (category)"), " where category is one ",
                    "of LA (Liberal Arts), Bacc (Bachelor's), Mas ",
                    "(Master's), or Nat (National Universities). ",
                    "Washington Monthly weights social mobility, ",
                    "research, and public service — a methodological ",
                    "complement to US News. Source: ",
                    tags$code("washingtonmonthly.com/<year>-college-guide/"),
                    "."),

            tags$dt("Forbes Rank"),
            tags$dd("Forbes ", tags$em("America's Top Colleges"),
                    " overall rank. Forbes publishes a single combined ",
                    "list of the top 500 schools (no category split). ",
                    "Forbes emphasizes salary outcomes, low debt, and ",
                    "leader-list alumni. Blank for any school outside ",
                    "the top 500. Source: ",
                    tags$code("forbes.com/top-colleges/"), "."),

            tags$dt("Sector"),
            tags$dd("Institutional control: ", tags$em("public"), " or ",
                    tags$em("private not-for-profit"), ". For-profit ",
                    "schools are excluded from the pool universe by ",
                    "default. Source: IPEDS HD survey, ", tags$code("control"),
                    "."),

            tags$dt("State"),
            tags$dd("Two-letter postal code of the institution's primary ",
                    "campus. Source: IPEDS HD survey, ", tags$code("stabbr"),
                    "."),

            tags$dt("Distance"),
            tags$dd("Weighted Euclidean distance from the anchor school ",
                    "on the chosen clustering variables, computed in ",
                    "z-score space so each variable contributes on the ",
                    "same scale. Variable weights come from the theme ",
                    "weights set in the sidebar. Lower = more similar. ",
                    "Distance is comparable within a single search but ",
                    "not across searches with different pool filters ",
                    "or theme weights — the z-score normalization is ",
                    "computed on the candidate pool, so changing the ",
                    "pool changes the scale.")
          ),
          tags$h6("How a peer search works"),
          tags$ol(
            tags$li("Pool: the universe is filtered by your sidebar ",
                     "(classification, sector, state, religious ",
                     "tradition, ranked-only, etc.)."),
            tags$li("Variables: each variable's value is z-scored over ",
                     "the pool, then weighted by the theme weights you ",
                     "set."),
            tags$li("Distance: Euclidean distance between each candidate ",
                     "and the anchor in the weighted z-space."),
            tags$li("Rank: candidates sorted ascending by distance.")
          ),
          tags$p(class = "text-muted",
                 tags$small("Methodology details and variable definitions ",
                            "are on the ", tags$strong("Variables"),
                            " and ", tags$strong("Help"), " tabs."))
        )
      ))
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
      #   forbes_rank   : Forbes America's Top Colleges overall rank.
      # NA for unranked schools or for older schools.csv files that don't
      # have these columns yet — display as blank in either case.
      .rank_disp <- function(col) {
        if (col %in% names(df)) {
          ifelse(is.na(df[[col]]), "", as.character(df[[col]]))
        } else {
          rep("", nrow(df))
        }
      }
      usn_rank_disp    <- .rank_disp("usnews_rank")
      forbes_rank_disp <- .rank_disp("forbes_rank")
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

      # Religious-affiliation column was retired here — same information
      # is available on the Side-by-Side tab's classifications block when
      # the user wants it. Keeping it out reduces visual noise and the
      # column was empty for the majority of schools.
      display_df <- data.frame(
        Rank          = df$rank,
        School        = df$instnm,
        `Class.`      = .prettify_classification(df$usnews_classification),
        `USN Rank`    = usn_rank_disp,
        `WM Rank`     = wamo_disp,
        `Forbes Rank` = forbes_rank_disp,
        Sector        = .prettify_control(df$control_grp),
        State         = df$stabbr,
        Distance      = round(df$distance, 3),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )

      # Prepend the anchor school as row 1 so the user sees "this is
      # what we're comparing against" before scrolling the peers. Rank
      # is rendered as a dash; distance is 0 (anchor is zero from itself).
      # Excluded from the click-to-select callback in selected_peer().
      anchor_uid <- res$meta$anchor_unitid
      a <- if (!is.null(anchor_uid)) {
        .SCHOOLS[.SCHOOLS$unitid == anchor_uid, , drop = FALSE]
      } else .SCHOOLS[0, , drop = FALSE]
      if (nrow(a) == 1) {
        .one <- function(v) if (is.null(v) || length(v) == 0 ||
                                  is.na(v)) "" else as.character(v)
        a_wamo <- if (!is.na(a$wamo_rank) &&
                       !is.na(a$wamo_category %||% NA)) {
          paste0(a$wamo_rank, " (",
                  wamo_short[a$wamo_category] %||% a$wamo_category, ")")
        } else if (!is.na(a$wamo_rank)) {
          as.character(a$wamo_rank)
        } else ""
        anchor_row_df <- data.frame(
          Rank          = 0L,
          School        = paste0("★ ", a$instnm, "  (anchor)"),
          `Class.`      = .prettify_classification(a$usnews_classification),
          `USN Rank`    = .one(a$usnews_rank),
          `WM Rank`     = a_wamo,
          `Forbes Rank` = .one(a$forbes_rank),
          Sector        = .prettify_control(a$control_grp),
          State         = .one(a$stabbr),
          Distance      = 0,
          check.names = FALSE,
          stringsAsFactors = FALSE
        )
        display_df <- rbind(anchor_row_df, display_df)
      }

      DT::datatable(
        display_df,
        rownames  = FALSE,
        selection = list(mode = "single", target = "row"),
        options = list(
          # pageLength generous enough to hold the maximum K (100) plus
          # the prepended anchor row + a little headroom — single page
          # is the right UX so users see everything at once and the
          # in-DT sort applies across the whole result set.
          pageLength = 150,
          dom        = "tip",
          order      = list(list(0, "asc")),
          columnDefs = list(
            list(className = "dt-right",  targets = c("Distance", "Rank",
                                                       "USN Rank",
                                                       "WM Rank",
                                                       "Forbes Rank")),
            list(className = "dt-center", targets = "State"),
            # Render rank 0 (anchor) as an em-dash so it doesn't read as
            # an actual rank position.
            list(targets = "Rank",
                 render = DT::JS(
                   "function(data, type, row) {",
                   "  if (type === 'display' && data === 0) return '\\u2014';",
                   "  return data;",
                   "}"))
          ),
          # Tag the anchor row with a class so SCSS can highlight it.
          rowCallback = DT::JS(
            "function(row, data) {",
            "  if (data[0] === 0) $(row).addClass('peer-anchor-row');",
            "}")
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
      # Anchor row is prepended at display position 1 (which DT reports
      # as input row 1, 1-indexed). Subtract one to map back to the
      # peers tibble row. Clicking the anchor itself (sel == 1) is a
      # no-op for Side-by-Side — return NULL so the comparison view
      # doesn't try to set the anchor as its own peer.
      if (sel == 1L) return(NULL)
      res$peers[sel - 1L, , drop = FALSE]
    })

    # -------------------------------------------------------------------------
    # Diagnostics (always rendered below the table once a result exists).
    # Rendered as plain block sections under a clear h4. Earlier attempts
    # used bslib accordion and native <details>; both had layout quirks
    # interacting with the surrounding card_body, so this is intentionally
    # boring HTML.
    # -------------------------------------------------------------------------
    # Diagnostics content. Used to be wrapped in a collapsed accordion
    # when this lived inline below the table; now it sits inside the
    # Diagnostics tab of the analytical surfaces strip, so the user has
    # already opted in by clicking the tab — no further hide/show needed.
    output$diagnostics_accordion <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      uiOutput(ns("diagnostics_ui"))
    })

    # ---- Map tab data + render -------------------------------------------
    # Build a single tibble with anchor + peers, lat/long, and a popup
    # HTML chunk. anchor flag drives the marker style choice below.
    peer_map_points <- reactive({
      res <- peer_result()
      if (is.null(res)) return(NULL)
      a_uid <- res$meta$anchor_unitid
      peer_uids <- res$peers$unitid
      uids <- unique(c(a_uid, peer_uids))
      df <- .SCHOOLS[match(uids, .SCHOOLS$unitid), , drop = FALSE]
      df <- df[!is.na(df$latitude) & !is.na(df$longitud), , drop = FALSE]
      if (!nrow(df)) return(NULL)
      df$is_anchor <- df$unitid == a_uid
      # Pull rank from the peer-result tibble (anchor row gets rank "—")
      rank_lookup <- stats::setNames(res$peers$rank, res$peers$unitid)
      df$peer_rank <- ifelse(df$is_anchor, NA_integer_,
                              rank_lookup[as.character(df$unitid)])
      # Popup HTML — escape minimal HTML chars defensively
      .esc <- function(x) gsub("<", "&lt;", gsub("&", "&amp;", x %||% ""))
      df$popup <- vapply(seq_len(nrow(df)), function(i) {
        r <- df[i, ]
        bits <- c(
          sprintf("<strong>%s</strong>", .esc(r$instnm)),
          sprintf("%s &middot; %s",
                  .esc(.prettify_classification(r$usnews_classification)),
                  .esc(r$stabbr)))
        if (r$is_anchor) {
          bits <- c(bits, "<em>Anchor school</em>")
        } else if (!is.na(r$peer_rank)) {
          bits <- c(bits, sprintf("Peer rank: <strong>%d</strong>",
                                   as.integer(r$peer_rank)))
        }
        if (!is.na(r$usnews_rank)) {
          bits <- c(bits, sprintf("USN: %d", as.integer(r$usnews_rank)))
        }
        if (!is.null(r$forbes_rank) && !is.na(r$forbes_rank)) {
          bits <- c(bits, sprintf("Forbes: %d", as.integer(r$forbes_rank)))
        }
        paste(bits, collapse = "<br>")
      }, character(1))
      df$tip <- vapply(seq_len(nrow(df)), function(i) {
        if (df$is_anchor[i])
          sprintf("&#9733; %s (anchor)", .esc(df$instnm[i]))
        else if (!is.na(df$peer_rank[i]))
          sprintf("#%d &middot; %s",
                  as.integer(df$peer_rank[i]), .esc(df$instnm[i]))
        else .esc(df$instnm[i])
      }, character(1))
      df
    })

    output$peer_map <- leaflet::renderLeaflet({
      pts <- peer_map_points()
      m <- leaflet::leaflet(
        options = leaflet::leafletOptions(zoomControl = TRUE,
                                           attributionControl = TRUE)
      ) %>%
        leaflet::addProviderTiles("CartoDB.Positron")

      if (is.null(pts) || !nrow(pts)) {
        return(m %>% leaflet::setView(lng = -98.5, lat = 39.5, zoom = 4))
      }

      anchor_pts <- pts[pts$is_anchor, , drop = FALSE]
      peer_pts   <- pts[!pts$is_anchor, , drop = FALSE]

      if (nrow(peer_pts)) {
        m <- m %>% leaflet::addCircleMarkers(
          data = peer_pts,
          lng = ~longitud, lat = ~latitude,
          color = "#602D89", fillColor = "#602D89",
          radius = 7, weight = 2, opacity = 1, fillOpacity = 0.7,
          label = lapply(peer_pts$tip, htmltools::HTML),
          popup = lapply(peer_pts$popup, htmltools::HTML),
          labelOptions = leaflet::labelOptions(
            direction = "auto", offset = c(0, -10),
            style = list("font-family" = "'Manrope', sans-serif",
                          "font-size" = "12px"))
        )
      }
      if (nrow(anchor_pts)) {
        m <- m %>% leaflet::addAwesomeMarkers(
          data = anchor_pts,
          lng = ~longitud, lat = ~latitude,
          icon = leaflet::awesomeIcons(
            icon = "star", library = "fa",
            iconColor = "#FFFFFF", markerColor = "darkpurple"),
          label = lapply(anchor_pts$tip, htmltools::HTML),
          popup = lapply(anchor_pts$popup, htmltools::HTML),
          labelOptions = leaflet::labelOptions(
            direction = "auto", offset = c(0, -16),
            style = list("font-family" = "'Manrope', sans-serif",
                          "font-size" = "12px"))
        )
      }

      # Fit bounds around the rendered set; pad so markers aren't clipped.
      m %>% leaflet::fitBounds(
        lng1 = min(pts$longitud), lat1 = min(pts$latitude),
        lng2 = max(pts$longitud), lat2 = max(pts$latitude)
      ) %>%
        leaflet::addLegend(
          position = "bottomright",
          colors   = c("#581C87", "#602D89"),
          labels   = c("Anchor", "Peer"),
          opacity  = 0.85
        )
    })

    # Tabs that contain a leaflet inside display:none need a size kick
    # when they become visible — otherwise leaflet computes its initial
    # tile layout against a 0x0 container and renders empty space when
    # the tab is finally shown. Triggering ANY leafletProxy call after
    # the tab activates forces leaflet to re-measure the container.
    observeEvent(input$analysis_nav, {
      if (!identical(input$analysis_nav, "map")) return()
      pts <- peer_map_points()
      if (is.null(pts) || !nrow(pts)) return()
      leaflet::leafletProxy("peer_map", session) |>
        leaflet::fitBounds(
          lng1 = min(pts$longitud), lat1 = min(pts$latitude),
          lng2 = max(pts$longitud), lat2 = max(pts$latitude))
    }, ignoreInit = TRUE)

    # ---- Analytical surfaces tab strip -----------------------------------
    # Single navset_card_tab that holds every below-table analytical
    # lens. Tabs are visible side by side so users discover all
    # available views without scrolling. Each tab body just embeds the
    # already-rendered uiOutput from the existing renderUI bindings —
    # the wrapping container changes, not the section logic.
    #
    # Composition / Map / Dashboard are scaffold placeholders for now
    # (Phase B2-B4); they tell the user what's coming so the feature
    # plan is visible without yet building the full surfaces.
    output$analysis_tabs <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)

      .placeholder <- function(label, blurb) {
        div(class = "peer-tab-placeholder",
            tags$h6(label),
            p(blurb),
            p(class = "text-muted",
              tags$small("Coming in a follow-up update. ",
                          "Wired into the same peer set as the table above.")))
      }

      tagList(
        tags$hr(class = "peer-refine-divider"),
        div(class = "peer-analysis-tabs",
          tabsetPanel(
            id = ns("analysis_nav"),
            type = "tabs",

            tabPanel(
              title = "Composition",
              value = "composition",
              .placeholder(
                "Composition of the peer set",
                paste("Stacked bars summarizing how the peer set breaks",
                      "down on the same nine categorical dimensions used",
                      "in the Cohort Builder (region, sector, control,",
                      "religious tradition, athletics division, etc.),",
                      "with the anchor's category marked for comparison."))
            ),

            tabPanel(
              title = "Map",
              value = "map",
              div(class = "peer-map-tab",
                  p(class = "peer-tab-lede text-muted",
                    tags$small("Peers in this search plotted on a US map. ",
                                "Anchor school marked with a star. ",
                                "Hover for the name; click for details.")),
                  leaflet::leafletOutput(ns("peer_map"), height = "520px"))
            ),

            tabPanel(
              title = "Dashboard",
              value = "dashboard",
              .placeholder(
                "Peer-set dashboard",
                paste("11 metric cards summarizing the peer set's median",
                      "values (enrollment, net price, graduation rate,",
                      "endowment per FTE, etc.), each with an inline",
                      "marker showing the anchor's position on the same",
                      "scale. Same widget as the Cohort Builder dashboard,",
                      "applied to this search result."))
            ),

            tabPanel(
              title = "Refine: Aspirant",
              value = "aspirant",
              uiOutput(ns("aspirant_refine_section"))
            ),

            tabPanel(
              title = "Refine: Stratified",
              value = "stratified",
              uiOutput(ns("stratified_expand_section"))
            ),

            tabPanel(
              title = "Diagnostics",
              value = "diagnostics",
              uiOutput(ns("diagnostics_accordion"))
            )
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
