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
  .THEMES <- c("scale", "selectivity", "resources", "finance",
               "outcomes", "aid", "composition")
}

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
  balanced       = setNames(as.list(rep(1.0, length(.THEMES))), .THEMES),
  outcomes_heavy = list(scale = 1.0, selectivity = 1.0, resources = 1.0,
                        finance = 1.0, outcomes = 2.5, aid = 1.0,
                        composition = 1.0),
  resources_heavy = list(scale = 1.0, selectivity = 1.0, resources = 2.0,
                         finance = 1.5, outcomes = 1.0, aid = 1.0,
                         composition = 1.0),
  mission_similar = list(scale = 1.0, selectivity = 1.0, resources = 1.0,
                         finance = 1.0, outcomes = 1.0, aid = 1.0,
                         composition = 2.0)
)

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
sidebarUI <- function(id) {
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
    checkboxInput(ns("pool_ranked"), "Ranked universe only", value = TRUE),

    tags$div(
      tags$label("US News classification"),
      checkboxInput(ns("pool_class_same"), "Same as anchor", value = TRUE),
      selectInput(ns("pool_class"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$div(
      tags$label("Sector / control"),
      checkboxInput(ns("pool_control_same"), "Same as anchor", value = TRUE),
      selectInput(ns("pool_control"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$div(
      tags$label("State / region"),
      selectInput(ns("pool_state"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$div(
      tags$label("Religious tradition"),
      selectInput(ns("pool_religious"), label = NULL,
                  choices = NULL, multiple = TRUE,
                  selectize = TRUE)
    ),

    tags$hr(),

    # ---------------- Theme weights ----------------
    tags$h6("Theme weights"),
    tags$div(
      class = "d-flex flex-wrap gap-1 mb-2",
      actionButton(ns("preset_balanced"),        "Balanced",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_outcomes_heavy"),  "Outcomes-heavy",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_resources_heavy"), "Resources-heavy",
                   class = "btn btn-sm btn-outline-secondary"),
      actionButton(ns("preset_mission_similar"), "Mission-similar",
                   class = "btn btn-sm btn-outline-secondary")
    ),

    # 7 sliders, one per theme
    lapply(.THEMES, function(th) {
      sliderInput(ns(paste0("weight_", th)),
                  label = stringr::str_to_title(th),
                  min = 0, max = 3, value = 1.0, step = 0.25, ticks = FALSE)
    }),

    tags$hr(),

    # ---------------- K + advanced ----------------
    tags$h6("Output"),
    sliderInput(ns("k"), "Number of peers",
                min = 5, max = 50, value = 20, step = 1, ticks = FALSE),

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

    tags$hr(),

    # ---------------- Run / Save ----------------
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
sidebarServer <- function(id, restore_signal = NULL) {
  moduleServer(id, function(input, output, session) {

    # --- Populate dynamic choices on startup from .SCHOOLS in global.R ---
    anchor_choices <- {
      vals <- .SCHOOLS$unitid
      names(vals) <- sprintf("%s (%s)", .SCHOOLS$instnm, .SCHOOLS$stabbr)
      vals
    }
    updateSelectizeInput(session, "anchor_unitid",
                         choices  = anchor_choices,
                         selected = .DEFAULT_ANCHOR_UNITID,
                         server   = TRUE)

    # Pretty labels for usnews_classification (.prettify_classification
    # lives in R/helpers_format.R)
    raw_classes <- sort(unique(stats::na.omit(.SCHOOLS$usnews_classification)))
    class_choices <- setNames(raw_classes, .prettify_classification(raw_classes))
    updateSelectInput(session, "pool_class", choices = class_choices)

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

    # --- Preset buttons update the theme sliders ---
    apply_preset <- function(preset_name) {
      vals <- .THEME_PRESETS[[preset_name]]
      for (th in names(vals)) {
        updateSliderInput(session, paste0("weight_", th), value = vals[[th]])
      }
    }
    observeEvent(input$preset_balanced,        apply_preset("balanced"))
    observeEvent(input$preset_outcomes_heavy,  apply_preset("outcomes_heavy"))
    observeEvent(input$preset_resources_heavy, apply_preset("resources_heavy"))
    observeEvent(input$preset_mission_similar, apply_preset("mission_similar"))

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

      # Classification: same-as-anchor uses anchor row; otherwise user picks
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

      list(
        anchor_unitid   = anchor_uid,
        candidate_pool  = pool,
        theme_weights   = theme_w,
        k               = input$k,
        distance_metric = if (isTRUE(input$mahalanobis)) "mahalanobis"
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
