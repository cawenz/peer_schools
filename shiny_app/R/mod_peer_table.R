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

# -----------------------------------------------------------------------------
# Empty-state hero — static onboarding panel shown until the first
# Run search lands. Pure HTML, no reactive dependencies, so it lives in
# the static UI and renders on the first DOM paint instead of requiring
# a server-side renderUI roundtrip.
#
# Returns a top-level div the caller can drop into a conditionalPanel.
# `ns` is the module namespace function (NS(id)) so any future input
# references stay namespaced; right now nothing inside the hero binds
# to inputs, but threading it through keeps the contract clean.
# -----------------------------------------------------------------------------
.peer_empty_hero <- function(ns) {
  div(class = "peer-empty-hero",
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
              h6("Tune the weights (optional)"),
              p("If a single variable matters more than its theme ",
                "would suggest, override it directly. Click ",
                tags$strong("Customize variables…"),
                " under the theme sliders to open the full ",
                "clustering-variable list — check each variable ",
                "you want to override and set its weight from 0 ",
                "(drop entirely) to 3 (triple influence). ",
                "Unchecked variables continue to use their theme ",
                "weight."),
              p(class = "peer-step-aside",
                "Most searches don't need this — the theme sliders ",
                "cover the common cases. Reach for individual ",
                "overrides when you want to spotlight a specific ",
                "metric (e.g. ", tags$em("grad rate"),
                ") above everything else in its theme.") )),
      div(class = "peer-step",
          div(class = "peer-step-num", "4"),
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
                "to the anchor. Theme weights apply by default; ",
                "individual variables override their theme weight ",
                "when you've customized them."),
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
  )
}

peerTableUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Peer Search"),
    # Tagline only — full onboarding lives in the empty-state hero
    # rendered inline below so the explanation is right where the
    # user's eye is once they're ready to read.
    p(class = "section-intro",
      "Rank institutions by similarity to an anchor school across IPEDS, ",
      "US News, Carnegie, EADA, and Scorecard data."),

    # Empty-state hero now lives in the static UI (wrapped in a
    # conditionalPanel that hides it once results land) so it paints
    # on the first DOM render rather than waiting for a server-side
    # renderUI roundtrip to ship the same static HTML over WebSocket.
    # This is the bulk of the perceived "app launch is slow" feeling.
    conditionalPanel(
      condition = sprintf("!output['%s']", ns("has_results")),
      .peer_empty_hero(ns)
    ),

    # Stats grid (rendered server-side ONLY after first search).
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

    # -------------------------------------------------------------------------
    # Curated peer-set state — layered on top of peer_result().
    #
    #   excluded   : integer vector of unitids the user removed.
    #   added      : list of (unitid -> list(source, distance)) records added
    #                from Aspirant / Stratified / a manual picker. A school
    #                can be BOTH in res$peers (original) AND in added (with
    #                a source tag like "Aspirant") — the Status column will
    #                stack both badges.
    #
    # Resets whenever peer_result() changes (new search clears the curation),
    # except when the new value is being restored from a saved search that
    # carries its own curated state. See the restore handler below.
    # -------------------------------------------------------------------------
    .empty_curated <- function() list(excluded = integer(0), added = list())
    peer_curated_state <- reactiveVal(.empty_curated())
    # NB: curation reset happens INSIDE the Run handler (see below)
    # rather than via observeEvent(peer_result(), ...). That way a
    # saved-search restore can repopulate peer_curated_state without
    # being immediately wiped by an observer reacting to the same
    # programmatic peer_result update.

    # Helper: add a school to the curated list with a source tag.
    .add_school_to_main <- function(unitid, source, distance = NA_real_) {
      uid <- as.integer(unitid)
      if (is.na(uid)) return(invisible())
      st <- peer_curated_state()
      # Drop from excluded if previously removed
      st$excluded <- setdiff(st$excluded, uid)
      key <- as.character(uid)
      cur <- st$added[[key]]
      if (is.null(cur)) {
        st$added[[key]] <- list(sources = source, distance = distance)
      } else {
        # Already added — append the new source tag if not present
        st$added[[key]]$sources <- unique(c(cur$sources, source))
      }
      peer_curated_state(st)
    }

    # Helper: remove a school from the main list.
    .remove_school_from_main <- function(unitid) {
      uid <- as.integer(unitid)
      if (is.na(uid)) return(invisible())
      st <- peer_curated_state()
      # If it was a manual add, drop the add entirely. Otherwise mark
      # the original peer as excluded.
      key <- as.character(uid)
      if (!is.null(st$added[[key]])) {
        st$added[[key]] <- NULL
      }
      st$excluded <- unique(c(st$excluded, uid))
      peer_curated_state(st)
    }

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
              anchor_unitid    = st$anchor_unitid,
              candidate_pool   = st$candidate_pool,
              theme_weights    = st$theme_weights,
              variable_weights = st$variable_weights %||% list(),
              distance_metric  = st$distance_metric,
              k                = st$k
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
          # Reset curation BEFORE pushing the new result so the user
          # starts from a clean slate with each fresh search.
          peer_curated_state(.empty_curated())
          peer_result(res)
        }
      )
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    # -------------------------------------------------------------------------
    # Header: stats grid AFTER first search. The empty-state hero now
    # lives in the static UI (peerTableUI) wrapped in a conditionalPanel
    # so it paints on first DOM render instead of waiting for the server
    # to ship the same static HTML over WebSocket.
    # -------------------------------------------------------------------------

    # Flag for the conditionalPanel guarding the empty-state hero. Has
    # to be exposed via outputOptions(suspendWhenHidden = FALSE) below
    # so the value reaches the client even before any output that reads
    # it is on screen.
    output$has_results <- reactive({ !is.null(peer_result()) })
    outputOptions(output, "has_results", suspendWhenHidden = FALSE)

    output$header_or_empty <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(NULL)   # static hero covers this case

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
      # Rendered as a semantic button so screen readers and keyboard
      # users get the right affordance. The scroll target is the
      # analysis tab strip below the results table.
      target_id  <- ns("analysis_tabs")
      # bslib layout_sidebar wraps the main content area in its own
      # overflow:auto container. scrollIntoView() defaults to scrolling
      # the nearest scrollable ancestor, but that path can no-op when
      # the ancestor's overflow is set up so the element is technically
      # "in view" of the container even though the visible viewport
      # hasn't moved. Solve it manually: walk up looking for the first
      # ancestor whose scrollHeight > clientHeight (the actually-scrolling
      # one), then set its scrollTop directly.
      # JS notes:
      # - Target the inner div.peer-analysis-tabs (the element the user
      #   actually wants in view) rather than the 0-height uiOutput
      #   placeholder #peer_table-analysis_tabs, which sits at a
      #   negative layout position inside the flex container.
      # - Walk up looking for the first scrollable ancestor whose box
      #   actually CONTAINS the target (positive relative offset). The
      #   bslib layout_sidebar's .main bslib-gap-spacing div is what
      #   ends up scrolling.
      # - Math.max(0, ...) guards against any leftover negative offset.
      scroll_js <- sprintf(
        paste0(
          "(function(){",
          "  var t=document.querySelector('.peer-analysis-tabs');",
          "  if(!t){t=document.getElementById('%s');}",
          "  if(!t)return;",
          "  var c=t.parentElement;",
          "  while(c&&c!==document.body){",
          "    var s=getComputedStyle(c);",
          "    var oy=s.overflowY;",
          "    if((oy==='auto'||oy==='scroll')&&c.scrollHeight>c.clientHeight){",
          "      var rt=t.getBoundingClientRect().top-c.getBoundingClientRect().top;",
          "      if(rt>=0)break;",
          "    }",
          "    c=c.parentElement;",
          "  }",
          "  if(c&&c!==document.body){",
          "    var rect=t.getBoundingClientRect();",
          "    var crect=c.getBoundingClientRect();",
          "    var top=c.scrollTop+(rect.top-crect.top)-12;",
          "    c.scrollTo({top:Math.max(0,top),behavior:'smooth'});",
          "  }else{",
          "    var y=Math.max(0,window.pageYOffset+t.getBoundingClientRect().top-12);",
          "    window.scrollTo({top:y,behavior:'smooth'});",
          "  }",
          "})();"),
        target_id)
      tags$div(
        class = "peer-analysis-indicator",
        role = "button",
        tabindex = "0",
        onclick  = scroll_js,
        onkeydown = sprintf(
          "if(event.key==='Enter'||event.key===' '){event.preventDefault();%s}",
          scroll_js),
        title = "Jump to additional analytical views",
        tags$span(class = "peer-ai-icon", HTML("&#8595;")),
        tags$span(class = "peer-ai-text",
                   tags$strong("More analysis below:"),
                   " Composition · Map · Dashboard · Inspector · ",
                   "Aspirant · Stratified · Diagnostics")
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
            # Right-side action cluster: downloads + the About modal
            # link. Downloads come first since they're the action users
            # are most likely to take after reviewing the table.
            div(class = "peer-results-actions",
              downloadButton(ns("download_xlsx"),
                             label = "Excel",
                             class = "btn btn-sm peer-download-btn",
                             icon  = icon("file-excel")),
              downloadButton(ns("download_pdf"),
                             label = "PDF",
                             class = "btn btn-sm peer-download-btn",
                             icon  = icon("file-pdf")),
              actionButton(ns("about_table_btn"),
                           label = tagList(
                             tags$span(class = "peer-about-icon",
                                        HTML("&#9432;")),
                             "About this table"),
                           class = "btn peer-about-btn"))),
        p(class = "text-muted",
          tags$small("Anchor school appears highlighted at the top. ",
                     "Peers below sorted by distance ascending. Click ",
                     "any column header to re-sort."))
      )
    })

    # ---- Download handlers ------------------------------------------------
    # Both bind to peer_result() / sidebar_state$state() so they always
    # reflect the current search. Filenames embed the anchor name +
    # timestamp so downloads don't collide in the user's Downloads folder.
    .download_basename <- function(res, ext) {
      anchor_name <- res$meta$anchor_name %||% "anchor"
      safe <- gsub("[^A-Za-z0-9]+", "_", anchor_name)
      safe <- substr(safe, 1, 40)
      sprintf("peer_search_%s_%s.%s",
              safe,
              format(Sys.time(), "%Y%m%d_%H%M%S"),
              ext)
    }

    output$download_xlsx <- downloadHandler(
      filename = function() {
        res <- peer_result()
        if (is.null(res)) "peer_search.xlsx"
        else .download_basename(res, "xlsx")
      },
      content = function(file) {
        res <- peer_result()
        st  <- sidebar_state$state()
        if (is.null(res)) {
          # Shouldn't happen — button only renders when results exist —
          # but if it does, write an empty placeholder so the browser's
          # download flow doesn't hang.
          openxlsx::write.xlsx(
            data.frame(message = "No search results to download."),
            file)
          return()
        }
        build_peer_xlsx(res, st, file)
      },
      contentType =
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    output$download_pdf <- downloadHandler(
      filename = function() {
        res <- peer_result()
        if (is.null(res)) "peer_search.pdf"
        else .download_basename(res, "pdf")
      },
      content = function(file) {
        res <- peer_result()
        st  <- sidebar_state$state()
        if (is.null(res)) {
          writeLines("No search results to download.", file)
          return()
        }
        # PDF render can take 30-60s on a cold tinytex install (it
        # auto-fetches LaTeX packages); subsequent renders are fast.
        # showNotification gives the user immediate feedback.
        id <- showNotification("Building PDF report…",
                               duration = NULL, type = "message")
        on.exit(removeNotification(id), add = TRUE)
        tryCatch(
          build_peer_pdf(res, st, file),
          error = function(e) {
            removeNotification(id)
            showNotification(
              paste("PDF generation failed:", conditionMessage(e)),
              duration = 10, type = "error")
            # Write a one-line placeholder so the browser's download
            # handshake completes — the notification surfaces the real
            # error to the user.
            writeLines(paste("PDF generation failed:",
                              conditionMessage(e)), file)
          }
        )
      },
      contentType = "application/pdf"
    )

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
      curated <- peer_curated_state()

      # ---- Filter excluded peers and append added schools ----
      df_base   <- tibble::as_tibble(res$peers)
      excluded  <- curated$excluded
      df_visible <- df_base[!(df_base$unitid %in% excluded), , drop = FALSE]

      added_uids <- as.integer(names(curated$added))
      added_uids <- added_uids[!is.na(added_uids)]
      added_uids <- added_uids[!added_uids %in% df_visible$unitid]
      added_uids <- added_uids[!added_uids %in% excluded]

      # Debug: log what's in curated state and what we're about to render.
      message(sprintf(
        "[peer-table] excluded=%d  added_total=%d  added_to_append=%d  visible_before=%d",
        length(excluded), length(curated$added), length(added_uids),
        nrow(df_visible)))

      if (length(added_uids)) {
        s <- .SCHOOLS[match(added_uids, .SCHOOLS$unitid), , drop = FALSE]
        added_df <- tibble::tibble(
          rank     = NA_integer_,
          unitid   = added_uids,
          instnm   = s$instnm,
          sector   = NA_integer_,
          usnews_classification = s$usnews_classification,
          stabbr   = s$stabbr,
          control_grp = s$control_grp,
          religious_affiliation = s$religious_affiliation,
          distance = vapply(added_uids, function(u) {
            d <- curated$added[[as.character(u)]]$distance
            if (is.null(d) || !is.finite(d)) NA_real_ else as.numeric(d)
          }, numeric(1))
        )
        # Pull external-rank cols when present in both .SCHOOLS and the
        # original result so the new rows show ranks consistently.
        for (col in c("usnews_rank", "wamo_rank", "wamo_category",
                       "forbes_rank")) {
          if (col %in% names(df_base) && col %in% names(s))
            added_df[[col]] <- s[[col]]
        }
        # dplyr::bind_rows handles tibble + data.frame column-fill +
        # type promotion cleanly, unlike base rbind which can choke on
        # tibble/data.frame mixes or differing column orders.
        df_visible <- dplyr::bind_rows(df_visible, added_df)
        message(sprintf("[peer-table] visible_after_append=%d",
                        nrow(df_visible)))
      }
      df <- df_visible

      # Sort-safe cell builder: DataTables honours the data-order
      # attribute on the cell's outer element for sorting (the cell still
      # *displays* the inner text). Without this, an integer rank column
      # rendered as character string-sorts "10" < "2" < "27"; with it,
      # DT sorts by the underlying numeric value. NA values get a sentinel
      # of 999999 so they sink to the bottom on ascending sort.
      .sort_html_num <- function(value, display = NULL) {
        if (is.null(display))
          display <- ifelse(is.na(value), "", as.character(value))
        ifelse(is.na(value),
               '<span data-order="999999"></span>',
               sprintf('<span data-order="%g">%s</span>',
                       as.numeric(value),
                       htmltools::htmlEscape(display)))
      }
      .rank_disp <- function(col) {
        if (col %in% names(df)) .sort_html_num(df[[col]])
        else rep('<span data-order="999999"></span>', nrow(df))
      }
      usn_rank_disp    <- .rank_disp("usnews_rank")
      forbes_rank_disp <- .rank_disp("forbes_rank")
      wamo_short <- c("Liberal Arts" = "LA", "Baccalaureate" = "Bacc",
                      "Master's" = "Mas",  "National" = "Nat")
      wamo_disp <- if ("wamo_rank" %in% names(df)) {
        cat <- if ("wamo_category" %in% names(df)) df$wamo_category
               else rep(NA_character_, nrow(df))
        sfx <- ifelse(is.na(cat), "", paste0(" (", wamo_short[cat], ")"))
        # Display text combines rank + category suffix; sort key is the
        # bare numeric rank so columns like "2 (LA)" still sort right.
        disp_text <- ifelse(is.na(df$wamo_rank), "",
                             paste0(as.character(df$wamo_rank), sfx))
        .sort_html_num(df$wamo_rank, disp_text)
      } else {
        rep('<span data-order="999999"></span>', nrow(df))
      }

      # ---- Build Status badges ----
      # For each row: which source tags apply.
      original_uids <- df_base$unitid    # full original set (incl. excluded)
      status_badges <- vapply(df$unitid, function(uid) {
        tags <- c()
        if (uid %in% original_uids) tags <- c(tags, "Original")
        ad <- curated$added[[as.character(uid)]]
        if (!is.null(ad)) tags <- c(tags, ad$sources)
        if (!length(tags)) return("")
        paste(vapply(tags, function(t) {
          slug <- tolower(gsub("[^a-z0-9]+", "-", t))
          sprintf('<span class="peer-status-badge peer-status-%s">%s</span>',
                  slug, htmltools::htmlEscape(t))
        }, character(1)), collapse = " ")
      }, character(1))

      # ---- Build per-row Remove action ----
      # The actual click handler lives at the table level via the
      # input$peer_table_cell_clicked observer below (inline onclicks
      # get consumed by DTs row-selection event before they can fire).
      action_html <- rep(
        '<span class="peer-remove-btn" title="Remove from main list">&#10005;</span>',
        nrow(df))

      # Religious-affiliation column was retired here — same information
      # is available on the Side-by-Side tab's classifications block.
      display_df <- data.frame(
        Rank          = df$rank,
        School        = df$instnm,
        Status        = status_badges,
        `Class.`      = .prettify_classification(df$usnews_classification),
        `USN Rank`    = usn_rank_disp,
        `WM Rank`     = wamo_disp,
        `Forbes Rank` = forbes_rank_disp,
        Sector        = .prettify_control(df$control_grp),
        State         = df$stabbr,
        Distance      = round(df$distance, 3),
        Actions       = action_html,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )

      # ---- Prepend the anchor row (no actions, no badges) ----
      anchor_uid <- res$meta$anchor_unitid
      a <- if (!is.null(anchor_uid)) {
        .SCHOOLS[.SCHOOLS$unitid == anchor_uid, , drop = FALSE]
      } else .SCHOOLS[0, , drop = FALSE]
      if (nrow(a) == 1) {
        .one <- function(v) if (is.null(v) || length(v) == 0 ||
                                  is.na(v)) "" else as.character(v)
        # Anchor row uses the same sort-safe rank format as peer rows so
        # the column sorts consistently even when the anchor's USN /
        # WM / Forbes rank is itself a number that would otherwise be
        # string-sorted vs the peer rows.
        a_wamo_disp_text <- if (!is.na(a$wamo_rank) &&
                                   !is.na(a$wamo_category %||% NA)) {
          paste0(a$wamo_rank, " (",
                  wamo_short[a$wamo_category] %||% a$wamo_category, ")")
        } else if (!is.na(a$wamo_rank)) {
          as.character(a$wamo_rank)
        } else ""
        anchor_row_df <- data.frame(
          Rank          = 0L,
          School        = paste0("★ ", a$instnm, "  (anchor)"),
          Status        = '<span class="peer-status-badge peer-status-anchor">Anchor</span>',
          `Class.`      = .prettify_classification(a$usnews_classification),
          `USN Rank`    = .sort_html_num(a$usnews_rank),
          `WM Rank`     = .sort_html_num(a$wamo_rank, a_wamo_disp_text),
          `Forbes Rank` = .sort_html_num(a$forbes_rank),
          Sector        = .prettify_control(a$control_grp),
          State         = .one(a$stabbr),
          Distance      = 0,
          Actions       = "",
          check.names = FALSE,
          stringsAsFactors = FALSE
        )
        display_df <- rbind(anchor_row_df, display_df)
      }

      DT::datatable(
        display_df,
        rownames  = FALSE,
        escape    = FALSE,  # allow HTML in Status + Actions columns
        selection = list(mode = "single", target = "row"),
        options = list(
          pageLength = 150,
          dom        = "tip",
          order      = list(list(0, "asc")),
          columnDefs = list(
            list(className = "dt-right",  targets = c("Distance", "Rank",
                                                       "USN Rank",
                                                       "WM Rank",
                                                       "Forbes Rank")),
            list(className = "dt-center", targets = c("State", "Actions")),
            list(targets = "Rank",
                 render = DT::JS(
                   "function(data, type, row) {",
                   "  if (type === 'display' && data === 0) return '\\u2014';",
                   "  if (type === 'display' && data === null) return '+';",
                   "  return data;",
                   "}"))
          ),
          rowCallback = DT::JS(
            "function(row, data) {",
            "  if (data[0] === 0) $(row).addClass('peer-anchor-row');",
            "}")
        ),
        class = "compact stripe hover"
      ) |>
        DT::formatRound("Distance", digits = 3)
    })

    # ---- Main peer table cell click: discriminate Remove vs row-select --
    # Inline onclick handlers don't fire reliably inside DT cells because
    # DT row-selection consumes the event first. We use cell_clicked
    # instead and check whether the clicked cell contained the
    # peer-remove-btn span; if so, the click is a Remove. Otherwise let
    # the row-selection update Side-by-Side as usual.
    observeEvent(input$peer_table_cell_clicked, {
      payload <- input$peer_table_cell_clicked
      if (is.null(payload) || is.null(payload$row)) return()
      val <- payload$value %||% ""
      if (!grepl("peer-remove-btn", val, fixed = TRUE)) return()
      uids <- peer_display_uids()
      r <- payload$row
      if (r < 1 || r > length(uids)) return()
      uid <- uids[r]
      message(sprintf(
        "[peer-remove] cell click row=%d uid=%d", r, uid))
      .remove_school_from_main(uid)
      # Clear row selection so the row click doesn't propagate as a
      # Side-by-Side selection on the about-to-disappear row.
      DT::dataTableProxy("peer_table") %>% DT::selectRows(NULL)
    })

    # ---- Add-to-main click observer (Aspirant + Stratified rows) -------
    observeEvent(input$peer_add_click, {
      payload <- input$peer_add_click
      if (is.null(payload) || is.null(payload$unitid)) return()
      d <- payload$distance
      if (is.null(d)) d <- NA_real_
      message(sprintf(
        "[peer-add] click payload: unitid=%s source=%s distance=%s",
        payload$unitid, payload$source, d))
      .add_school_to_main(payload$unitid, payload$source,
                            as.numeric(d))
      message(sprintf(
        "[peer-add] state after add: %d excluded, %d added",
        length(peer_curated_state()$excluded),
        length(peer_curated_state()$added)))
      # Brief toast so users see the action register
      showNotification(
        tagList(tags$strong("Added: "),
                .SCHOOLS$instnm[match(as.integer(payload$unitid),
                                       .SCHOOLS$unitid)],
                tags$br(),
                tags$small(sprintf("Source: %s", payload$source))),
        type = "message", duration = 3)
    })

    # -------------------------------------------------------------------------
    # Selected peer row → exposed reactive for the Side-by-Side tab
    # -------------------------------------------------------------------------
    # Track the unitids in the currently-displayed table so clicks can
    # be resolved back to a school regardless of curation state (excluded
    # peers removed, added schools appended).
    peer_display_uids <- reactive({
      res <- peer_result()
      if (is.null(res)) return(integer(0))
      curated <- peer_curated_state()
      base_uids <- res$peers$unitid[!res$peers$unitid %in% curated$excluded]
      added_uids <- as.integer(names(curated$added))
      added_uids <- added_uids[!added_uids %in% base_uids &
                                  !added_uids %in% curated$excluded]
      c(res$meta$anchor_unitid, base_uids, added_uids)
    })

    selected_peer <- reactive({
      res <- peer_result()
      sel <- input$peer_table_rows_selected
      if (is.null(res) || !length(sel)) return(NULL)
      uids <- peer_display_uids()
      if (sel < 1 || sel > length(uids)) return(NULL)
      uid <- uids[sel]
      # Clicking the anchor row (always row 1) is a no-op for Side-by-Side
      if (identical(uid, res$meta$anchor_unitid)) return(NULL)
      # Prefer the row in res$peers (original peer with computed distance);
      # fall back to a synthesized row from .SCHOOLS for added schools.
      hit <- res$peers[res$peers$unitid == uid, , drop = FALSE]
      if (nrow(hit) == 1) return(hit)
      s <- .SCHOOLS[.SCHOOLS$unitid == uid, , drop = FALSE]
      if (!nrow(s)) return(NULL)
      data.frame(
        rank     = NA_integer_,
        unitid   = uid,
        instnm   = s$instnm,
        sector   = NA,
        usnews_classification = s$usnews_classification,
        stabbr   = s$stabbr,
        control_grp = s$control_grp,
        religious_affiliation = s$religious_affiliation,
        distance = NA_real_,
        stringsAsFactors = FALSE
      )
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
      if (is.null(res)) return(.needs_search_notice("Diagnostics"))
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

    # ---- Dashboard tab ---------------------------------------------------
    # 11 headline metric cards. Each card pairs a small SVG strip
    # (ranked-universe distribution + peer rug + anchor line) with a
    # cohort-summary line beneath. Same visual conventions and CSS
    # classes (.dash-card, .dash-strip, .dash-card-anchor, etc.) as the
    # Cohort Builder dashboard so the two surfaces feel consistent.
    .PEER_DASHBOARD_METRICS <- c(
      "acceptance_rate",
      "sat_mid50",
      "student_faculty_ratio",
      "avg_ft_faculty_salary",
      "herd_avg",
      "endowment_per_fte",
      "grad_rate_6yr",
      "pct_pell",
      "pct_bipoc",
      "undergraduate_enrollment",
      "n_undergrad_programs"
    )

    # Action -> color for the per-school rug. Only two actions in this
    # context: Peer (everyone in the peer set) + Anchor (drawn separately
    # as a tall line, not a rug tick).
    .PEER_DASH_ACTION_COLORS <- c("Anchor" = "#602D89", "Peer" = "#AC9E94")

    # Source pretty-print helpers (copy of mod_cohort.R locals — both
    # surfaces want the same chip labels). Move to a shared helper file
    # the next time we refactor.
    .PEER_SOURCE_LABELS <- c(
      ipeds          = "IPEDS",
      ipeds_derived  = "IPEDS",
      ccihe          = "Carnegie 2025 Data File",
      cds_ai         = "Common Data Set",
      cds_ai_derived = "Common Data Set",
      scorecard      = "College Scorecard"
    )
    .PEER_COMPUTED_SOURCES <- c("ipeds_derived", "cds_ai_derived", "ccihe")
    .simplify_source <- function(src) {
      if (is.null(src) || is.na(src) || !nzchar(src))
        return("Unknown source")
      lbl <- .PEER_SOURCE_LABELS[[src]]
      if (is.null(lbl)) src else lbl
    }
    .is_computed_source <- function(src) {
      if (is.null(src) || is.na(src) || !nzchar(src)) return(FALSE)
      src %in% .PEER_COMPUTED_SOURCES
    }

    # Universe baseline = full ranked universe, same as Cohort Builder.
    peer_dashboard_universe <- reactive({
      .SCHOOLS_WIDE[.SCHOOLS_WIDE$in_ranked_universe %in% TRUE, ,
                     drop = FALSE]
    })

    # Tidy rug data.frame for a given metric: anchor row + every peer
    # row from the current peer_result, with their action labels.
    .peer_build_rug_data <- function(metric) {
      res <- peer_result()
      if (is.null(res) || !metric %in% names(.SCHOOLS_WIDE)) {
        return(data.frame(unitid = integer(), action = character(),
                          value = numeric(), instnm = character(),
                          stringsAsFactors = FALSE))
      }
      a_uid     <- res$meta$anchor_unitid
      peer_uids <- res$peers$unitid

      anchor_meta <- .SCHOOLS[.SCHOOLS$unitid == a_uid, , drop = FALSE]
      peer_meta   <- .SCHOOLS[match(peer_uids, .SCHOOLS$unitid), , drop = FALSE]

      df <- data.frame(
        unitid = c(a_uid, peer_uids),
        action = c("Anchor", rep("Peer", length(peer_uids))),
        instnm = c(if (nrow(anchor_meta)) anchor_meta$instnm[1] else "(anchor)",
                    peer_meta$instnm),
        stringsAsFactors = FALSE
      )
      df$value <- .SCHOOLS_WIDE[[metric]][match(df$unitid,
                                                  .SCHOOLS_WIDE$unitid)]
      df
    }

    # SVG strip — direct port of the cohort version, narrowed to the
    # action palette this tab needs. Returns an HTML() string.
    .peer_dashboard_strip_svg <- function(universe_vals, anchor_val,
                                           rug_data = NULL,
                                           width = 280, height = 48) {
      uv <- universe_vals[is.finite(universe_vals)]
      if (length(uv) < 5)
        return(tags$div(class = "dash-strip-empty",
                         "Insufficient data"))
      q <- stats::quantile(uv, c(0.01, 0.99), na.rm = TRUE)
      uv_min <- as.numeric(q[1]); uv_max <- as.numeric(q[2])
      rng <- uv_max - uv_min
      if (rng <= 0)
        return(tags$div(class = "dash-strip-empty", "No variation"))

      density_top    <- 4
      density_bottom <- height - 14
      rug_top        <- height - 10
      rug_bottom     <- height - 2
      density_h      <- density_bottom - density_top

      dens <- stats::density(uv, from = uv_min, to = uv_max, n = 60)
      max_dens <- max(dens$y); if (max_dens <= 0) max_dens <- 1
      dens_y <- (dens$y / max_dens) * density_h
      to_x <- function(v) {
        ((pmin(pmax(v, uv_min), uv_max) - uv_min) / rng) * width
      }
      poly_x <- c(to_x(dens$x),
                   to_x(dens$x[length(dens$x)]),
                   to_x(dens$x[1]))
      poly_y <- c(density_bottom - dens_y,
                   rep(density_bottom, 2))
      pts <- paste(sprintf("%.1f,%.1f", poly_x, poly_y), collapse = " ")

      rug_str <- ""
      if (!is.null(rug_data) && nrow(rug_data) > 0) {
        rd <- rug_data[is.finite(rug_data$value) &
                        rug_data$action != "Anchor", , drop = FALSE]
        if (nrow(rd)) {
          colors <- unname(.PEER_DASH_ACTION_COLORS[as.character(rd$action)])
          colors[is.na(colors)] <- "#AC9E94"
          rug_parts <- vapply(seq_len(nrow(rd)), function(i) {
            x <- to_x(rd$value[i])
            sprintf(paste0('<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" ',
                            'stroke="%s" stroke-width="1.6" ',
                            'stroke-opacity="0.85" stroke-linecap="round"/>'),
                    x, x, rug_top, rug_bottom, colors[i])
          }, character(1))
          rug_str <- paste(rug_parts, collapse = "")
        }
      }
      anchor_str <- if (is.finite(anchor_val)) {
        ax <- to_x(anchor_val)
        sprintf(paste0('<line x1="%.1f" x2="%.1f" y1="2" y2="%.1f" ',
                        'stroke="#602D89" stroke-width="2.5"/>',
                        '<circle cx="%.1f" cy="2" r="3.5" fill="#602D89"/>'),
                ax, ax, rug_bottom, ax)
      } else ""

      HTML(sprintf(
        paste0('<svg class="dash-strip" width="%d" height="%d" ',
                'viewBox="0 0 %d %d" preserveAspectRatio="none">',
                '<polygon points="%s" fill="#F4EDEC" stroke="#AC9E94" ',
                'stroke-width="0.5"/>',
                '%s%s',
                '</svg>'),
        width, height, width, height, pts, rug_str, anchor_str
      ))
    }

    # Build a single card. Clicking sends the metric back via a custom
    # input event so the modal observer can render the detail view.
    .peer_dashboard_card <- function(metric, anchor_val, rug_data,
                                       universe_vals, display_name, fmt) {
      cv  <- rug_data$value[rug_data$action != "Anchor" &
                              is.finite(rug_data$value)]
      n_c <- sum(rug_data$action != "Anchor")
      n_r <- length(cv)

      peer_line <- if (n_r > 0) {
        sprintf("Peers: %s – %s   (median %s)",
                .format_value(min(cv),           fmt),
                .format_value(max(cv),           fmt),
                .format_value(stats::median(cv), fmt))
      } else "Peers: no data"

      strip <- .peer_dashboard_strip_svg(universe_vals, anchor_val,
                                          rug_data = rug_data)

      # Year-window label ("snapshot (2024)" / "5-yr avg" / etc.) from
      # the .VAR_YEARS_LABEL lookup populated in global.R. Renders as a
      # small subtitle under the metric name.
      years_lbl <- .VAR_YEARS_LABEL[[metric]] %||% ""

      tags$div(class = "dash-card",
        `data-metric` = metric,
        # Card click -> send {metric, t} to Shiny so the modal observer
        # fires. `priority: 'event'` ensures repeat clicks on the same
        # card always re-trigger.
        onclick = sprintf(
          "Shiny.setInputValue('%s', {metric: '%s', t: Date.now()}, {priority: 'event'});",
          ns("peer_dash_card_click"), metric),
        tags$div(class = "dash-card-title", display_name),
        if (nzchar(years_lbl))
          tags$div(class = "dash-card-years", years_lbl),
        tags$div(class = "dash-card-anchor",
          tags$span(class = "dash-card-anchor-label", "Anchor"),
          tags$span(class = "dash-card-anchor-val",
                     .format_value(anchor_val, fmt))
        ),
        strip,
        tags$div(class = "dash-card-cohort", peer_line),
        tags$div(class = "dash-card-n",
                  sprintf("%d of %d reporting", n_r, n_c))
      )
    }

    # ---- Click-to-modal --------------------------------------------------
    # Opens a modal with a larger strip + per-school value table for the
    # clicked metric. Same visual conventions as the Cohort dashboard
    # modal so the two surfaces stay consistent.
    observeEvent(input$peer_dash_card_click, {
      payload <- input$peer_dash_card_click
      if (is.null(payload) || is.null(payload$metric)) return()
      metric <- payload$metric
      if (!metric %in% names(.SCHOOLS_WIDE)) return()
      res <- peer_result(); req(res)

      meta <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      dn   <- if (nrow(meta) && !is.na(meta$display_name)) meta$display_name
              else metric
      fmt  <- if (nrow(meta)) meta$format else NA

      desc <- if (nrow(meta) && !is.na(meta$notes) && nzchar(meta$notes))
                meta$notes
              else if (nrow(meta) && !is.na(meta$coverage_note) &&
                        nzchar(meta$coverage_note))
                meta$coverage_note
              else "No description recorded for this variable."

      chips <- tagList()
      if (nrow(meta)) {
        chip_specs <- list(
          c("Source",   .simplify_source(meta$source)),
          c("Category", if (!is.na(meta$category)) meta$category else ""),
          c("Format",   if (!is.na(meta$format))   meta$format   else ""),
          c("Years",    .VAR_YEARS_LABEL[[metric]] %||% "")
        )
        chips <- tagList(
          lapply(chip_specs, function(p) {
            if (!nzchar(p[2])) return(NULL)
            tags$span(class = "dash-modal-chip",
                      tags$strong(p[1], ":"), " ", p[2])
          }),
          if (.is_computed_source(meta$source))
            tags$span(class = "dash-modal-chip dash-modal-chip-computed",
                      title = "This value is derived from one or more raw inputs.",
                      "Computed")
        )
      }

      a_uid    <- res$meta$anchor_unitid
      anchor_v <- .SCHOOLS_WIDE[[metric]][.SCHOOLS_WIDE$unitid == a_uid][1]
      rug      <- .peer_build_rug_data(metric)
      univ     <- peer_dashboard_universe()

      big_strip <- .peer_dashboard_strip_svg(univ[[metric]], anchor_v,
                                              rug_data = rug,
                                              width = 720, height = 80)

      uv <- univ[[metric]]; uv <- uv[is.finite(uv)]
      pct <- function(v) {
        if (!is.finite(v) || !length(uv)) return(NA_real_)
        100 * mean(uv < v)
      }
      tbl_rows <- rug
      tbl_rows$state <- .SCHOOLS$stabbr[match(tbl_rows$unitid, .SCHOOLS$unitid)]
      tbl_rows$value_fmt <- vapply(tbl_rows$value,
                                    function(v) .format_value(v, fmt),
                                    character(1))
      tbl_rows$pct     <- vapply(tbl_rows$value, pct, numeric(1))
      tbl_rows$pct_fmt <- ifelse(is.na(tbl_rows$pct), "—",
                                  sprintf("%.0f", tbl_rows$pct))

      # Anchor first; peers sorted by descending value
      anchor_ix   <- which(tbl_rows$action == "Anchor")
      other_ix    <- setdiff(seq_len(nrow(tbl_rows)), anchor_ix)
      other_order <- other_ix[order(-tbl_rows$value[other_ix])]
      tbl_rows    <- tbl_rows[c(anchor_ix, other_order), , drop = FALSE]

      table_tag <- tags$table(class = "dash-modal-table",
        tags$thead(tags$tr(
          tags$th("Status"),
          tags$th("School"),
          tags$th(class = "dt-center", "State"),
          tags$th(class = "dt-right",  "Value"),
          tags$th(class = "dt-right",
                  title = paste("Percentile in the ranked universe —",
                                 "e.g., 73 means this school's value is",
                                 "higher than 73% of ranked institutions",
                                 "on this metric. Higher number = higher",
                                 "value, not 'better' (acceptance rate,",
                                 "net price, etc. flip the interpretation)."),
                   "%ile")
        )),
        tags$tbody(lapply(seq_len(nrow(tbl_rows)), function(i) {
          a <- as.character(tbl_rows$action[i])
          slug <- tolower(gsub(" ", "-", a))
          tags$tr(
            tags$td(tags$span(class = sprintf("cohort-action-badge cohort-badge-%s",
                                                slug), a)),
            tags$td(tbl_rows$instnm[i]),
            tags$td(class = "dt-center", tbl_rows$state[i]),
            tags$td(class = "dt-right", tbl_rows$value_fmt[i]),
            tags$td(class = "dt-right", tbl_rows$pct_fmt[i])
          )
        }))
      )

      # Stash the metric for the Inspector hand-off below.
      session$userData$peer_dash_modal_metric <- metric

      showModal(modalDialog(
        title = tagList(
          tags$div(class = "dash-modal-title", dn),
          tags$div(class = "dash-modal-chips", chips)
        ),
        size = "l",
        easyClose = TRUE,
        fade = TRUE,
        footer = tagList(
          actionButton(ns("peer_dash_open_inspector"),
                        "Open in Inspector",
                        icon = icon("chart-area"),
                        class = "btn btn-outline-primary"),
          modalButton("Close")
        ),
        div(class = "dash-modal-body",
          tags$p(class = "dash-modal-desc", desc),
          tags$div(class = "dash-modal-strip-wrap", big_strip),
          tags$div(class = "dash-modal-legend",
            lapply(names(.PEER_DASH_ACTION_COLORS), function(a) {
              tags$span(class = "dash-modal-legend-item",
                tags$span(class = "dash-modal-legend-swatch",
                          style = sprintf("background: %s;",
                                           unname(.PEER_DASH_ACTION_COLORS[a]))),
                a)
            })
          ),
          tags$h6("Per-school values"),
          table_tag
        )
      ))
    })

    # Small reusable "needs-a-search" notice for the tabs that genuinely
    # require a peer result before they have anything to show.
    .needs_search_notice <- function(label) {
      div(class = "peer-tab-placeholder",
          tags$h6(label),
          p("This view summarizes the peer set. Run a search ",
            "in the sidebar — results will appear here automatically."),
          p(class = "text-muted",
            tags$small("The ", tags$strong("Inspector"),
                       " tab works standalone in the meantime; pick a ",
                       "variable to explore distributions against any ",
                       "comparison pool.")))
    }

    output$peer_dashboard <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(.needs_search_notice("Dashboard"))
      a_uid <- res$meta$anchor_unitid
      univ  <- peer_dashboard_universe()

      cards <- lapply(.PEER_DASHBOARD_METRICS, function(m) {
        if (!m %in% names(.SCHOOLS_WIDE)) return(NULL)
        var_row <- .VARIABLES[.VARIABLES$metric == m, , drop = FALSE]
        display_name <- if (nrow(var_row)) var_row$display_name[1] else m
        fmt          <- if (nrow(var_row)) var_row$format[1] else NA
        anchor_val <- .SCHOOLS_WIDE[[m]][match(a_uid, .SCHOOLS_WIDE$unitid)]
        rug_data   <- .peer_build_rug_data(m)
        univ_vals  <- univ[[m]]
        .peer_dashboard_card(m, anchor_val, rug_data, univ_vals,
                              display_name, fmt)
      })
      cards <- Filter(Negate(is.null), cards)
      div(class = "dash-grid", cards)
    })

    # ---- Inspector tab ---------------------------------------------------
    # Variable browser modeled on the Cohort Builder's inspector. Pick any
    # variable in the catalog; the histogram shows the chosen comparison
    # pool (ranked universe by default, optionally narrowed by US News
    # classification and/or sector), with the anchor as a tall purple line
    # and each peer as a rug marker. The per-school table below lists raw
    # values + each row's percentile within the chosen pool.
    #
    # Reuses the cohort module's visual conventions (.distribution-stats,
    # cohort-inspector-controls, etc.) so the two surfaces feel like the
    # same widget.

    # Variable choices grouped by category. Only metrics that exist in
    # .SCHOOLS_WIDE and have a display_name are offered.
    peer_inspector_choice_groups <- reactive({
      vars_df <- .VARIABLES %>%
        dplyr::filter(metric %in% names(.SCHOOLS_WIDE)) %>%
        dplyr::filter(!is.na(display_name))
      vars_df <- vars_df[order(vars_df$category, vars_df$display_name), ]
      groups <- split(vars_df, vars_df$category)
      lapply(groups, function(g) {
        v <- g$metric
        names(v) <- g$display_name
        v
      })
    })

    # Resolve the anchor unitid from either:
    #   - the latest search result (preferred — implies an active search),
    #   - or the sidebar's current anchor picker (lets the Inspector work
    #     before any search has been run).
    peer_inspector_anchor_uid <- reactive({
      res <- peer_result()
      if (!is.null(res) && !is.null(res$meta$anchor_unitid))
        return(res$meta$anchor_unitid)
      st <- tryCatch(sidebar_state$state(), error = function(e) NULL)
      if (!is.null(st) && !is.null(st$anchor_unitid))
        return(st$anchor_unitid)
      .DEFAULT_ANCHOR_UNITID
    })

    output$peer_inspector <- renderUI({
      res <- peer_result()
      no_search <- is.null(res)
      groups <- peer_inspector_choice_groups()
      class_choices <- {
        cls <- sort(unique(stats::na.omit(.SCHOOLS$usnews_classification)))
        v <- cls
        names(v) <- .prettify_classification(cls)
        v
      }
      sector_choices <- c("Public" = "public",
                          "Private (nonprofit)" = "private_nfp")

      lede <- if (no_search) {
        p(class = "peer-tab-lede text-muted",
          tags$small(tags$strong("Standalone mode."),
                     " No peer search has run yet — the Inspector is ",
                     "showing the sidebar's anchor against the comparison ",
                     "pool. Run a search to overlay the peer set as ",
                     "diamond markers."))
      } else {
        p(class = "peer-tab-lede text-muted",
          tags$small("Pick any variable to see how the peer set sits ",
                      "against a chosen comparison pool. Anchor shown as ",
                      "a tall purple line; peers as diamond markers along ",
                      "the x-axis."))
      }

      tagList(
        lede,

        div(class = "cohort-inspector-controls",
          div(class = "cohort-inspector-control-row",
            selectizeInput(ns("peer_inspect_metric"),
                           label = "Variable",
                           choices = groups,
                           selected = "total_enrollment_fall",
                           width = "100%",
                           options = list(placeholder = "Type to search variables"))
          ),
          div(class = "cohort-inspector-control-row cohort-pool-controls",
            div(class = "cohort-pool-control",
              selectizeInput(ns("peer_pool_classification"),
                             label = "Pool: US News classification (multi-select)",
                             choices = class_choices,
                             selected = character(0),
                             multiple = TRUE, width = "100%",
                             options = list(
                               placeholder = "(all classifications)",
                               plugins = list("remove_button")
                             ))
            ),
            div(class = "cohort-pool-control",
              selectizeInput(ns("peer_pool_sector"),
                             label = "Pool: Sector (multi-select)",
                             choices = sector_choices,
                             selected = character(0),
                             multiple = TRUE, width = "100%",
                             options = list(
                               placeholder = "(both sectors)",
                               plugins = list("remove_button")
                             ))
            )
          ),
          uiOutput(ns("peer_inspector_pool_description"))
        ),

        plotlyOutput(ns("peer_inspector_plot"), height = "420px"),
        uiOutput(ns("peer_inspector_stats")),
        h5("Per-school values"),
        DT::DTOutput(ns("peer_inspector_table"))
      )
    })

    # Comparison pool — ranked universe filtered by the inspector's class +
    # sector multi-selects. Empty selection = no filter on that field.
    peer_inspector_pool <- reactive({
      pool <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$in_ranked_universe %in% TRUE, ,
                             drop = FALSE]
      cls <- input$peer_pool_classification
      sec <- input$peer_pool_sector
      if (length(cls))
        pool <- pool[pool$usnews_classification %in% cls, , drop = FALSE]
      if (length(sec))
        pool <- pool[pool$control_grp %in% sec, , drop = FALSE]
      pool
    })

    output$peer_inspector_pool_description <- renderUI({
      pool <- peer_inspector_pool()
      cls <- input$peer_pool_classification
      sec <- input$peer_pool_sector
      parts <- c()
      if (length(cls))
        parts <- c(parts, sprintf("US News: %s",
                                   paste(.prettify_classification(cls),
                                         collapse = ", ")))
      if (length(sec))
        parts <- c(parts, sprintf("Sector: %s",
                                   paste(.prettify_control(sec),
                                         collapse = ", ")))
      base <- if (length(parts))
                sprintf("Pool: %s (%s schools)",
                        paste(parts, collapse = " · "),
                        format(nrow(pool), big.mark = ","))
              else
                sprintf("Pool: Ranked universe (%s schools)",
                        format(nrow(pool), big.mark = ","))
      tags$div(class = "cohort-inspector-pool-desc",
        tags$small(base))
    })

    # Color palette — two categories only: Anchor + Peer.
    .PEER_INSPECTOR_COLORS <- c("Anchor" = "#602D89",
                                  "Peer"   = "#AC9E94")

    # ---- Inspector plot ----
    output$peer_inspector_plot <- renderPlotly({
      metric <- input$peer_inspect_metric; req(metric)
      req(metric %in% names(.SCHOOLS_WIDE))
      a_uid <- peer_inspector_anchor_uid(); req(a_uid)
      res <- peer_result()
      peer_uids <- if (!is.null(res)) res$peers$unitid else integer(0)

      pool_df   <- peer_inspector_pool()
      pool_vals <- pool_df[[metric]]
      pool_vals <- pool_vals[is.finite(pool_vals)]
      validate(need(length(pool_vals) >= 5,
                    "Not enough finite values to plot a distribution."))

      a_val       <- .SCHOOLS_WIDE[[metric]][.SCHOOLS_WIDE$unitid == a_uid][1]
      anchor_name <- .SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1]

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA
      x_label <- if (nrow(meta_row) && !is.na(meta_row$display_name))
                   meta_row$display_name else metric

      iqr <- diff(stats::quantile(pool_vals, c(0.25, 0.75),
                                   na.rm = TRUE, names = FALSE))
      bw  <- max(2 * iqr / length(pool_vals)^(1/3),
                 diff(range(pool_vals)) / 40)

      x_hover_fmt <- switch(
        as.character(fmt) %||% "",
        currency   = "$%{x:,.0f}",
        percentage = "%{x:.1f}%",
        count      = "%{x:,.0f}",
        ratio      = "%{x:.2f}",
        "%{x:.4g}"
      )

      pool_label <- if (length(input$peer_pool_classification) ||
                         length(input$peer_pool_sector))
                       "Selected pool" else "Ranked universe"

      p <- plot_ly() %>%
        add_histogram(
          x    = pool_vals,
          name = pool_label,
          xbins = list(start = min(pool_vals),
                       end   = max(pool_vals) + bw,
                       size  = bw),
          marker = list(color = "#F4EDEC",
                        line  = list(color = "#AC9E94", width = 0.5)),
          hovertemplate = paste0(
            "<b>Pool bin</b><br>Around ", x_hover_fmt,
            ": %{y} institutions<extra></extra>")
        )

      # Peer markers
      peer_vals  <- .SCHOOLS_WIDE[[metric]][match(peer_uids,
                                                    .SCHOOLS_WIDE$unitid)]
      peer_names <- .SCHOOLS$instnm[match(peer_uids, .SCHOOLS$unitid)]
      ok <- is.finite(peer_vals)
      if (any(ok)) {
        p <- p %>% add_markers(
          x = peer_vals[ok],
          y = rep(0, sum(ok)),
          name = "Peer",
          text = peer_names[ok],
          marker = list(symbol = "diamond", size = 10,
                        color = .PEER_INSPECTOR_COLORS[["Peer"]],
                        line = list(color = "#FFFFFF", width = 1)),
          hovertemplate = paste0("<b>%{text}</b><br>",
                                  x_label, ": ", x_hover_fmt,
                                  "<extra></extra>")
        )
      }

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
          bgcolor = "#251230", bordercolor = "#251230",
          font = list(color = "#FFFFFF", size = 12),
          xshift = 4, yshift = 2
        )))
      }

      p %>%
        layout(
          xaxis  = list(title = x_label, gridcolor = "#F4EDEC",
                        zeroline = FALSE),
          yaxis  = list(title = "Number of institutions",
                        gridcolor = "#F4EDEC"),
          shapes = shapes,
          annotations = annots
        ) %>%
        cohc_plotly_theme(hovermode = "closest") %>%
        cohc_modebar(filename_root = "peer_inspector")
    })

    # ---- Inspector summary stats ----
    output$peer_inspector_stats <- renderUI({
      metric <- input$peer_inspect_metric; req(metric)
      req(metric %in% names(.SCHOOLS_WIDE))
      a_uid <- peer_inspector_anchor_uid(); req(a_uid)
      res <- peer_result()
      peer_uids <- if (!is.null(res)) res$peers$unitid else integer(0)

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA

      a_val      <- .SCHOOLS_WIDE[[metric]][.SCHOOLS_WIDE$unitid == a_uid][1]
      pool_df    <- peer_inspector_pool()
      pool_vals  <- pool_df[[metric]]; pool_vals <- pool_vals[is.finite(pool_vals)]
      peer_vals  <- .SCHOOLS_WIDE[[metric]][match(peer_uids,
                                                    .SCHOOLS_WIDE$unitid)]
      peer_vals  <- peer_vals[is.finite(peer_vals)]

      pct_anchor <- if (is.finite(a_val) && length(pool_vals))
                       sprintf("%.0fth", 100 * mean(pool_vals < a_val))
                     else "—"

      tags$dl(class = "distribution-stats",
        tags$dt("Anchor"),
        tags$dd(sprintf("%s  (%s pct.)",
                        .format_value(a_val, fmt), pct_anchor)),
        tags$dt("Peer median"),
        tags$dd(if (length(peer_vals))
                  .format_value(stats::median(peer_vals), fmt) else "—"),
        tags$dt("Peer range"),
        tags$dd(if (length(peer_vals))
                  sprintf("%s to %s",
                          .format_value(min(peer_vals), fmt),
                          .format_value(max(peer_vals), fmt))
                else "—"),
        tags$dt("Peer N reporting"),
        tags$dd(sprintf("%d of %d", length(peer_vals), length(peer_uids))),
        tags$dt("Pool N"),
        tags$dd(format(length(pool_vals), big.mark = ","))
      )
    })

    # ---- Inspector per-school table ----
    output$peer_inspector_table <- DT::renderDT({
      metric <- input$peer_inspect_metric; req(metric)
      req(metric %in% names(.SCHOOLS_WIDE))
      a_uid <- peer_inspector_anchor_uid(); req(a_uid)
      res <- peer_result()
      peer_uids <- if (!is.null(res)) res$peers$unitid else integer(0)

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA

      uids    <- c(a_uid, peer_uids)
      actions <- c("Anchor", rep("Peer", length(peer_uids)))
      names_v <- .SCHOOLS$instnm[match(uids, .SCHOOLS$unitid)]
      states  <- .SCHOOLS$stabbr[match(uids, .SCHOOLS$unitid)]
      raw_vals <- .SCHOOLS_WIDE[[metric]][match(uids, .SCHOOLS_WIDE$unitid)]

      pool_df   <- peer_inspector_pool()
      pool_vals <- pool_df[[metric]]; pool_vals <- pool_vals[is.finite(pool_vals)]
      pct <- vapply(raw_vals, function(v) {
        if (!is.finite(v) || !length(pool_vals)) return(NA_real_)
        100 * mean(pool_vals < v)
      }, numeric(1))

      # Value + Percentile are formatted strings; wrap each in a
      # data-order span so DT sorts by the underlying numeric value
      # when the user clicks the column header (without changing the
      # rendered text). NA -> sentinel data-order so NAs sink to the
      # bottom of either sort direction.
      val_display <- vapply(raw_vals, function(v) .format_value(v, fmt),
                             character(1))
      val_html <- ifelse(
        is.finite(raw_vals),
        sprintf('<span data-order="%g">%s</span>',
                raw_vals,
                vapply(val_display, htmltools::htmlEscape, character(1))),
        '<span data-order="-1e15">&#8212;</span>'
      )
      pct_html <- ifelse(
        is.na(pct),
        '<span data-order="-1e15">&#8212;</span>',
        sprintf('<span data-order="%g">%.0f</span>', pct, pct)
      )

      tbl <- data.frame(
        Action      = actions,
        School      = names_v,
        State       = states,
        Value       = val_html,
        Percentile  = pct_html,
        `_sort`     = ifelse(is.finite(raw_vals), raw_vals, -Inf),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )

      DT::datatable(
        tbl,
        rownames = FALSE,
        selection = "none",
        # escape = FALSE lets the Value/Percentile data-order span
        # wrappers render as real HTML so DT picks up the sort hint.
        # Action / School / State are simple text; harmless to leave
        # them in the unescaped set.
        escape = FALSE,
        options = list(
          pageLength = 50,
          dom = "tip",
          order = list(list(5, "desc")),
          columnDefs = list(
            list(visible = FALSE, targets = 5),
            list(className = "dt-right", targets = c(3, 4)),
            list(className = "dt-center", targets = 2)
          )
        ),
        class = "compact stripe hover"
      ) %>%
        DT::formatStyle(
          "Action",
          target = "cell",
          color = DT::styleEqual(
            c("Anchor", "Peer"),
            c("#602D89", "#AC9E94")
          ),
          fontWeight = "600"
        )
    })

    # ---- Dashboard modal "Open in inspector" hand-off --------------------
    # Convenience: when the user is viewing a metric in the dashboard
    # click-to-modal, give them a one-click jump to the Inspector tab
    # with the metric pre-selected.
    observeEvent(input$peer_dash_open_inspector, {
      m <- session$userData$peer_dash_modal_metric
      if (is.null(m)) return()
      updateSelectizeInput(session, "peer_inspect_metric", selected = m)
      updateTabsetPanel(session, "analysis_nav", selected = "inspector")
      removeModal()
    })

    # ---- Composition tab: 9 representation bars --------------------------
    # For each categorical dimension, show the breakdown of the peer set
    # as a stack of small horizontal bars (one per category). The anchor's
    # own category is starred and tinted so the user sees at a glance
    # "what camp does this peer set sit in vs. the anchor."
    #
    # Each dim entry is a list with:
    #   label    : card title
    #   accessor : function(.SCHOOLS row subset) -> character vector of
    #              category keys (one per school, NA for missing)
    #   labeler  : function(key) -> pretty label for display
    # Defensive helper: pull a column as character; fall back to NA when
    # the column is absent. Always returns length == nrow(df).
    .col_or_na <- function(df, col) {
      if (!col %in% names(df)) return(rep(NA_character_, nrow(df)))
      as.character(df[[col]])
    }

    # Five-card layout — focused on the dimensions that change most
    # peer-to-peer and where the labels are short enough to not truncate
    # in the side-by-side bar layout. Earlier 9-card version cut off
    # things like "Special Focus: Arts and Sciences" and
    # "Lower Access, Higher Earnings".
    .PEER_COMPOSITION_DIMS <- list(
      list(label    = "US News classification",
           accessor = function(df) .col_or_na(df, "usnews_classification"),
           labeler  = function(v) {
             out <- .prettify_classification(v)
             if (length(out) != length(v)) v else as.character(out)
           }),
      list(label    = "Institution size (Carnegie)",
           accessor = function(df) .col_or_na(df, "ic2025size_label"),
           labeler  = function(v) as.character(v)),
      list(label    = "Geographic region",
           accessor = function(df) {
             top <- c("northeast", "midwest", "south", "west")
             st_v <- .col_or_na(df, "stabbr")
             vapply(st_v, function(st) {
               if (is.na(st)) return(NA_character_)
               for (k in top) if (st %in% .REGIONS[[k]]) return(k)
               NA_character_
             }, character(1), USE.NAMES = FALSE)
           },
           labeler  = function(v) {
             keys <- c("northeast","midwest","south","west")
             pretty <- c("Northeast","Midwest","South","West")
             m <- match(v, keys)
             out <- pretty[m]
             ifelse(is.na(out), "(unknown)", out)
           }),
      list(label    = "Carnegie Research Activity",
           accessor = function(df) .col_or_na(df, "research2025_label"),
           labeler  = function(v) as.character(v)),
      list(label    = "Athletics division",
           accessor = function(df) .col_or_na(df, "athletics_division"),
           labeler  = function(v) {
             vapply(v, function(x) {
               if (is.na(x)) return("(no athletics)")
               switch(as.character(x),
                      D1 = "NCAA Division I",
                      D2 = "NCAA Division II",
                      D3 = "NCAA Division III",
                      NAIA = "NAIA",
                      as.character(x))
             }, character(1), USE.NAMES = FALSE)
           })
    )

    # Coerce a labeler return value into a single-string label, defensively.
    # Returns the fallback (usually the raw key) when the labeler returns
    # NULL, an empty vector, multiple values, NA, or an empty string.
    .label_or_key <- function(labeler, key) {
      lbl <- tryCatch(labeler(key), error = function(e) NULL)
      if (is.null(lbl) || length(lbl) == 0) return(as.character(key))
      lbl <- unname(lbl)[1]
      if (is.na(lbl) || !nzchar(lbl)) return(as.character(key))
      as.character(lbl)
    }

    # Build a per-dimension breakdown for the current peer set.
    # Returns a data.frame with $key, $label, $n, $pct, $is_anchor_cat.
    .peer_dim_breakdown <- function(dim, peer_df, anchor_row) {
      vals_raw <- tryCatch(dim$accessor(peer_df),
                            error = function(e) rep(NA_character_,
                                                     nrow(peer_df)))
      # Force character + length match, defensively
      if (length(vals_raw) != nrow(peer_df)) {
        vals_raw <- rep(NA_character_, nrow(peer_df))
      }
      vals <- as.character(vals_raw)

      a_val_raw <- if (nrow(anchor_row))
                     tryCatch(dim$accessor(anchor_row),
                              error = function(e) NA_character_)
                   else NA_character_
      a_val <- if (length(a_val_raw) == 0) NA_character_
               else as.character(a_val_raw[1])

      vals_for_tab <- ifelse(is.na(vals), "(missing)", vals)
      n_total <- length(vals_for_tab)
      if (!n_total) {
        return(data.frame(key = character(0), n = integer(0),
                          pct = numeric(0), label = character(0),
                          is_anchor_cat = logical(0),
                          stringsAsFactors = FALSE))
      }
      # NB: stringsAsFactors is NOT a table() argument — table() treats
      # every named ... as another variable to cross-tabulate, so passing
      # stringsAsFactors=FALSE there made R try to tabulate vals_for_tab
      # (length N) against FALSE (length 1), triggering "all arguments
      # must have the same length". stringsAsFactors only goes on the
      # outer as.data.frame() call.
      tab_raw <- as.data.frame(table(key = vals_for_tab),
                                stringsAsFactors = FALSE)
      tab <- data.frame(key = as.character(tab_raw$key),
                         n   = as.integer(tab_raw$Freq),
                         stringsAsFactors = FALSE)
      tab <- tab[order(-tab$n), , drop = FALSE]
      tab$pct <- tab$n / n_total
      tab$label <- vapply(tab$key, function(k) {
        if (identical(k, "(missing)")) return("(missing)")
        .label_or_key(dim$labeler, k)
      }, character(1))
      a_val_str <- if (is.na(a_val)) "" else as.character(a_val)
      tab$is_anchor_cat <- tab$key == a_val_str
      tab
    }

    # Render a single dimension card.
    .peer_composition_card <- function(dim, peer_df, anchor_row) {
      n_total <- nrow(peer_df)
      brk <- .peer_dim_breakdown(dim, peer_df, anchor_row)
      a_val_raw <- if (nrow(anchor_row))
                     tryCatch(dim$accessor(anchor_row),
                              error = function(e) NA_character_)
                   else NA_character_
      a_val <- if (length(a_val_raw) == 0) NA_character_
               else as.character(a_val_raw[1])
      anchor_label <- if (is.na(a_val))
                        "(anchor missing on this dimension)"
                      else .label_or_key(dim$labeler, a_val)

      rows <- if (nrow(brk)) lapply(seq_len(nrow(brk)), function(i) {
        b <- brk[i, ]
        bar_pct <- sprintf("%.0f%%", 100 * b$pct)
        is_anchor <- isTRUE(b$is_anchor_cat)
        # Stacked layout: label + stats on the top line (label takes
        # the room it needs, stats hug right). Bar fills the full card
        # width below, so no inner column constraint can chop long
        # category names like "National Liberal Arts Colleges".
        tags$div(class = paste("peer-comp-row",
                                if (is_anchor) "peer-comp-row-anchor" else ""),
          tags$div(class = "peer-comp-row-header",
            tags$div(class = "peer-comp-row-label",
                      title = as.character(b$label),
              if (is_anchor) HTML("&#9733; ") else NULL,
              b$label),
            tags$div(class = "peer-comp-row-stats",
                      sprintf("%d  (%s)", b$n, bar_pct))
          ),
          tags$div(class = "peer-comp-row-bar",
            tags$div(class = "peer-comp-row-bar-fill",
                     style = sprintf("width: %.1f%%;", 100 * b$pct)))
        )
      }) else list(tags$div(class = "text-muted",
                              tags$small("No data on this dimension.")))

      tags$div(class = "peer-comp-card",
        tags$div(class = "peer-comp-card-title", dim$label),
        tags$div(class = "peer-comp-card-anchor",
                  tags$span(class = "peer-comp-card-anchor-label", "Anchor:"),
                  tags$span(class = "peer-comp-card-anchor-val",
                             anchor_label)),
        tags$div(class = "peer-comp-rows", rows),
        tags$div(class = "peer-comp-card-n",
                  sprintf("Based on %d peers", n_total))
      )
    }

    output$peer_composition <- renderUI({
      res <- peer_result()
      if (is.null(res)) return(.needs_search_notice("Composition"))
      a_uid <- res$meta$anchor_unitid
      peer_uids <- res$peers$unitid
      peer_df    <- .SCHOOLS[match(peer_uids, .SCHOOLS$unitid), , drop = FALSE]
      anchor_row <- .SCHOOLS[.SCHOOLS$unitid == a_uid, , drop = FALSE]

      # Each card rendered under tryCatch so a single bad dimension shows
      # a small error notice instead of blowing up the whole pane.
      cards <- lapply(.PEER_COMPOSITION_DIMS, function(d) {
        tryCatch(.peer_composition_card(d, peer_df, anchor_row),
                 error = function(e) {
                   tags$div(class = "peer-comp-card",
                     tags$div(class = "peer-comp-card-title", d$label),
                     tags$div(class = "text-muted",
                       tags$small(sprintf("Could not render: %s",
                                            conditionMessage(e))))
                   )
                 })
      })
      div(class = "peer-comp-grid", cards)
    })

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
      # Tab strip is always rendered. The Inspector tab is usable
      # standalone (uses the sidebar's anchor as the reference + the
      # ranked universe as the comparison pool). Other tabs need a peer
      # set; their bodies show a "run a search" placeholder via the
      # individual renderUI/renderPlotly/renderDT bindings until then.

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
              div(class = "peer-composition-tab",
                  p(class = "peer-tab-lede text-muted",
                    tags$small("How the peer set breaks down on five ",
                                "categorical dimensions. Anchor's category ",
                                "is starred (★) and highlighted in each card.")),
                  uiOutput(ns("peer_composition")))
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
              div(class = "peer-dashboard-tab",
                  p(class = "peer-tab-lede text-muted",
                    tags$small("11 headline metrics for the peer set. ",
                                "Each card shows the ranked-universe ",
                                "distribution, every peer as a rug tick, ",
                                "and the anchor as a tall purple line.")),
                  uiOutput(ns("peer_dashboard")))
            ),

            tabPanel(
              title = "Inspector",
              value = "inspector",
              uiOutput(ns("peer_inspector"))
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

      # Mahalanobis-specific diagnostic block — only rendered when the
      # user picked that metric (or it fell back from it). Shows the
      # numerical-stability indicators (covariance condition number,
      # eigenvalue spectrum, effective rank) plus a callout that theme
      # weights are mathematically inert under Mahalanobis.
      mah_block <- if (!is.null(m$mahalanobis_diagnostics)) {
        mdg <- m$mahalanobis_diagnostics
        .fmt <- function(x, d = 2) {
          if (is.null(x) || !is.finite(x)) return("—")
          if (abs(x) >= 1e4 || (abs(x) > 0 && abs(x) < 1e-2))
            formatC(x, format = "e", digits = 2)
          else formatC(x, format = "f", digits = d)
        }
        cond_band <- if (!is.finite(mdg$condition_number)) "singular"
                     else if (mdg$condition_number < 1e3)  "well-conditioned"
                     else if (mdg$condition_number < 1e6)  "marginal"
                     else                                   "ill-conditioned"
        tagList(
          h5("Mahalanobis numerics"),
          p(class = "text-muted",
            tags$small(
              "Mahalanobis adjusts distance for variable correlation. ",
              "These numbers show whether the candidate-pool covariance ",
              "matrix is well-behaved enough to make that adjustment ",
              "reliable. Big condition numbers, lots of near-zero ",
              "eigenvalues, or negative eigenvalues all mean Mahalanobis ",
              "is amplifying noise — switch back to Euclidean.")),
          tags$div(class = "mah-diag-grid",
            tags$div(class = "mah-diag-card",
              tags$div(class = "mah-diag-label", "Condition number"),
              tags$div(class = "mah-diag-value", .fmt(mdg$condition_number)),
              tags$div(class = "mah-diag-band", cond_band)),
            tags$div(class = "mah-diag-card",
              tags$div(class = "mah-diag-label", "Effective rank"),
              tags$div(class = "mah-diag-value",
                       sprintf("%s / %d",
                               .fmt(mdg$effective_rank, 0),
                               mdg$n_vars %||% mdg$n_active_dims %||% 0L))),
            tags$div(class = "mah-diag-card",
              tags$div(class = "mah-diag-label", "Negative eigenvalues"),
              tags$div(class = "mah-diag-value",
                       .fmt(mdg$n_negative_eigs, 0)),
              tags$div(class = "mah-diag-band",
                if (isTRUE(mdg$n_negative_eigs > 0)) "pairwise-NA artefact" else "")),
            tags$div(class = "mah-diag-card",
              tags$div(class = "mah-diag-label", "Eigenvalue range"),
              tags$div(class = "mah-diag-value",
                       sprintf("%s — %s",
                               .fmt(mdg$eigen_min), .fmt(mdg$eigen_max)))),
            tags$div(class = "mah-diag-card",
              tags$div(class = "mah-diag-label", "Peer distance median"),
              tags$div(class = "mah-diag-value",
                       .fmt(mdg$pool_distance_median %||% NA_real_)),
              tags$div(class = "mah-diag-band",
                sprintf("expected ~ sqrt(active dims) = %s",
                        .fmt(sqrt(mdg$n_active_dims %||% NA_real_), 1)))),
            tags$div(class = "mah-diag-card",
              tags$div(class = "mah-diag-label", "Peer distance max"),
              tags$div(class = "mah-diag-value",
                       .fmt(mdg$pool_distance_max %||% NA_real_)))
          ),
          if (isTRUE(mdg$singular_fallback))
            tags$div(class = "mah-diag-alert",
              tags$strong("Fallback: "),
              "the covariance matrix was singular, so the ranking you see ",
              "above actually used weighted Euclidean. Drop a few highly-",
              "correlated variables via the variable overrides modal, or ",
              "switch back to Euclidean explicitly."),
          # Eigenvalue spectrum plot. Shows the dropoff from largest to
          # smallest eigenvalue on a log scale — a steep cliff means a
          # near-collinear bundle of variables is dominating the inverse
          # covariance and inflating distances.
          if (!is.null(mdg$eigenvalues)) tagList(
            tags$h6(class = "mah-diag-subhead",
                    "Eigenvalue spectrum"),
            p(class = "text-muted",
              tags$small(
                "Each bar is one eigenvalue of the candidate-pool ",
                "covariance matrix, sorted largest to smallest on a ",
                "log10 axis. A steep cliff at the right end is what ",
                "drives the condition-number problem: those tiny ",
                "eigenvalues get inverted to huge numbers and dominate ",
                "the Mahalanobis distance.")),
            plotOutput(ns("mah_eigen_plot"), height = "220px")
          ),
          # "Who's making it unstable?" — variables with the largest
          # absolute loading on the SMALLEST eigendirection. They form
          # the near-collinear bundle. Removing any one usually drops
          # the condition number by orders of magnitude.
          if (!is.null(mdg$smallest_direction_loadings) &&
              nrow(mdg$smallest_direction_loadings) > 0) tagList(
            tags$h6(class = "mah-diag-subhead",
                    "Top variables on the smallest eigendirection"),
            p(class = "text-muted",
              tags$small(
                "The smallest eigendirection is the linear combination ",
                "of variables that has the smallest variance in the ",
                "pool — i.e., a near-collinear bundle. These variables ",
                "have the largest weights in that combination. Excluding ",
                "one of them (uncheck or set weight to 0 via the variable ",
                "overrides modal) usually drops the condition number by ",
                "several orders of magnitude.")),
            DT::DTOutput(ns("mah_loadings_table"))
          ),
          tags$div(class = "mah-diag-note",
            tags$strong("Heads up: "),
            mdg$theme_weights_active_note %||% ""),
          tags$br()
        )
      } else NULL

      tagList(
        tags$hr(class = "peer-section-divider"),
        h4("Diagnostics"),
        p(class = "section-intro", summary_text),
        mah_block,

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

    # ---- Diagnostics: Mahalanobis eigenvalue spectrum ----
    # Sorted-descending bar chart on log10 axis. The "cliff" at the
    # right end tells the user how many directions are near-collinear
    # — those are the ones blowing up the inverse covariance.
    output$mah_eigen_plot <- renderPlot({
      res <- peer_result()
      req(res)
      mdg <- res$meta$mahalanobis_diagnostics
      req(!is.null(mdg), !is.null(mdg$eigenvalues))
      ev <- mdg$eigenvalues
      df <- data.frame(
        idx = seq_along(ev),
        # Plot |λ| on log10 so the floor is visible; negative eigenvalues
        # (if any) are marked separately via fill color.
        absev = pmax(abs(ev), 1e-12),
        sign  = ifelse(ev < 0, "negative", "positive"),
        stringsAsFactors = FALSE
      )
      tol_line <- 1e-10 * max(df$absev)
      ggplot2::ggplot(df, ggplot2::aes(x = idx, y = absev, fill = sign)) +
        ggplot2::geom_col(width = 0.8) +
        ggplot2::geom_hline(yintercept = tol_line,
                            linetype = "dashed",
                            color = "#AC9E94",
                            linewidth = 0.4) +
        ggplot2::annotate("text", x = max(df$idx), y = tol_line,
                          label = "numerical-zero floor",
                          vjust = -0.4, hjust = 1, size = 3,
                          color = "#7A6E66") +
        ggplot2::scale_y_log10(
          labels = function(v) formatC(v, format = "e", digits = 1)) +
        ggplot2::scale_fill_manual(
          values = c(positive = "#602D89", negative = "#C44"),
          guide  = "none") +
        ggplot2::labs(x = "Eigenvalue index (largest -> smallest)",
                      y = "|eigenvalue|  (log10)") +
        ggplot2::theme_minimal(base_size = 10) +
        ggplot2::theme(
          panel.grid.major.x = ggplot2::element_blank(),
          panel.grid.minor   = ggplot2::element_blank(),
          plot.margin = ggplot2::margin(4, 6, 4, 4)
        )
    })

    # ---- Diagnostics: Mahalanobis smallest-eigendirection loadings ----
    # Compact 3-column table (Variable | Loading | % of bundle). Use
    # the same display-name + theme lookup as the weights table so the
    # user sees familiar labels, not raw metric IDs.
    output$mah_loadings_table <- DT::renderDT({
      res <- peer_result()
      req(res)
      mdg <- res$meta$mahalanobis_diagnostics
      req(!is.null(mdg), !is.null(mdg$smallest_direction_loadings))
      df <- mdg$smallest_direction_loadings
      labels <- .VARIABLES$display_name[match(df$metric, .VARIABLES$metric)]
      labels <- ifelse(is.na(labels), df$metric, labels)
      themes <- vapply(df$metric, .var_theme, character(1))
      out <- data.frame(
        Variable = labels,
        Metric   = df$metric,
        Theme    = ifelse(is.na(themes), "(unassigned)",
                          .theme_label(themes)),
        Loading  = round(df$loading, 3),
        `% of bundle` = sprintf("%.1f%%", df$pct),
        check.names      = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        out,
        rownames = FALSE,
        options  = list(
          pageLength = 10, dom = "t",
          ordering   = FALSE,
          columnDefs = list(
            list(className = "dt-right", targets = c(3, 4))
          )
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
        # Use .theme_label() so multi-word theme keys ("student_body")
        # render as "Student body" instead of "Student_body".
        Theme    = ifelse(is.na(themes), "(unassigned)",
                          .theme_label(themes)),
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

      # Keep Coverage numeric so DT sorts by value. formatPercentage()
      # below paints the "%" symbol at render time without losing the
      # underlying numeric type — string-sort bugs avoided.
      df <- data.frame(
        Variable = labels,
        Metric   = d$metric,
        Coverage = as.numeric(d$coverage),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        df,
        rownames = FALSE,
        options  = list(pageLength = 10, dom = "tip"),
        class    = "compact stripe"
      ) |>
        DT::formatPercentage("Coverage", digits = 1)
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
      # slider above the main K — or flips on the "Search wider universe"
      # checkbox — fetch a wider candidate set via the cached peer
      # compute (free if same args were used before).
      #
      # Universe mode REPLACES the sidebar's candidate_pool with
      # `list(in_ranked_universe = TRUE)` so the result is drawn from
      # every ranked institution rather than the user's narrower main
      # search filters. The aspirant logic still applies on top.
      st     <- isolate(sidebar_state$state())
      pool_k <- input$aspirant_pool_k %||% nrow(res$peers)
      universe <- isTRUE(input$aspirant_universe)
      candidate_pool_used <- if (universe)
                               list(in_ranked_universe = TRUE)
                             else st$candidate_pool
      if (universe ||
          (is.finite(pool_k) && pool_k != nrow(res$peers))) {
        bigger <- tryCatch(
          compute_peers_cached(
            anchor_unitid    = a_uid,
            candidate_pool   = candidate_pool_used,
            theme_weights    = st$theme_weights,
            variable_weights = st$variable_weights %||% list(),
            distance_metric  = if (isTRUE(st$mahalanobis)) "mahalanobis"
                               else (st$distance_metric %||% "euclidean"),
            k                = as.integer(pool_k)
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
      if (is.null(res)) return(.needs_search_notice("Aspirant refinement"))

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
                          min = 5, max = 1000,
                          value = main_k, step = 5, ticks = FALSE),
              checkboxInput(ns("aspirant_universe"),
                            label = "Search wider universe",
                            value = FALSE),
              tags$small(class = "peer-refine-help text-muted",
                "When checked, aspirants are drawn from the full ranked ",
                "universe (ignoring this search's classification / sector ",
                "/ state filters) so you can discover schools far outside ",
                "your current peer pool. Use the slider to cap how many ",
                "closest matches are evaluated for the aspirational ",
                "comparison.")
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
      # Render the Add column as plain text "+ Add" — no inline onclick.
      # The click handler lives at the table level via input$..._cell_clicked
      # (cell_clicked is unaffected by row-selection swallowing the click).
      cols <- list(
        Rank     = df$rank,
        School   = df$instnm,
        State    = df$stabbr,
        Distance = round(df$distance, 3),
        Add      = rep('<span class="peer-add-btn">+ Add</span>', nrow(df))
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
          # NA value: sentinel sort-order so it sinks to the bottom on
          # both ascending and descending sorts (no real value beats
          # 1e15).
          if (!is.finite(v))
            return('<span data-order="1e15">&#8212;</span>')
          gap <- v - a_val
          beats <- if (dir == "higher") gap > 0 else gap < 0
          arrow <- if (is.na(beats)) ""
                   else if (beats) "<span class=\"asp-up\">&#9650;</span>"
                   else            "<span class=\"asp-down\">&#9660;</span>"
          display_text <- sprintf("%s  %s",
                                   .format_value(v, fmt),
                                   paste0(arrow, " ",
                                           sprintf("%+s",
                                                   .format_value(abs(gap), fmt))))
          # data-order = the raw numeric value so DT sorts by metric
          # value, not by string-of-formatted-text.
          sprintf('<span data-order="%g">%s</span>', v, display_text)
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
                         list(className = "dt-center", targets = c(2, 4)),
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

    # Aspirant table click discriminator.
    #   - Clicking the Add cell -> push the school to the curated main list
    #   - Clicking any other cell -> open the aspirational-gap modal
    # cell_clicked fires reliably regardless of DT row-selection, where the
    # row_selected event was being consumed by the gap-modal handler before
    # our inline onclick could run.
    .aspirant_cell_click <- function(source_tbl, payload, dfn) {
      ar <- aspirant_filter(); req(ar, nrow(dfn) > 0)
      if (is.null(payload) || is.null(payload$row)) return()
      row <- payload$row
      val <- payload$value %||% ""
      if (grepl("peer-add-btn", val, fixed = TRUE)) {
        rec  <- dfn[row, , drop = FALSE]
        uid  <- as.integer(rec$unitid[1])
        dist <- if (is.finite(rec$distance[1])) as.numeric(rec$distance[1])
                else NA_real_
        message(sprintf("[peer-add] aspirant click row=%d uid=%d dist=%s",
                        row, uid, dist))
        .add_school_to_main(uid, "Aspirant", dist)
        showNotification(
          tagList(tags$strong("Added: "),
                  .SCHOOLS$instnm[match(uid, .SCHOOLS$unitid)],
                  tags$br(),
                  tags$small("Source: Aspirant")),
          type = "message", duration = 3)
      } else {
        .open_aspirant_modal(dfn[row, , drop = FALSE],
                              ar$anchor_values, ar$aspirant_metrics)
      }
      DT::dataTableProxy(source_tbl) %>% DT::selectRows(NULL)
    }
    observeEvent(input$aspirant_strict_tbl_cell_clicked, {
      ar <- aspirant_filter(); req(ar, nrow(ar$strict) > 0)
      .aspirant_cell_click("aspirant_strict_tbl",
                            input$aspirant_strict_tbl_cell_clicked,
                            ar$strict)
    })
    observeEvent(input$aspirant_near_tbl_cell_clicked, {
      ar <- aspirant_filter(); req(ar, nrow(ar$near_miss) > 0)
      .aspirant_cell_click("aspirant_near_tbl",
                            input$aspirant_near_tbl_cell_clicked,
                            ar$near_miss)
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
      if (is.null(res)) return(.needs_search_notice("Stratified expansion"))
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
                anchor_unitid    = a_uid,
                candidate_pool   = pool,
                theme_weights    = st$theme_weights,
                variable_weights = st$variable_weights %||% list(),
                distance_metric  = if (isTRUE(st$mahalanobis))
                                     "mahalanobis" else "euclidean",
                k                = per_value_k
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
          # Source tag for "Add" — "Stratified: <label>" e.g. "Stratified: D1"
          src_tag <- sprintf("Stratified: %s",
                              if (is.na(s$label)) as.character(s$value)
                              else as.character(s$label))
          # Escape single quotes in src_tag for inlined JS (defensive)
          src_tag_js <- gsub("'", "\\\\'", src_tag, fixed = TRUE)
          rows_html <- paste(
            vapply(seq_len(nrow(peers_df)), function(i) {
              uid <- as.integer(peers_df$unitid[i])
              dist <- if (is.finite(peers_df$distance[i]))
                        sprintf("%.6f", peers_df$distance[i]) else "null"
              add_btn <- sprintf(paste0(
                "<a href='#' class='peer-add-btn peer-add-btn-mini' ",
                "title='Add to main list' ",
                "onclick=\"event.stopPropagation();Shiny.setInputValue('%s', ",
                "{unitid: %d, source: '%s', distance: %s, t: Date.now()}, ",
                "{priority: 'event'});return false;\">+</a>"),
                ns("peer_add_click"), uid, src_tag_js, dist)
              sprintf("<tr><td>%d</td><td>%s</td><td class='dt-center'>%s</td><td class='dt-right'>%.3f</td><td class='dt-center'>%s</td></tr>",
                      peers_df$rank[i],
                      htmltools::htmlEscape(peers_df$instnm[i]),
                      htmltools::htmlEscape(peers_df$stabbr[i]),
                      peers_df$distance[i],
                      add_btn)
            }, character(1)),
            collapse = ""
          )
          HTML(sprintf(
            "<table class='peer-strat-card-table'><thead><tr><th>#</th><th>School</th><th class='dt-center'>State</th><th class='dt-right'>Dist.</th><th class='dt-center'>Add</th></tr></thead><tbody>%s</tbody></table>",
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
    # When a saved search is restored, sessionServer pushes the curated
    # state into restore_curated_signal; apply it AFTER the search re-runs.
    # (See app.R for the wiring.)

    list(
      result          = peer_result,
      selected_peer   = selected_peer,
      curated_state   = peer_curated_state,
      apply_curated   = function(curated) {
        if (is.null(curated)) return(invisible())
        # Defensive: normalize to the expected shape.
        if (is.null(curated$excluded)) curated$excluded <- integer(0)
        if (is.null(curated$added))    curated$added    <- list()
        curated$excluded <- as.integer(curated$excluded)
        peer_curated_state(curated)
      }
    )
  })
}
