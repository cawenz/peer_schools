# =============================================================================
# Sidebar module — anchor picker, pool filters, theme weight sliders + presets,
# K control, Mahalanobis (advanced), Run / Save buttons.
#
# The module returns a reactive list `sidebar_state` summarizing the current
# control values, formatted for direct use as arguments to compute_peers().
# It also exposes:
#   - $run_trigger   reactive that increments when Run is clicked
#   - $save_trigger  reactive that increments when Save is clicked
#
# Step 2: controls are present and bound. Run / Save observers live in the
# peer table and session modules (steps 3 and 5).
# =============================================================================

# -----------------------------------------------------------------------------
# Theme list. Duplicated from global.R so this file is self-sufficient
# regardless of which order Shiny sources things (autoload vs global.R).
# If you change the theme set, change BOTH definitions in lockstep.
# -----------------------------------------------------------------------------
if (!exists(".THEMES", envir = globalenv(), inherits = FALSE)) {
  .THEMES <- c("size", "selectivity", "resources", "finance",
               "outcomes", "aid", "student_body", "athletics")
}

# Themes that default to 0 weight (opt-in). Sliders for these start at 0
# and presets explicitly hold them at 0 unless overridden.
.OPT_IN_THEMES <- c(
  # "athletics"
  )
.theme_default_weight <- function(th) if (th %in% .OPT_IN_THEMES) 0 else 1.0

# -----------------------------------------------------------------------------
# Geographic region groupings. Used to let users pick "Region: New England"
# or similar and have the candidate-pool filter expand to the constituent
# state abbreviations. Northeast / Midwest / South / West follow the US
# Census regions; New England and Mid-Atlantic are common IR sub-regions.
# -----------------------------------------------------------------------------
.REGIONS <- list(
  northeast   = c("CT","ME","MA","NH","NJ","NY","PA","RI","VT"),
  new_england = c("CT","ME","MA","NH","RI","VT"),
  midatlantic = c("NJ","NY","PA"),
  midwest     = c("IL","IN","IA","KS","MI","MN","MO","NE","ND","OH","SD","WI"),
  south       = c("AL","AR","DE","DC","FL","GA","KY","LA","MD","MS","NC",
                  "OK","SC","TN","TX","VA","WV"),
  west        = c("AK","AZ","CA","CO","HI","ID","MT","NV","NM","OR","UT","WA","WY")
)
.REGION_LABELS <- c(
  northeast   = "Region: Northeast",
  new_england = "Region: New England",
  midatlantic = "Region: Mid-Atlantic",
  midwest     = "Region: Midwest",
  south       = "Region: South",
  west        = "Region: West"
)
.REGION_PREFIX <- "__region_"

# .STATE_NAMES and prettify functions live in R/helpers_format.R

# -----------------------------------------------------------------------------
# Theme weight presets. Map preset name to a named list of theme weights.
# Sliders default to 1.0; presets only override the listed themes.
# -----------------------------------------------------------------------------
.THEME_PRESETS <- list(
  # Balanced: every academic theme at 1.0. Athletics stays at 0 by default
  # to preserve the locked methodology — flip the slider explicitly to opt in.
  balanced       = setNames(
                     lapply(.THEMES, .theme_default_weight),
                     .THEMES),
  # Each non-balanced preset boosts exactly one theme to 2.5 and leaves
  # the rest at 1.0 — symmetric, easy to reason about, and aid + selectivity
  # both get their own preset so users can lean into either dimension.
  # (Replaces the prior "mission_similar" preset, which boosted composition
  # but had a misleading name for a Jesuit institution.)
  outcomes_heavy    = list(size = 1.0, selectivity = 1.0, resources = 1.0,
                           finance = 1.0, outcomes = 2.5, aid = 1.0,
                           student_body = 1.0, athletics = 0),
  resources_heavy   = list(size = 1.0, selectivity = 1.0, resources = 2.0,
                           finance = 1.5, outcomes = 1.0, aid = 1.0,
                           student_body = 1.0, athletics = 0),
  selectivity_heavy = list(size = 1.0, selectivity = 2.5, resources = 1.0,
                           finance = 1.0, outcomes = 1.0, aid = 1.0,
                           student_body = 1.0, athletics = 0),
  aid_heavy         = list(size = 1.0, selectivity = 1.0, resources = 1.0,
                           finance = 1.0, outcomes = 1.0, aid = 2.5,
                           student_body = 1.0, athletics = 0)
)

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
peerSearchSidebarUI <- function(id) {
  ns <- NS(id)
  tagList(
    # ---------------- Anchor ----------------
    tags$h6("Anchor school"),
    selectizeInput(ns("anchor_unitid"),
                   label   = NULL,
                   choices = NULL,
                   options = list(
                     placeholder = "Type to search institutions",
                     maxOptions  = 50
                   )),

    tags$hr(),

    # ---------------- Candidate pool ----------------
    tags$h6("Candidate pool"),
    tags$div(class = "pool-checkbox-row",
      checkboxInput(ns("pool_ranked"), "Ranked universe only", value = TRUE),
      actionLink(ns("ranked_info_btn"),
                  label = HTML("&#9432;"),
                  class = "pool-info-btn",
                  title = "What is the ranked universe?")
    ),

    tags$div(
      tags$label("US News classification"),
      # Default OFF: open pool across every published classification
      # rather than narrowing to whatever the anchor happens to be. The
      # picker is initialized below with the "All US News Classifications"
      # sentinel pre-selected, so the user lands in a usable wide-open
      # state and can narrow from there.
      checkboxInput(ns("pool_class_same"), "Same as anchor", value = FALSE),
      selectInput(ns("pool_class"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$div(
      tags$label("Institution type",
                  tags$small(class = "pool-label-hint",
                             "(public vs. private nonprofit)")),
      # Default OFF: most users want the pool wide-open across both
      # sectors. The picker is pre-populated with both choices at app
      # start (see updateSelectInput in the server below), so flipping
      # the default here doesn't strand them in an empty multi-select.
      checkboxInput(ns("pool_control_same"), "Same as anchor", value = FALSE),
      selectInput(ns("pool_control"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$div(class = "pool-optional-block",
      tags$label("State / region",
                  tags$small(class = "pool-label-hint pool-label-empty-hint",
                             "(leave empty for all states & regions)")),
      selectInput(ns("pool_state"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$div(class = "pool-optional-block",
      tags$label("Religious tradition",
                  tags$small(class = "pool-label-hint pool-label-empty-hint",
                             "(leave empty to include all traditions)")),
      selectInput(ns("pool_religious"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$hr(),

    # ---------------- Theme weights ----------------
    tags$h6("Theme weights"),
    tags$div(
      class = "d-flex flex-wrap gap-1 mb-2",
      actionButton(ns("preset_balanced"),          "Balanced",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_outcomes_heavy"),    "Outcomes-heavy",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_resources_heavy"),   "Resources-heavy",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_selectivity_heavy"), "Selectivity-heavy",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_aid_heavy"),         "Aid-heavy",
                   class = "btn btn-sm btn-outline-secondary")
    ),

    # One slider per theme. Athletics defaults to 0 (opt-in) so existing
    # peer searches behave identically until the user dials it up.
    lapply(.THEMES, function(th) {
      sliderInput(ns(paste0("weight_", th)),
                  # .theme_label() handles multi-word display names
                  # ("student_body" → "Student body") that str_to_title()
                  # would otherwise turn into "Student_body".
                  label = .theme_label(th),
                  min = 0, max = 3,
                  value = .theme_default_weight(th),
                  step = 0.25, ticks = FALSE)
    }),

    # ---- Per-variable weight overrides launcher ----
    # Compact summary in the sidebar — full editor lives in a modal so the
    # ~40 clustering variables can be browsed at once instead of one at a
    # time via type-ahead.
    tags$div(class = "var-override-launcher",
      tags$h6("Variable overrides"),
      uiOutput(ns("var_override_summary")),
      actionButton(ns("open_var_override_modal"),
                   label = "Customize variables…",
                   class = "btn btn-outline-primary btn-sm",
                   width = "100%")
    ),

    tags$hr(),

    # ---------------- K + advanced ----------------
    tags$h6("Output"),
    sliderInput(ns("k"), "Number of peers",
                min = 5, max = 100, value = 20, step = 1, ticks = FALSE),

    accordion(
      open = FALSE,
      accordion_panel(
        "Advanced",
        checkboxInput(ns("mahalanobis"),
                      "Use Mahalanobis distance instead of Euclidean",
                      value = FALSE),
        helpText(tags$small(
          "Mahalanobis adjusts for correlation between variables. ",
          "On this data it typically converges with weighted Euclidean ",
          "after redundant variables are pruned, and falls back to ",
          "Euclidean automatically if the covariance matrix is singular."
        ))
      )
    ),

    # ---------------- Run / Save ----------------
    # No <hr> here — the big primary "Run search" button is itself a
    # strong visual break from the Advanced accordion above it, so a
    # divider would just add noise.
    tags$div(
      class = "d-grid gap-2",
      actionButton(ns("run"), "Run search",
                   icon = icon("play"),
                   class = "btn btn-primary btn-lg"),
      actionButton(ns("save_search"), "Save this search",
                   icon = icon("bookmark"),
                   class = "btn btn-outline-secondary")
    )
  )
}

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
peerSearchSidebarServer <- function(id, restore_signal = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Populate dynamic choices on startup from .SCHOOLS in global.R ---
    # Sorted alphabetically by label and shipped client-side so selectize's
    # server = TRUE pages results from the server instead of shipping
    # all 2,598 schools to the client as JSON on every session start.
    # Cuts ~156KB out of the initial payload + skips selectize2 having
    # to build a 2,598-option DOM upfront — the slowest single thing
    # that fired during app launch.
    updateSelectizeInput(session, "anchor_unitid",
                         choices  = .ANCHOR_CHOICES,
                         selected = .DEFAULT_ANCHOR_UNITID,
                         server   = TRUE)

    # ---- Per-variable override modal state ----
    # var_override_weights is the COMMITTED state: named list of
    # metric -> weight. Only metrics with explicit overrides appear here.
    # The modal lets users edit a draft, then Apply commits to this store.
    var_override_weights <- reactiveVal(list())

    # Clustering-eligible variables grouped by category. Cached here so
    # the modal builder doesn't re-scan .VARIABLES every open.
    .CLUSTERING_VARS <- local({
      df <- .VARIABLES[!is.na(.VARIABLES$use_type) &
                         .VARIABLES$use_type == "clustering", ,
                         drop = FALSE]
      df[order(df$category, df$display_name), ]
    })
    .CATEGORY_LABELS_VAR <- c(
      admissions = "Selectivity & Admissions",
      enrollment = "Enrollment & Composition",
      resources  = "Resources",
      finance    = "Finance",
      outcomes   = "Outcomes & Programs",
      aid        = "Financial Aid",
      athletics  = "Athletics (EADA)"
    )

    # Sidebar summary chip: shows current commit count.
    output$var_override_summary <- renderUI({
      w <- var_override_weights()
      n <- length(w)
      if (n == 0) {
        tags$div(class = "var-override-summary var-override-summary-empty",
          tags$small("No overrides set — every clustering variable uses ",
                     "its theme default."))
      } else {
        tags$div(class = "var-override-summary var-override-summary-set",
          tags$small(tags$strong(sprintf("%d variable%s customized",
                                          n, if (n == 1) "" else "s"))),
          tags$small(class = "var-override-list",
            paste(vapply(names(w), function(m) {
              lbl <- .CLUSTERING_VARS$display_name[
                       match(m, .CLUSTERING_VARS$metric)]
              if (is.na(lbl)) m else lbl
            }, character(1)), collapse = ", ")))
      }
    })

    # ---- Modal launcher + builder ----
    observeEvent(input$open_var_override_modal, {
      current <- var_override_weights()
      # Build the grid: one row per clustering variable, grouped by
      # category section. Each row has a checkbox + label + slider.
      build_section <- function(cat_key, cat_label) {
        rows <- .CLUSTERING_VARS[.CLUSTERING_VARS$category == cat_key, ,
                                  drop = FALSE]
        if (!nrow(rows)) return(NULL)
        tags$div(class = "var-modal-section",
          tags$h6(class = "var-modal-section-title", cat_label),
          tagList(lapply(seq_len(nrow(rows)), function(i) {
            m   <- rows$metric[i]
            lbl <- rows$display_name[i]
            included <- m %in% names(current)
            weight   <- if (included) current[[m]] else 1.0
            tags$div(class = "var-modal-row",
              tags$div(class = "var-modal-row-check",
                checkboxInput(ns(paste0("incl_", m)),
                              label = NULL, value = included,
                              width = NULL)),
              tags$div(class = "var-modal-row-label",
                tags$label(`for` = ns(paste0("incl_", m)), lbl)),
              tags$div(class = "var-modal-row-slider",
                sliderInput(ns(paste0("weight_var_", m)),
                            label = NULL,
                            min = 0, max = 3, value = weight,
                            step = 0.25, ticks = FALSE, width = "100%")))
          })))
      }
      sections <- lapply(names(.CATEGORY_LABELS_VAR), function(k) {
        build_section(k, .CATEGORY_LABELS_VAR[[k]])
      })
      sections <- Filter(Negate(is.null), sections)

      showModal(modalDialog(
        title = "Customize variables",
        size  = "l",
        easyClose = FALSE,
        fade = TRUE,
        footer = tagList(
          actionButton(ns("var_modal_reset"),
                        "Reset to theme defaults",
                        class = "btn btn-outline-secondary"),
          tags$span(style = "flex:1"),
          modalButton("Cancel"),
          actionButton(ns("var_modal_apply"),
                        "Apply",
                        class = "btn btn-primary")
        ),
        div(class = "var-modal-body",
          tags$p(class = "var-modal-intro",
            "Check a row to override that variable's weight. Unchecked ",
            "rows continue to use the theme weight. Slide 0 to drop a ",
            "variable from the distance calculation entirely; slide 3 ",
            "to triple its influence."),
          sections)
      ))
    })

    # Apply: read every checkbox + slider in the modal, build the new
    # committed map, dismiss the modal.
    observeEvent(input$var_modal_apply, {
      new_map <- list()
      for (i in seq_len(nrow(.CLUSTERING_VARS))) {
        m <- .CLUSTERING_VARS$metric[i]
        if (isTRUE(input[[paste0("incl_", m)]])) {
          w <- input[[paste0("weight_var_", m)]]
          if (!is.null(w)) new_map[[m]] <- as.numeric(w)
        }
      }
      var_override_weights(new_map)
      removeModal()
    })

    # Reset: tick off every include checkbox and set sliders to 1.0.
    observeEvent(input$var_modal_reset, {
      for (i in seq_len(nrow(.CLUSTERING_VARS))) {
        m <- .CLUSTERING_VARS$metric[i]
        updateCheckboxInput(session, paste0("incl_", m), value = FALSE)
        updateSliderInput(session,  paste0("weight_var_", m), value = 1.0)
      }
    })

    # Pretty labels for usnews_classification (.prettify_classification
    # lives in R/helpers_format.R). Three sentinel "All" options at the
    # top expand to multiple raw classifications when the filter is
    # applied — same pattern the state/region picker uses for "Region:
    # Northeast" etc.
    raw_classes <- sort(unique(stats::na.omit(.SCHOOLS$usnews_classification)))
    pretty <- .prettify_classification(raw_classes)

    # Sentinel values are kept distinct from real classifications by the
    # double-underscore prefix; the state-filter expander already follows
    # this convention.
    .USNEWS_SENTINEL_ALL                  <<- "__usnews_all__"
    .USNEWS_SENTINEL_ALL_REGIONAL_COLLS   <<- "__usnews_all_regional_colleges__"
    .USNEWS_SENTINEL_ALL_REGIONAL_UNIVS   <<- "__usnews_all_regional_universities__"
    .USNEWS_REGIONAL_COLL_VALUES <<- grep("^regional-colleges-",
                                           raw_classes, value = TRUE)
    .USNEWS_REGIONAL_UNIV_VALUES <<- grep("^regional-universities-",
                                           raw_classes, value = TRUE)

    sentinel_values <- c(.USNEWS_SENTINEL_ALL,
                         .USNEWS_SENTINEL_ALL_REGIONAL_COLLS,
                         .USNEWS_SENTINEL_ALL_REGIONAL_UNIVS)
    sentinel_labels <- c(
      "All US News classifications",
      "All Regional Colleges (Midwest + North + South + West)",
      "All Regional Universities (Midwest + North + South + West)"
    )
    sentinel_choices <- setNames(sentinel_values, sentinel_labels)

    class_choices <- c(sentinel_choices, setNames(raw_classes, pretty))
    # Pre-select the "All US News Classifications" sentinel so the picker
    # has a usable starting value when "Same as anchor" is off (its new
    # default). The sentinel expands to the full classification list at
    # search time via the .USNEWS_SENTINEL_ALL handler.
    updateSelectInput(session, "pool_class",
                      choices  = class_choices,
                      selected = .USNEWS_SENTINEL_ALL)

    # Better display labels for control_grp. Names = labels users see,
    # values = the raw codes used to filter schools.csv.
    control_labels <- c(
      "public"      = "Public",
      "private_nfp" = "Private (nonprofit)"
    )
    raw_controls <- sort(unique(stats::na.omit(.SCHOOLS$control_grp)))
    control_choices <- setNames(
      raw_controls,
      ifelse(raw_controls %in% names(control_labels),
             control_labels[raw_controls], raw_controls)
    )
    # Default to both sectors selected so the user has something to start
    # with the moment they toggle "Same as anchor" off.
    updateSelectInput(session, "pool_control",
                      choices  = control_choices,
                      selected = raw_controls)

    # State / region choices: region sentinels at the top, then states/
    # territories sorted alphabetically by full display name. Selectize
    # matches against both label and value so typing "MA" or "Mass" both
    # find Massachusetts.
    state_raw <- unique(stats::na.omit(.SCHOOLS$stabbr))
    state_display <- ifelse(state_raw %in% names(.STATE_NAMES),
                            .STATE_NAMES[state_raw], state_raw)
    ord <- order(state_display)
    state_named <- setNames(state_raw[ord], state_display[ord])

    region_values <- paste0(.REGION_PREFIX, names(.REGIONS), "__")
    names(region_values) <- .REGION_LABELS[names(.REGIONS)]

    state_choices <- c(region_values, state_named)
    updateSelectInput(session, "pool_state", choices = state_choices)

    # Religious tradition choices: prepend a sentinel "Any religious
    # affiliation" option that resolves to all observed traditions in
    # the sidebar_state reactive. Lets users filter to "religious schools
    # of any tradition" in a single click.
    .ANY_RELIGIOUS_SENTINEL <<- "__any_religious__"
    .ALL_RELIGIOUS_TRADITIONS <<- sort(unique(stats::na.omit(.SCHOOLS$religious_tradition)))
    relig_choices <- c(
      setNames(.ANY_RELIGIOUS_SENTINEL, "Any religious affiliation"),
      .ALL_RELIGIOUS_TRADITIONS
    )
    updateSelectInput(session, "pool_religious", choices = relig_choices)

    # --- Anchor attributes (reactive on anchor selection) ---
    anchor_row <- reactive({
      uid <- as.integer(input$anchor_unitid)
      if (is.na(uid)) return(NULL)
      .SCHOOLS[.SCHOOLS$unitid == uid, , drop = FALSE]
    })

    # --- Religious-tradition: selecting a specific tradition clears "Any" ---
    # Tracks the previous selection so we can tell whether the change was
    # "user added Any to specifics" (let it through, intentional) versus
    # "user added a specific while Any was selected" (clear Any).
    last_relig <- reactiveVal(character(0))
    observeEvent(input$pool_religious, {
      current  <- input$pool_religious %||% character(0)
      previous <- last_relig()
      added    <- setdiff(current, previous)

      if (.ANY_RELIGIOUS_SENTINEL %in% current &&
          length(setdiff(current, .ANY_RELIGIOUS_SENTINEL)) > 0 &&
          !.ANY_RELIGIOUS_SENTINEL %in% added) {
        # User added a specific tradition while "Any" was already selected.
        # Clear "Any" so the selection is unambiguous.
        new_sel <- setdiff(current, .ANY_RELIGIOUS_SENTINEL)
        updateSelectInput(session, "pool_religious", selected = new_sel)
        last_relig(new_sel)
      } else {
        last_relig(current)
      }
    }, ignoreNULL = FALSE)

    # --- "Same as anchor" enable/disable wiring ---
    observe({
      if (isTRUE(input$pool_class_same)) {
        shinyjs::disable("pool_class")
      } else {
        shinyjs::enable("pool_class")
      }
    })
    observe({
      if (isTRUE(input$pool_control_same)) {
        shinyjs::disable("pool_control")
      } else {
        shinyjs::enable("pool_control")
      }
    })

    # --- Default values when "Same as anchor" is unchecked ----------------
    # Unchecking shouldn't drop the user into an empty multi-select. Set
    # sensible defaults so the picker is immediately useful: "All US News
    # Classifications" sentinel for classification, both sectors for
    # control. observeEvent with ignoreInit avoids firing on app start.
    observeEvent(input$pool_class_same, {
      if (isFALSE(input$pool_class_same) &&
          !length(isolate(input$pool_class))) {
        updateSelectInput(session, "pool_class",
                          selected = .USNEWS_SENTINEL_ALL)
      }
    }, ignoreInit = TRUE)
    observeEvent(input$pool_control_same, {
      if (isFALSE(input$pool_control_same) &&
          !length(isolate(input$pool_control))) {
        updateSelectInput(session, "pool_control",
                          selected = c("public", "private_nfp"))
      }
    }, ignoreInit = TRUE)

    # --- Ranked-universe info modal ---------------------------------------
    observeEvent(input$ranked_info_btn, {
      showModal(modalDialog(
        title = "About the ranked universe",
        size = "m",
        easyClose = TRUE,
        footer = modalButton("Close"),
        div(class = "pool-info-body",
          p("The ", tags$strong("ranked universe"),
            " is the set of institutions for which US News publishes a ",
            "numeric overall rank. Across the four categories US News ",
            "ranks, that covers four groups of schools:"),
          tags$ul(
            tags$li(tags$strong("National Universities"),
                    " — research universities with a full range of ",
                    "undergrad and graduate programs."),
            tags$li(tags$strong("National Liberal Arts Colleges"),
                    " — bachelor's-focused colleges drawing students ",
                    "nationally."),
            tags$li(tags$strong("Regional Universities"),
                    " — master's-granting institutions, ranked within ",
                    "four geographic regions (North / South / Midwest / West)."),
            tags$li(tags$strong("Regional Colleges"),
                    " — bachelor's-focused regional schools, also ranked ",
                    "within the four geographic regions.")
          ),
          tags$p(
            tags$strong("Ranked universe only"),
            " (the default) restricts the candidate pool to schools with ",
            "a published US News overall rank. This is usually what you ",
            "want for peer comparison: it keeps the pool to schools US ",
            "News actively benchmarks."),

          tags$h6("What you'd add by unchecking"),
          tags$ul(
            tags$li(tags$strong("Schools that appear in IPEDS but aren't ranked"),
                    " — institutions US News doesn't assign a numeric ",
                    "overall rank to. This is a mixed group: some are ",
                    "specialty schools (art, music, military), some are ",
                    "very small, and some sit in US News categories that ",
                    "aren't part of the ranked set at all.")
          ),

          tags$h6("Effect on the results table"),
          tags$ul(
            tags$li("The ", tags$strong("Class."),
                    " column shows the published US News category for each ",
                    "row (blank when the school has no classification at all)."),
            tags$li("The ", tags$strong("USN Rank"),
                    " column is blank only for schools US News didn't ",
                    "assign a numeric overall rank to."),
            tags$li("Categories are not directly comparable: rank #5 in ",
                    "National Liberal Arts is not equivalent to rank #5 ",
                    "in National Universities, Regional Universities, or ",
                    "Regional Colleges.")
          )
        )
      ))
    })

    # --- Preset buttons update the theme sliders ---
    apply_preset <- function(preset_name) {
      vals <- .THEME_PRESETS[[preset_name]]
      for (th in names(vals)) {
        updateSliderInput(session, paste0("weight_", th), value = vals[[th]])
      }
    }
    observeEvent(input$preset_balanced,          apply_preset("balanced"))
    observeEvent(input$preset_outcomes_heavy,    apply_preset("outcomes_heavy"))
    observeEvent(input$preset_resources_heavy,   apply_preset("resources_heavy"))
    observeEvent(input$preset_selectivity_heavy, apply_preset("selectivity_heavy"))
    observeEvent(input$preset_aid_heavy,         apply_preset("aid_heavy"))

    # --- Restore from a saved search ---
    # When sessionServer puts a saved sidebar_state into restore_signal,
    # hydrate every input here. We can't reliably distinguish "Same as
    # anchor was on, anchor's classification was X" from "user explicitly
    # picked X with Same as anchor off" (both produce the same saved
    # filter), so the restore always lands with Same-as-anchor toggles OFF
    # and the multi-selects set to the saved values. The user can re-enable
    # the toggles after if they want anchor-following behavior.
    if (!is.null(restore_signal)) {
      observeEvent(restore_signal(), {
        state <- restore_signal()
        if (is.null(state)) return()

        if (!is.null(state$anchor_unitid))
          updateSelectizeInput(session, "anchor_unitid",
                               selected = state$anchor_unitid)

        pool <- state$candidate_pool %||% list()
        updateCheckboxInput(session, "pool_ranked",
                            value = isTRUE(pool$in_ranked_universe))

        if (!is.null(pool$usnews_classification)) {
          updateCheckboxInput(session, "pool_class_same", value = FALSE)
          updateSelectInput(session, "pool_class",
                            selected = pool$usnews_classification)
        } else {
          updateCheckboxInput(session, "pool_class_same", value = TRUE)
        }

        if (!is.null(pool$control_grp)) {
          updateCheckboxInput(session, "pool_control_same", value = FALSE)
          updateSelectInput(session, "pool_control",
                            selected = pool$control_grp)
        } else {
          updateCheckboxInput(session, "pool_control_same", value = TRUE)
        }

        updateSelectInput(session, "pool_state",
                          selected = pool$stabbr %||% character(0))
        updateSelectInput(session, "pool_religious",
                          selected = pool$religious_tradition %||% character(0))

        for (th in names(state$theme_weights %||% list())) {
          updateSliderInput(session, paste0("weight_", th),
                            value = state$theme_weights[[th]])
        }
        # Variable overrides: push the committed state into the
        # reactiveVal so the sidebar summary chip + future modal opens
        # reflect what was saved.
        var_w <- state$variable_weights %||% list()
        var_w <- lapply(var_w, as.numeric)
        var_override_weights(var_w)

        if (!is.null(state$k))
          updateSliderInput(session, "k", value = state$k)
        updateCheckboxInput(session, "mahalanobis",
                            value = identical(state$distance_metric,
                                              "mahalanobis"))
      }, ignoreNULL = TRUE)
    }

    # --- Sidebar state reactive ---
    # Live snapshot of all controls, packaged as a list ready to pass to
    # compute_peers(). The peer table module decides when to consume it
    # (gated on the Run button in step 3).
    sidebar_state <- reactive({
      ar <- anchor_row()
      anchor_uid <- if (!is.null(ar) && nrow(ar) == 1) ar$unitid
                    else .DEFAULT_ANCHOR_UNITID

      # ---- Build candidate_pool argument ----
      pool <- list()
      if (isTRUE(input$pool_ranked))
        pool$in_ranked_universe <- TRUE

      # Classification: same-as-anchor uses anchor row; otherwise user picks.
      # Sentinel "All ..." values expand to their constituent raw codes
      # (same pattern as the state picker's region sentinels).
      if (isTRUE(input$pool_class_same)) {
        if (!is.null(ar) && !is.na(ar$usnews_classification))
          pool$usnews_classification <- ar$usnews_classification
      } else if (length(input$pool_class)) {
        sel <- input$pool_class
        expanded <- unique(unlist(lapply(sel, function(v) {
          if (identical(v, .USNEWS_SENTINEL_ALL)) {
            sort(unique(stats::na.omit(.SCHOOLS$usnews_classification)))
          } else if (identical(v, .USNEWS_SENTINEL_ALL_REGIONAL_COLLS)) {
            .USNEWS_REGIONAL_COLL_VALUES
          } else if (identical(v, .USNEWS_SENTINEL_ALL_REGIONAL_UNIVS)) {
            .USNEWS_REGIONAL_UNIV_VALUES
          } else {
            v
          }
        }), use.names = FALSE))
        if (length(expanded)) pool$usnews_classification <- expanded
      }

      if (isTRUE(input$pool_control_same)) {
        if (!is.null(ar) && !is.na(ar$control_grp))
          pool$control_grp <- ar$control_grp
      } else if (length(input$pool_control)) {
        pool$control_grp <- input$pool_control
      }

      # State / region: expand any region sentinels (e.g. "__region_new_england__")
      # to the constituent state abbrs and union with any individually-picked
      # states. "Region: Northeast" + "MA" + "FL" resolves to all northeast
      # states plus FL, deduplicated.
      # Note: strip prefix/suffix via substring rather than sub() — R 4.5.2's
      # sub() returns empty against ^__region_(.+)__$ on these inputs.
      if (length(input$pool_state)) {
        sel <- input$pool_state
        suffix <- "__"
        pfx_n <- nchar(.REGION_PREFIX)
        sfx_n <- nchar(suffix)
        expanded <- unique(unlist(lapply(sel, function(v) {
          if (startsWith(v, .REGION_PREFIX) && endsWith(v, suffix)) {
            key <- substr(v, pfx_n + 1, nchar(v) - sfx_n)
            .REGIONS[[key]]
          } else {
            v
          }
        }), use.names = FALSE))
        if (length(expanded)) pool$stabbr <- expanded
      }

      # Religious tradition: if user picked "Any religious affiliation",
      # expand the sentinel to the full list of observed traditions so the
      # filter resolves to "any school with a religious affiliation".
      if (length(input$pool_religious)) {
        rel_vals <- input$pool_religious
        if (.ANY_RELIGIOUS_SENTINEL %in% rel_vals) {
          pool$religious_tradition <- .ALL_RELIGIOUS_TRADITIONS
        } else {
          pool$religious_tradition <- rel_vals
        }
      }

      # ---- Theme weights ----
      theme_w <- setNames(
        lapply(.THEMES, function(th) input[[paste0("weight_", th)]]),
        .THEMES
      )

      # ---- Per-variable overrides ----
      # var_override_weights() is the committed state — only metrics the
      # user has explicitly overridden via the modal appear in the list.
      variable_w <- var_override_weights() %||% list()

      list(
        anchor_unitid    = anchor_uid,
        candidate_pool   = pool,
        theme_weights    = theme_w,
        variable_weights = variable_w,
        k                = input$k,
        distance_metric  = if (isTRUE(input$mahalanobis)) "mahalanobis"
                           else "euclidean"
      )
    })

    # Triggers exposed to downstream modules. ActionButton values increment
    # on each click and start at 0; consumers can use observeEvent on them.
    list(
      state         = sidebar_state,
      run_trigger   = reactive(input$run),
      save_trigger  = reactive(input$save_search)
    )
  })
}
