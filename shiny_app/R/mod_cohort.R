# =============================================================================
# Cohort Builder tab.
#
# Workflow built around a fixed cohort an accreditor (e.g., NECHE) has
# handed the user. Three phases:
#   1. Examine — load the cohort from a CSV (UNITID, name, Action columns),
#      see how each school sits on the NECHE-dashboard variables and on
#      institutional classifications.
#   2. Curate — toggle each school's Action (Keep / Maybe / Remove for
#      originals; Possible / Proposed for additions). Schools marked
#      Remove count against the replacement budget.
#   3. Replace — accept the user's Proposed adds (originally Possible Add rows
#      from the file) plus app-suggested replacements ranked by
#      similarity to the anchor with a diversity penalty against the
#      kept cohort.
#
# This module exposes:
#   cohortSidebarUI(id), cohortUI(id), cohortServer(id)
#
# Sidebar holds: anchor picker, cohort file upload, drop-budget readout,
# diversity weight slider, reset button.
# =============================================================================

# Action vocabulary.
#
# Each row in cohort_state has both an `action` and an `origin`. Origin is
# fixed once a row enters the cohort:
#   - "original": came from the file's curated list (the accreditor's
#                 recommended peers). Action can be Keep / Maybe / Remove.
#   - "addition": user-added candidates (file's Possible Add rows or
#                 sidebar-added schools). Action can be Possible / Proposed.
#   - "anchor"  : the anchor school. Renders as a read-only Anchor badge,
#                 no dropdown. Not stored in cohort_state — synthesized at
#                 render time from anchor_uid().
#
# The dropdown options for each row are constrained by origin so users can
# only switch among compatible actions. Switching an addition from
# Possible → Proposed moves it out of the "Possible adds" section and into
# the main cohort list.
.ORIGINAL_ACTIONS <- c("Keep", "Maybe", "Remove")
.ADDITION_ACTIONS <- c("Possible", "Proposed")
.COHORT_ACTIONS   <- c(.ORIGINAL_ACTIONS, .ADDITION_ACTIONS)

# Target size for the in-cohort set, NOT counting the anchor. NECHE's
# original peer list was 24 schools (10 Keep + 4 Maybe + 10 Drop), so
# the natural completed cohort is 24. Edit here if a different
# accreditor's expectation requires a different total.
.COHORT_TARGET_SIZE <- 24L

# Statuses that count toward the "active cohort" total (everything
# committed in the In column, excluding the anchor and excluding Remove).
.IN_COHORT_ACTIVE_STATUSES <- c("Keep", "Maybe", "Proposed")

# 11 headline metrics shown in the cohort overview dashboard. Order is the
# rendered grid order. Each entry must exist in .VARIABLES$metric so the
# format / display name come from the catalog.
.DASHBOARD_METRICS <- c(
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

# Path to the default cohort CSV. Auto-loaded into the tab on session
# start so the user doesn't have to re-upload every session. The file
# upload widget still works as a runtime override.
# Shared with cohort_app — file lives at the project root data/ dir so
# both apps see the same seed. .OUTPUT_DIR is set in global.R; .DATA_DIR
# wasn't in older versions, so derive it defensively.
.DEFAULT_COHORT_FILE <- file.path(
  if (exists(".DATA_DIR")) .DATA_DIR
  else file.path(.PROJECT_ROOT, "data"),
  "neche_cohort.csv")

# Hand-curated descriptions for the cohort-metadata and school-metadata
# columns that ship in the export. Variable columns are documented from
# .VARIABLES at runtime. Keys here must exactly match the export column
# headers; anything missing falls back to a generic "IPEDS raw code" row.
.COHORT_METADATA_CODEBOOK <- tibble::tribble(
  ~column_name,        ~type,               ~display_name,                              ~description,
  "unitid",            "Identifier",        "IPEDS UnitID",                              "Federal IPEDS institutional identifier.",
  "instnm_file",       "Cohort metadata",   "School name (as supplied)",                 "School name as it appeared in the cohort file. NA for the anchor and for sidebar-added rows.",
  "instnm",            "School metadata",   "School name (canonical)",                   "Canonical institution name from IPEDS HD.",
  "stabbr",            "School metadata",   "State abbreviation",                        "Two-letter US state / territory code.",
  "action",            "Cohort metadata",   "Action",                                    "Status of this school in the cohort: Anchor / Keep / Maybe / Remove / Proposed / Possible."
)

.SCHOOL_METADATA_CODEBOOK <- tibble::tribble(
  ~column_name,                ~display_name,                            ~description,
  "latest_year",               "Latest IPEDS year",                      "Most recent panel year the school appears in.",
  "sector",                    "IPEDS sector (code)",                    "IPEDS HD2024 SECTOR raw code (0-9).",
  "sector_label",              "IPEDS sector",                           "Human-readable sector label.",
  "control",                   "Control of institution (code)",          "IPEDS HD2024 CONTROL raw code.",
  "control_label",             "Control of institution",                 "Public / Private not-for-profit / Private for-profit.",
  "iclevel",                   "Institutional level (code)",             "IPEDS HD2024 ICLEVEL raw code.",
  "iclevel_label",             "Institutional level",                    "Four-year, at-least-2-but-less-than-4-year, etc.",
  "control_grp",               "Sector grouping",                        "Collapsed sector used by this app: public / private_nfp.",
  "longitud",                  "Longitude",                              "Decimal longitude from IPEDS HD.",
  "latitude",                  "Latitude",                               "Decimal latitude from IPEDS HD.",
  "instcat",                   "Institutional category (code)",          "IPEDS HD2024 INSTCAT raw code.",
  "instcat_label",             "Institutional category",                 "IPEDS institutional category label.",
  "locale",                    "Locale (code)",                          "IPEDS HD2024 LOCALE raw code (Urbanization).",
  "locale_label",              "Locale",                                 "Urbanization label (City, Suburb, Town, Rural; size).",
  "instsize",                  "Institution size (code)",                "IPEDS HD2024 INSTSIZE raw code.",
  "instsize_label",            "Institution size",                       "Size category (Under 1,000; 1,000-4,999; etc.).",
  "hbcu",                      "HBCU flag (code)",                       "Historically Black College/University indicator.",
  "hbcu_label",                "HBCU",                                   "Historically Black College/University (Yes/No).",
  "hospital",                  "Hospital flag (code)",                   "Has a teaching hospital.",
  "hospital_label",            "Hospital",                               "Teaching hospital (Yes/No).",
  "medical",                   "Medical degrees flag (code)",            "Confers medical degrees.",
  "medical_label",             "Medical degrees",                        "Confers medical degrees (Yes/No).",
  "tribal",                    "Tribal college flag (code)",             "Tribal college indicator.",
  "tribal_label",              "Tribal college",                         "Tribal college (Yes/No).",
  "relaffil",                  "Religious affiliation (code)",           "IPEDS HD2024 RELAFFIL raw code.",
  "religious_affiliation_code","Religious affiliation (numeric code)",   "Local numeric encoding of religious affiliation.",
  "religious_affiliation",     "Religious affiliation",                  "Religious affiliation label (or NA).",
  "religious_tradition",       "Religious tradition",                    "Broader religious tradition grouping.",
  "usnews_classification",     "US News classification",                 "US News & World Report Best Colleges classification (raw code).",
  "in_ranked_universe",        "In ranked universe",                     "TRUE if the school is in the app's ranked candidate universe (4-year, degree-granting, not for-profit, etc.).",
  "accreditor",                "Regional accreditor",                    "Name of the regional accrediting agency.",
  "ic2025",                    "Carnegie 2025 institution class (code)", "Raw Carnegie 2025 institution classification code.",
  "ic2025_label",              "Carnegie 2025 institution class",        "Carnegie 2025 institution classification (e.g., Bachelor's Colleges: Arts & Sciences Focus).",
  "saec2025",                  "Carnegie 2025 SAEC (code)",              "Student Access & Earnings Classification raw code.",
  "saec2025_label",            "Carnegie 2025 SAEC",                     "Carnegie 2025 Student Access & Earnings Classification label.",
  "research2025",              "Carnegie 2025 research activity (code)", "Raw Carnegie research activity classification.",
  "research2025_label",        "Carnegie 2025 research activity",        "Carnegie 2025 research activity label (e.g., R2: High Research Spending and Doctorate Production).",
  "setting2025",               "Carnegie 2025 campus setting (code)",    "Raw Carnegie 2025 campus setting code.",
  "setting2025_label",         "Carnegie 2025 campus setting",           "Carnegie 2025 campus setting label.",
  "highest_degree_2025",       "Highest degree offered (code)",          "Raw Carnegie 2025 highest-degree code.",
  "highest_degree_2025_label", "Highest degree offered",                 "Highest degree offered (e.g., Baccalaureate, Doctorate).",
  "basic2021",                 "Carnegie 2021 Basic (code)",             "Carnegie 2021 Basic classification raw code (legacy).",
  "basic2021_label",           "Carnegie 2021 Basic",                    "Carnegie 2021 Basic classification label (legacy).",
  "ic2025size",                "Carnegie 2025 size (code)",              "Carnegie 2025 size category raw code.",
  "ic2025size_label",          "Carnegie 2025 size",                     "Carnegie 2025 size category label.",
  "ic2025alf",                 "Carnegie 2025 Academic Level Focus code","Raw academic-level-focus code.",
  "ic2025alf_label",           "Carnegie 2025 Academic Level Focus",     "Academic-level-focus label.",
  "apm",                       "Carnegie APM (code)",                    "Academic Program Mix raw code.",
  "apm_label",                 "Carnegie APM",                           "Academic Program Mix label (undergraduate focus).",
  "gpm",                       "Carnegie GPM (code)",                    "Graduate Program Mix raw code.",
  "gpm_label",                 "Carnegie GPM",                           "Graduate Program Mix label.",
  "apm_max_cip2percent",       "APM dominant CIP-2 share",               "Percentage of undergraduate degrees in the largest CIP-2 field.",
  "apm_max_cip2_name",         "APM dominant CIP-2 name",                "Name of the largest CIP-2 field.",
  "earnings_ratio",            "Earnings ratio",                         "Carnegie SAEC earnings-ratio metric.",
  "pbi",                       "PBI flag",                               "Predominantly Black Institution indicator.",
  "annhsi",                    "ANNHSI flag",                            "Asian American and Native American Pacific Islander Serving Institution indicator.",
  "aanapisi",                  "AANAPISI flag",                          "Asian American and Native American Pacific Islander Serving Institution (variant).",
  "hsi",                       "HSI flag",                               "Hispanic-Serving Institution indicator.",
  "nasnti",                    "NASNTI flag",                            "Native American-Serving Non-Tribal Institution indicator.",
  "womenonly",                 "Women's college",                        "Women-only institution indicator.",
  "rpu",                       "Regional public university",             "RPU indicator (Alliance for Research on Regional Colleges).",
  "cce",                       "CCE indicator",                          "Carnegie Community Engagement classification flag.",
  "lpp",                       "LPP indicator",                          "Leadership for Public Purpose flag."
)

# Build a tidy codebook describing every column in `export_df`.
# Variable columns (anything matched in .VARIABLES$metric) are documented
# from the variable catalog; everything else is documented from the
# hand-curated tables above. Unmatched columns get a generic placeholder
# so the codebook always covers the full file.
.build_cohort_codebook <- function(export_df) {
  cols <- names(export_df)

  # Variable rows from .VARIABLES, restricted to columns present.
  vars_df <- .VARIABLES[match(cols, .VARIABLES$metric), , drop = FALSE]
  is_var  <- !is.na(vars_df$metric)

  rows <- vector("list", length(cols))
  for (i in seq_along(cols)) {
    nm <- cols[i]
    if (is_var[i]) {
      v <- vars_df[i, ]
      use_type <- if (!is.na(v$use_type)) v$use_type else "variable"
      type_lbl <- switch(
        use_type,
        clustering  = "Clustering variable",
        descriptive = "Descriptive variable",
        sprintf("Variable (%s)", use_type)
      )
      rows[[i]] <- tibble::tibble(
        column_name  = nm,
        type         = type_lbl,
        category     = if (!is.na(v$category))     v$category     else NA_character_,
        display_name = if (!is.na(v$display_name)) v$display_name else nm,
        description  = if (!is.na(v$coverage_note)) v$coverage_note
                       else if (!is.na(v$ipeds_table_or_formula))
                              sprintf("Source: %s.", v$ipeds_table_or_formula)
                       else NA_character_,
        format       = if (!is.na(v$format))       v$format       else NA_character_,
        source       = if (!is.na(v$source))       v$source       else NA_character_,
        notes        = if (!is.na(v$notes))        v$notes        else NA_character_
      )
    } else if (nm %in% .COHORT_METADATA_CODEBOOK$column_name) {
      m <- .COHORT_METADATA_CODEBOOK[.COHORT_METADATA_CODEBOOK$column_name == nm, ]
      rows[[i]] <- tibble::tibble(
        column_name  = nm,
        type         = m$type,
        category     = NA_character_,
        display_name = m$display_name,
        description  = m$description,
        format       = NA_character_,
        source       = "Cohort builder",
        notes        = NA_character_
      )
    } else if (nm %in% .SCHOOL_METADATA_CODEBOOK$column_name) {
      m <- .SCHOOL_METADATA_CODEBOOK[.SCHOOL_METADATA_CODEBOOK$column_name == nm, ]
      rows[[i]] <- tibble::tibble(
        column_name  = nm,
        type         = "School metadata",
        category     = NA_character_,
        display_name = m$display_name,
        description  = m$description,
        format       = NA_character_,
        source       = "IPEDS HD / Carnegie 2025",
        notes        = NA_character_
      )
    } else {
      rows[[i]] <- tibble::tibble(
        column_name  = nm,
        type         = "Other",
        category     = NA_character_,
        display_name = nm,
        description  = "Undocumented column. Refer to the source dataset.",
        format       = NA_character_,
        source       = NA_character_,
        notes        = NA_character_
      )
    }
  }
  dplyr::bind_rows(rows)
}

# Parse a cohort CSV file into a tibble {unitid, instnm, stabbr,
# instnm_file, action}, with the Anchor row pulled out separately.
# Returns list(cohort = tibble, anchor_uid = integer or NULL).
# `path` is the CSV file path (must exist).
.parse_cohort_csv <- function(path) {
  df <- tryCatch(readr::read_csv(path, show_col_types = FALSE),
                 error = function(e) NULL)
  if (is.null(df) || !nrow(df))
    return(list(cohort = NULL, anchor_uid = NULL,
                error = "Could not read cohort file as CSV."))

  lower <- tolower(names(df))
  uid_col <- which(lower %in% c("unitid", "unit_id", "id"))
  act_col <- which(lower %in% c("action", "status", "decision"))
  if (!length(uid_col))
    return(list(cohort = NULL, anchor_uid = NULL,
                error = "Cohort file must include a UNITID column."))

  uids <- suppressWarnings(as.integer(df[[uid_col[1]]]))
  acts <- if (length(act_col))
            vapply(as.character(df[[act_col[1]]]),
                   .normalize_action, character(1))
          else rep("Keep", length(uids))

  idx <- match(uids, .SCHOOLS$unitid)
  name_col <- setdiff(seq_len(ncol(df)), c(uid_col, act_col))[1]
  origins <- ifelse(acts %in% .ORIGINAL_ACTIONS, "original",
              ifelse(acts %in% .ADDITION_ACTIONS, "addition",
                     ifelse(acts == "Anchor", "anchor", "original")))

  cohort_df <- tibble::tibble(
    unitid = uids,
    instnm_file = if (!is.null(name_col) && !is.na(name_col))
                    as.character(df[[name_col]]) else NA_character_,
    instnm = .SCHOOLS$instnm[idx],
    stabbr = .SCHOOLS$stabbr[idx],
    action = acts,
    origin = origins
  ) %>% dplyr::filter(!is.na(unitid))

  # Peel off Anchor row(s) — they don't live in cohort_state; the anchor
  # row is rendered from anchor_uid() at view time.
  anchor_rows <- cohort_df %>% dplyr::filter(action == "Anchor")
  anchor_uid <- if (nrow(anchor_rows) >= 1) anchor_rows$unitid[1] else NULL

  cohort_df <- cohort_df %>% dplyr::filter(action != "Anchor")
  cohort_df$action <- factor(cohort_df$action, levels = .COHORT_ACTIONS)
  cohort_df$origin <- factor(cohort_df$origin,
                              levels = c("original", "addition"))

  list(cohort = cohort_df,
       anchor_uid = anchor_uid,
       anchor_name = if (!is.null(anchor_uid)) anchor_rows$instnm[1] else NULL,
       error = NULL)
}

.normalize_action <- function(s) {
  if (is.na(s) || !nzchar(s)) return("Maybe")
  s_low <- tolower(trimws(s))
  # "Us" / "Anchor" / "Self" are a special sentinel: the row points at the
  # anchor school, not a cohort member. Recognized separately so the upload
  # handler can pull it out and update the anchor picker.
  if (grepl("^us\\b|^anchor|^self|^home", s_low)) return("Anchor")
  hit <- vapply(.COHORT_ACTIONS, function(a) tolower(a) == s_low, logical(1))
  if (any(hit)) return(.COHORT_ACTIONS[hit])
  # Lenient pattern matches. Order matters: more specific patterns first.
  if (grepl("^propos|^commit",                       s_low)) return("Proposed")
  if (grepl("^possible|^candidate|^brainstorm|^add", s_low)) return("Possible")
  if (grepl("^keep|^retain|^in",                      s_low)) return("Keep")
  if (grepl("^drop|^remove|^cut|^out|^replace",       s_low)) return("Remove")
  if (grepl("^maybe|^unsure|^undecided",              s_low)) return("Maybe")
  "Maybe"
}

# -----------------------------------------------------------------------------
# UI - sidebar
# -----------------------------------------------------------------------------
cohortSidebarUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Add a school"),
    tags$hr(),

    selectizeInput(ns("add_school"),
                   label = NULL,
                   choices = NULL, multiple = FALSE,
                   options = list(placeholder = "Type to search",
                                   maxOptions  = 50)),
    selectInput(ns("add_school_action"),
                label = "...as",
                choices = c("Possible", "Proposed"),
                selected = "Possible", width = "100%"),
    helpText(tags$small(class = "text-muted",
      tags$strong("Possible"), " = brainstorm only (lives in the Possible ",
      "adds section). ", tags$strong("Proposed"),
      " = commit as a replacement (joins the main cohort list).")
    ),
    actionButton(ns("add_school_btn"), "Add to cohort",
                 icon = icon("plus"),
                 class = "btn btn-primary btn-sm w-100"),

    tags$hr(),

    tags$h6("Export"),
    downloadButton(ns("download_cohort_csv"),
                   "Download cohort bundle (.zip)",
                   class = "btn btn-outline-primary btn-sm w-100"),
    helpText(tags$small(class = "text-muted",
      "Zip contains ",
      tags$code("cohort.csv"),
      " (one row per school, all variables joined), ",
      tags$code("codebook.csv"),
      " (column-by-column documentation), and ",
      tags$code("README.txt"),
      ".")
    )
  )
}

# -----------------------------------------------------------------------------
# UI - main panel
# -----------------------------------------------------------------------------
cohortUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Cohort Builder"),
    p(class = "section-intro",
      "Mark schools for replacement up to a budget, dig into how the cohort ",
      "sits on individual variables, and export the full data for further ",
      "analysis. Use the inspector below the cohort table to look at any one ",
      "variable's distribution and per-school values."),

    uiOutput(ns("cohort_view")),

    # Map: header/intro in a renderUI (conditionally rendered), but the
    # leafletOutput itself lives in the static UI tree so Shiny registers
    # the output binding on app start. Without this, nesting the
    # leafletOutput inside a renderUI sometimes leaves it unbound and
    # nothing draws.
    uiOutput(ns("cohort_map_header")),
    tags$div(class = "cohort-map-container",
      leaflet::leafletOutput(ns("cohort_leaflet"), height = "480px")
    ),

    uiOutput(ns("cohort_dashboard")),
    uiOutput(ns("variable_inspector"))
  )
}

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
cohortServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Anchor + cohort state ----
    # The anchor used to be a sidebar selectizeInput. With the simpler
    # sidebar (only Add + Export) it's derived from the bundled cohort
    # file's Anchor row, falling back to .DEFAULT_ANCHOR_UNITID. No UI.
    anchor_uid_state <- reactiveVal(.DEFAULT_ANCHOR_UNITID)
    anchor_uid <- reactive(anchor_uid_state())

    # All schools, keyed by unitid with pretty names — used by the
    # add-school selectize below.
    anchor_choices_all <- {
      vals <- .SCHOOLS$unitid
      names(vals) <- sprintf("%s (%s)", .SCHOOLS$instnm, .SCHOOLS$stabbr)
      vals[order(names(vals))]
    }

    # ---- Load cohort from file ----
    # Parsed result: tibble with unitid, instnm, action, origin. Stored
    # separately as the "original" (from file) and "current" (user-mutated).
    cohort_original <- reactiveVal(NULL)
    cohort_state    <- reactiveVal(NULL)

    # Session-start auto-load from the bundled cohort file. Silent — no
    # toast notifications, since the user knows what's expected to load.
    observe({
      if (!is.null(cohort_state())) return()
      if (!file.exists(.DEFAULT_COHORT_FILE)) return()
      parsed <- .parse_cohort_csv(.DEFAULT_COHORT_FILE)
      if (!is.null(parsed$error)) return()
      if (!is.null(parsed$anchor_uid))
        anchor_uid_state(parsed$anchor_uid)
      cohort_original(parsed$cohort)
      cohort_state(parsed$cohort)
    })

    # ---- Add-a-school control ----
    # Populate the add-school picker with all 2,598 institutions so the
    # user can add anything. The action default is Possible Add.
    updateSelectizeInput(session, "add_school",
                         choices  = anchor_choices_all,
                         selected = character(0),
                         server   = FALSE)

    observeEvent(input$add_school_btn, {
      uid <- suppressWarnings(as.integer(input$add_school))
      if (length(uid) != 1 || is.na(uid)) {
        showNotification("Pick a school first.", type = "warning",
                         duration = 4)
        return()
      }
      df <- cohort_state()
      if (is.null(df)) df <- tibble::tibble(
        unitid = integer(), instnm_file = character(),
        instnm = character(), stabbr = character(),
        action = factor(character(), levels = .COHORT_ACTIONS),
        origin = factor(character(), levels = c("original", "addition"))
      )
      if (uid %in% df$unitid) {
        showNotification("That school is already in the cohort.",
                         type = "warning", duration = 4)
        return()
      }
      new_action <- .normalize_action(input$add_school_action %||% "Possible")
      # Sidebar adds are always additions, never originals.
      if (!new_action %in% .ADDITION_ACTIONS) new_action <- "Possible"
      new_row <- tibble::tibble(
        unitid = uid,
        instnm_file = NA_character_,
        instnm = .SCHOOLS$instnm[match(uid, .SCHOOLS$unitid)],
        stabbr = .SCHOOLS$stabbr[match(uid, .SCHOOLS$unitid)],
        action = factor(new_action, levels = .COHORT_ACTIONS),
        origin = factor("addition", levels = c("original", "addition"))
      )
      cohort_state(dplyr::bind_rows(df, new_row))
      updateSelectizeInput(session, "add_school", selected = character(0))
    }, ignoreInit = TRUE)

    # ---- Action toggle handler ----
    # Each row's action selectInput sends {row, action} to a single
    # delegated input. The observer below updates the cohort_state row.
    observeEvent(input$action_change, {
      payload <- input$action_change
      if (is.null(payload) || is.null(payload$uid) || is.null(payload$action))
        return()
      df <- cohort_state(); if (is.null(df)) return()
      ix <- which(df$unitid == as.integer(payload$uid))
      if (!length(ix)) return()
      new_action <- .normalize_action(payload$action)

      # Constrain by origin: an original row can only move among
      # Keep/Maybe/Remove; an addition can only move among Possible/Proposed.
      origin <- as.character(df$origin[ix])
      allowed <- switch(origin,
                        original = .ORIGINAL_ACTIONS,
                        addition = .ADDITION_ACTIONS,
                        .COHORT_ACTIONS)
      if (!new_action %in% allowed) return()

      df$action[ix] <- new_action
      cohort_state(df)
    })

    # ---- Row remove handler ----
    # Only fired by the × button on addition rows. Drops the matching uid
    # from cohort_state entirely; ignored if the row turns out to be an
    # original (defensive — the button isn't rendered there to begin with).
    observeEvent(input$row_remove, {
      payload <- input$row_remove
      if (is.null(payload) || is.null(payload$uid)) return()
      df <- cohort_state(); if (is.null(df)) return()
      uid <- as.integer(payload$uid)
      ix  <- which(df$unitid == uid)
      if (!length(ix)) return()
      if (!identical(as.character(df$origin[ix]), "addition")) return()
      removed_name <- df$instnm[ix]
      cohort_state(df[-ix, , drop = FALSE])
      showNotification(
        tagList(tags$strong("Removed: "), removed_name),
        type = "message", duration = 3
      )
    })

    # ---- Row move handler ----
    # Fired by the → / ← arrow buttons. payload$side is the SIDE the row
    # was on when the user clicked — "in" means the user wants to move the
    # row Out, "out" means move it back In.
    #
    # Origin rule (locked):
    #   in/original  → Remove     (Keep/Maybe → Remove)
    #   in/addition  → Possible   (Proposed   → Possible)
    #   out/original → Maybe      (Remove     → Maybe; un-flag, undecided)
    #   out/addition → Proposed   (Possible   → Proposed; commit)
    observeEvent(input$row_move, {
      payload <- input$row_move
      if (is.null(payload) || is.null(payload$uid) || is.null(payload$side))
        return()
      df  <- cohort_state(); if (is.null(df)) return()
      uid <- as.integer(payload$uid)
      ix  <- which(df$unitid == uid)
      if (!length(ix)) return()

      origin <- as.character(df$origin[ix])
      side   <- as.character(payload$side)

      new_action <- if (identical(side, "in")) {
        # Moving from In to Out
        if (origin == "original") "Remove" else "Possible"
      } else if (identical(side, "out")) {
        # Moving from Out to In
        if (origin == "original") "Maybe" else "Proposed"
      } else {
        return()  # unrecognized side payload
      }

      df$action[ix] <- new_action
      cohort_state(df)
    })

    # ---- Cohort table rendering ----
    # Wide matrix slice for the cohort. neche_dashboard variables in
    # column order, with anchor row prepended for reference.
    cohort_wide <- reactive({
      df <- cohort_state()
      a_uid <- anchor_uid()
      if (is.null(df) || is.null(a_uid)) return(NULL)

      uids_all <- unique(c(a_uid, df$unitid))
      .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid %in% uids_all, , drop = FALSE]
    })

    # No View selector now; we just show a few categorical columns for
    # orientation. Numeric variables live in the inspector below.

    # Build a single compact row.
    #
    # The row's controls depend on (side, origin):
    #   anchor       : read-only "Anchor" pill. No arrow, no delete.
    #   in/original  : Keep/Maybe dropdown   + → arrow (move out)
    #   in/addition  : Proposed badge        + → arrow (move out) + × delete
    #   out/original : Remove badge          + ← arrow (move in)
    #   out/addition : Possible badge        + ← arrow (move in)  + × delete
    .cohort_row <- function(row, wide_row, origin, side) {
      current_action <- as.character(row$action)

      # --- Status widget (left edge of action cell) ---
      status_widget <- if (identical(origin, "anchor")) {
        current_action <- "Anchor"
        tags$span(class = "cohort-anchor-pill",
                  title = "Anchor institution (your school)",
                  "Anchor")
      } else if (identical(side, "in") && identical(origin, "original")) {
        # Only place a true dropdown survives: in-side originals can be
        # toggled between Keep and Maybe without sending the row out.
        tags$select(
          class = "cohort-action-select cohort-action-select-mini",
          `data-uid` = row$unitid,
          onchange = sprintf(
            "Shiny.setInputValue('%s', {uid: %d, action: this.value, t: Date.now()}, {priority: 'event'});",
            ns("action_change"), row$unitid),
          lapply(c("Keep", "Maybe"), function(a) {
            tags$option(value = a,
                        selected = if (identical(current_action, a))
                                      "selected" else NULL,
                        a)
          })
        )
      } else {
        # In/addition (Proposed) or Out side (Remove, Possible): static badge.
        badge_slug <- tolower(gsub(" ", "-", current_action))
        tags$span(
          class = sprintf("cohort-action-badge cohort-badge-%s", badge_slug),
          current_action
        )
      }

      # --- Move-arrow button (everything but anchor) ---
      move_btn <- if (!identical(origin, "anchor")) {
        arrow_label <- if (identical(side, "in")) "→" else "←"
        arrow_title <- if (identical(side, "in"))
                         "Move to Out / Considering"
                       else
                         "Move back to In Cohort"
        tags$button(
          class = sprintf("cohort-move-btn cohort-move-%s", side),
          type  = "button",
          title = arrow_title,
          `aria-label` = sprintf("%s: %s", arrow_title, row$instnm),
          onclick = sprintf(
            "Shiny.setInputValue('%s', {uid: %d, side: '%s', t: Date.now()}, {priority: 'event'});",
            ns("row_move"), row$unitid, side),
          HTML(arrow_label)
        )
      } else NULL

      # --- × delete (additions only) ---
      remove_btn <- if (identical(origin, "addition")) {
        tags$button(
          class    = "cohort-remove-btn",
          type     = "button",
          title    = "Remove this school from the cohort list",
          `aria-label` = sprintf("Remove %s", row$instnm),
          onclick  = sprintf(
            "Shiny.setInputValue('%s', {uid: %d, t: Date.now()}, {priority: 'event'});",
            ns("row_remove"), row$unitid),
          HTML("&times;")
        )
      } else NULL

      badge_slug   <- tolower(gsub(" ", "-", current_action))
      action_class <- sprintf("cohort-action-%s", badge_slug)
      usnews <- .prettify_classification(wide_row$usnews_classification)

      # Note: no secondary badge after the school name now — the row tint
      # plus the status widget in the action cell already encode the state,
      # and the two-column layout is tight enough that we don't need both.
      tags$tr(class = paste("cohort-row", action_class),
        tags$td(class = "cohort-action-cell",
                tags$div(class = "cohort-action-widget",
                  status_widget,
                  if (identical(side, "in")) tagList(remove_btn, move_btn)
                                              else tagList(move_btn,  remove_btn)
                )),
        tags$td(class = "cohort-name",
                tags$span(class = "cohort-name-text", row$instnm)),
        tags$td(class = "cohort-state", row$stabbr),
        tags$td(class = "cohort-ctx",
                if (is.na(usnews)) "—" else usnews)
      )
    }

    .cohort_table <- function(df_subset, wide_df, side,
                              anchor_row_df = NULL) {
      stopifnot(side %in% c("in", "out"))
      if (!nrow(df_subset) && is.null(anchor_row_df)) return(NULL)

      anchor_tr <- NULL
      if (!is.null(anchor_row_df) && nrow(anchor_row_df)) {
        w_anchor <- wide_df[wide_df$unitid == anchor_row_df$unitid, ,
                             drop = FALSE]
        if (nrow(w_anchor))
          anchor_tr <- .cohort_row(anchor_row_df, w_anchor,
                                    origin = "anchor", side = side)
      }

      rows <- lapply(seq_len(nrow(df_subset)), function(i) {
        r <- df_subset[i, ]
        w <- wide_df[wide_df$unitid == r$unitid, , drop = FALSE]
        if (!nrow(w)) return(NULL)
        .cohort_row(r, w, origin = as.character(r$origin), side = side)
      })
      tags$table(class = sprintf("cohort-table cohort-table-compact cohort-table-%s",
                                  side),
        tags$thead(
          tags$tr(
            tags$th(class = "cohort-action-th", "Status"),
            tags$th(class = "cohort-name-th",   "School"),
            tags$th(class = "cohort-state-th",  "State"),
            tags$th(class = "cohort-ctx-th",    "US News classification")
          )
        ),
        tags$tbody(anchor_tr, rows)
      )
    }

    # -------------------------------------------------------------------------
    # Cohort overview dashboard — 11 stat cards above the variable inspector.
    # Each card shows the anchor's value, the cohort's min/median/max, and a
    # mini SVG strip with a universe density curve, a cohort range bar, and
    # an anchor tick. Click a card to scroll to the inspector with that
    # metric pre-selected.
    # -------------------------------------------------------------------------

    # The "in-cohort" set used by the dashboard cards: anchor + Keep +
    # Maybe + Proposed. Mirrors the In column in the two-column table.
    in_cohort_uids <- reactive({
      df    <- cohort_state()
      a_uid <- anchor_uid()
      if (is.null(df)) return(integer())
      uids <- df$unitid[df$action %in% c("Keep", "Maybe", "Proposed")]
      unique(c(a_uid, uids))
    })

    # Universe baseline for the dashboard strips. We deliberately use the
    # full ranked universe (not the inspector's filtered pool), so the
    # cards always show the same baseline regardless of inspector state.
    dashboard_universe <- reactive({
      .SCHOOLS_WIDE[.SCHOOLS_WIDE$in_ranked_universe %in% TRUE, , drop = FALSE]
    })

    # Short, stakeholder-friendly source labels.
    .SOURCE_LABELS <- c(
      ipeds          = "IPEDS",
      ipeds_derived  = "IPEDS",
      ccihe          = "Carnegie 2025 Data File",
      cds_ai         = "Common Data Set",
      cds_ai_derived = "Common Data Set",
      scorecard      = "College Scorecard"
    )
    # Sources whose raw value is itself a computed/derived number.
    .COMPUTED_SOURCES <- c("ipeds_derived", "cds_ai_derived", "ccihe")

    .simplify_source <- function(src) {
      if (is.null(src) || is.na(src) || !nzchar(src))
        return("Unknown source")
      lbl <- .SOURCE_LABELS[[src]]
      if (is.null(lbl)) src else lbl
    }
    .is_computed_source <- function(src) {
      if (is.null(src) || is.na(src) || !nzchar(src)) return(FALSE)
      src %in% .COMPUTED_SOURCES
    }

    # Color palette for the per-school rug ticks. Matches the action
    # badges used elsewhere in the cohort tab.
    .DASH_ACTION_COLORS <- c(
      "Anchor"   = "#602D89",
      "Keep"     = "#2e7d32",
      "Maybe"    = "#AC9E94",
      "Proposed" = "#7591b3"
    )

    # SVG strip: faint universe density curve at top, per-school rug ticks
    # at bottom (colored by action), anchor as a tall purple line + dot
    # spanning the whole strip. `rug_data` is a data.frame with $value and
    # $action columns; if NULL or empty, no rug is drawn.
    #
    # Returns an HTML() string ready to drop into a tagList.
    .dashboard_strip_svg <- function(universe_vals, anchor_val,
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

      # Vertical regions inside the strip:
      #   density region: y = 4 .. (height - 14)
      #   rug region:     y = (height - 10) .. (height - 2)
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

      # Density polygon: top follows the curve, bottom flat at density_bottom.
      poly_x <- c(to_x(dens$x),
                   to_x(dens$x[length(dens$x)]),
                   to_x(dens$x[1]))
      poly_y <- c(density_bottom - dens_y,
                   rep(density_bottom, 2))
      pts <- paste(sprintf("%.1f,%.1f", poly_x, poly_y), collapse = " ")

      # Per-school rug. Anchor tick is drawn separately, so exclude it
      # here (otherwise the anchor's color would compete with the long
      # vertical anchor line above the rug).
      rug_str <- ""
      if (!is.null(rug_data) && nrow(rug_data) > 0) {
        rd <- rug_data[is.finite(rug_data$value) &
                        rug_data$action != "Anchor", , drop = FALSE]
        if (nrow(rd)) {
          colors <- unname(.DASH_ACTION_COLORS[as.character(rd$action)])
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

      # Anchor: long vertical line spanning density region, with dot at top.
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

    # Build a tidy rug data.frame for a given metric: anchor row + every
    # in-cohort row (Keep + Maybe + Proposed) with their action labels.
    .build_rug_data <- function(metric) {
      df    <- cohort_state()
      a_uid <- anchor_uid()
      if (is.null(df) || is.null(a_uid) ||
          !metric %in% names(.SCHOOLS_WIDE)) {
        return(data.frame(unitid = integer(), action = character(),
                          value = numeric(), instnm = character(),
                          stringsAsFactors = FALSE))
      }
      in_df <- df[df$action %in% c("Keep", "Maybe", "Proposed"),
                   c("unitid", "action", "instnm")]
      anchor_meta <- .SCHOOLS[.SCHOOLS$unitid == a_uid, , drop = FALSE]
      anchor_row <- data.frame(
        unitid = a_uid,
        action = "Anchor",
        instnm = if (nrow(anchor_meta)) anchor_meta$instnm[1] else "(anchor)",
        stringsAsFactors = FALSE
      )
      all <- rbind(anchor_row, as.data.frame(in_df, stringsAsFactors = FALSE))
      all$action <- as.character(all$action)
      all$value <- .SCHOOLS_WIDE[[metric]][match(all$unitid,
                                                  .SCHOOLS_WIDE$unitid)]
      all
    }

    # Build one card.
    .dashboard_card <- function(metric, anchor_val, rug_data,
                                 universe_vals, display_name, fmt) {
      cv  <- rug_data$value[rug_data$action != "Anchor" &
                              is.finite(rug_data$value)]
      n_c <- sum(rug_data$action != "Anchor")  # in-cohort minus anchor
      n_r <- length(cv)

      cohort_line <- if (n_r > 0) {
        sprintf("Cohort: %s – %s   (median %s)",
                .format_value(min(cv),           fmt),
                .format_value(max(cv),           fmt),
                .format_value(stats::median(cv), fmt))
      } else "Cohort: no data"

      strip <- .dashboard_strip_svg(universe_vals, anchor_val,
                                     rug_data = rug_data)

      tags$div(class = "dash-card",
        `data-metric` = metric,
        onclick = sprintf(
          "Shiny.setInputValue('%s', {metric: '%s', t: Date.now()}, {priority: 'event'});",
          ns("dash_card_click"), metric),
        tags$div(class = "dash-card-title", display_name),
        tags$div(class = "dash-card-anchor",
          tags$span(class = "dash-card-anchor-label", "Anchor"),
          tags$span(class = "dash-card-anchor-val",
                     .format_value(anchor_val, fmt))
        ),
        strip,
        tags$div(class = "dash-card-cohort", cohort_line),
        tags$div(class = "dash-card-n",
                  sprintf("%d of %d reporting", n_r, n_c))
      )
    }

    # -------------------------------------------------------------------------
    # Geographic map: Keep + Possible (+ anchor) schools.
    #
    # Shows the committed original peers (Keep) alongside the brainstormed
    # candidates (Possible) on a leaflet map. Lets the user see at a glance
    # whether the original cohort is geographically concentrated and where
    # the candidate adds sit relative to it.
    #
    # Markers use the same color logic as everywhere else in the cohort
    # tab: Anchor purple-dark, Keep green, Possible light purple. Maybe /
    # Remove / Proposed are deliberately excluded to keep the map focused
    # on "what's solidly in" vs "what's being considered".
    # -------------------------------------------------------------------------
    # All statuses except Remove appear on the map. Color palette mirrors
    # the per-action badges used elsewhere in the cohort tab so the map
    # reads consistently with the cohort table and the dashboard.
    .MAP_ACTION_COLORS <- c(
      Anchor   = "#251230",  # dark slate
      Keep     = "#2e7d32",  # green
      Maybe    = "#AC9E94",  # taupe
      Proposed = "#602D89",  # purple (committed addition)
      Possible = "#7591b3"   # light purple (brainstormed)
    )

    # Statuses that appear on the map (everything except Remove).
    .MAP_STATUSES <- c("Keep", "Maybe", "Proposed", "Possible")

    # Header is conditionally rendered, but the map container itself
    # stays visible in the DOM at all times. Hiding the container with
    # shinyjs::hide() caused leaflet to compute 0x0 tile sizes and never
    # recover when the container became visible again, which is why no
    # markers were appearing after the first load.
    output$cohort_map_header <- renderUI({
      df <- cohort_state()
      has_pts <- !is.null(df) &&
                  sum(df$action %in% .MAP_STATUSES) > 0

      # Hide the view toggle + category checkboxes when there's nothing
      # to draw. When the cohort has data, we ALWAYS render the same
      # controls regardless of which categories are present — empty
      # categories just produce nothing on the map.
      controls <- if (has_pts) tags$div(class = "cohort-map-controls",
        tags$div(class = "cohort-map-control-block",
          tags$div(class = "cohort-map-control-label", "View"),
          radioButtons(ns("map_view"),
                       label = NULL,
                       choices = c("Points" = "points",
                                    "Heatmap" = "heatmap"),
                       selected = "points",
                       inline = TRUE)
        ),
        tags$div(class = "cohort-map-control-block",
          tags$div(class = "cohort-map-control-label", "Include"),
          checkboxGroupInput(ns("map_cats"),
                              label = NULL,
                              choices = c("Anchor", "Keep", "Maybe",
                                          "Proposed", "Possible"),
                              selected = c("Anchor", "Keep", "Maybe",
                                            "Proposed", "Possible"),
                              inline = TRUE)
        )
      ) else NULL

      tagList(
        tags$hr(class = "cohort-section-divider"),
        h4("Geographic distribution"),
        p(class = "section-intro",
          if (has_pts) tagList(
            "Anchor + every cohort school except ", tags$strong("Remove"),
            ". Markers use the same color logic as the cohort table: ",
            tags$strong("Keep"), " green, ", tags$strong("Maybe"),
            " taupe, ", tags$strong("Proposed"), " purple, ",
            tags$strong("Possible"), " light purple. ",
            "Switch between point and heatmap views with the toggle ",
            "below; the heatmap rebuilds from whichever categories ",
            "are checked. Hover any marker for school details.")
          else
            "No cohort schools to plot yet."
        ),
        controls
      )
    })

    # Build the per-marker frame: anchor + every status except Remove.
    # Pulled out as a reactive so renderLeaflet AND any future
    # leafletProxy observer can share it without re-deriving twice.
    map_points <- reactive({
      df    <- cohort_state(); req(df)
      a_uid <- anchor_uid();   req(a_uid)

      in_map <- df[df$action %in% .MAP_STATUSES, ]
      anchor_meta <- .SCHOOLS[.SCHOOLS$unitid == a_uid, , drop = FALSE]

      anchor_df <- if (nrow(anchor_meta)) tibble::tibble(
        unitid = anchor_meta$unitid,
        instnm = anchor_meta$instnm,
        stabbr = anchor_meta$stabbr,
        action = "Anchor"
      ) else tibble::tibble()

      all_rows <- dplyr::bind_rows(
        anchor_df,
        if (nrow(in_map))
          tibble::tibble(
            unitid = in_map$unitid,
            instnm = in_map$instnm,
            stabbr = in_map$stabbr,
            action = as.character(in_map$action)
          ) else NULL
      )

      ctx_cols <- c("unitid", "longitud", "latitude",
                    "usnews_classification", "ic2025_label",
                    "control_grp", "instsize_label")
      ctx <- .SCHOOLS[, intersect(ctx_cols, names(.SCHOOLS)), drop = FALSE]
      pts <- dplyr::left_join(all_rows, ctx, by = "unitid")
      pts <- pts[is.finite(pts$longitud) & is.finite(pts$latitude), ]
      if (!nrow(pts)) return(pts)

      pts$color <- unname(.MAP_ACTION_COLORS[pts$action])
      pts$tip   <- sprintf(
        "<strong>%s</strong><br><span style='color:#64748b'>%s &middot; %s</span>",
        pts$instnm, pts$stabbr, pts$action)
      pts$popup <- vapply(seq_len(nrow(pts)), function(i) {
        r <- pts[i, ]
        cls_u <- if (!is.na(r$usnews_classification))
                   .prettify_classification(r$usnews_classification) else NA
        cls_c <- if (!is.na(r$ic2025_label)) r$ic2025_label else NA
        ctrl  <- if (!is.na(r$control_grp))
                   .prettify_control(r$control_grp) else NA
        size  <- if (!is.na(r$instsize_label)) r$instsize_label else NA
        parts <- c(
          sprintf("<strong>%s</strong>", r$instnm),
          sprintf("<span style='color:#602D89;font-weight:600'>%s</span>",
                  r$action),
          sprintf("%s", r$stabbr),
          if (!is.na(cls_u)) sprintf("<em>US News:</em> %s",  cls_u),
          if (!is.na(cls_c)) sprintf("<em>Carnegie:</em> %s", cls_c),
          if (!is.na(ctrl))  sprintf("<em>Sector:</em> %s",   ctrl),
          if (!is.na(size))  sprintf("<em>Size:</em> %s",     size)
        )
        paste(parts, collapse = "<br>")
      }, character(1))
      pts
    })

    # Track the user's last-known view so we can restore it after the
    # cohort_state-driven re-render (which otherwise resets to fit).
    .last_view <- reactiveVal(NULL)
    observeEvent(input$cohort_leaflet_center, {
      z <- input$cohort_leaflet_zoom
      c <- input$cohort_leaflet_center
      if (is.null(z) || is.null(c)) return()
      .last_view(list(lng = c$lng, lat = c$lat, zoom = z))
    })

    output$cohort_leaflet <- leaflet::renderLeaflet({
      pts <- map_points()

      m <- leaflet::leaflet(
        options = leaflet::leafletOptions(zoomControl = TRUE,
                                           attributionControl = TRUE)
      ) %>%
        leaflet::addProviderTiles("CartoDB.Positron") %>%
        leaflet::addLegend(
          position = "bottomright",
          colors   = unname(.MAP_ACTION_COLORS),
          labels   = names(.MAP_ACTION_COLORS),
          opacity  = 0.85,
          title    = "Status"
        )

      # No points yet? Just show a continental-US default.
      if (!nrow(pts)) {
        return(m %>% leaflet::setView(lng = -98.5, lat = 39.5, zoom = 4))
      }

      # --- Read the Shiny controls (with safe defaults during init) ---
      view_mode <- input$map_view %||% "points"
      checked   <- input$map_cats %||% c("Anchor", "Keep", "Maybe",
                                           "Proposed", "Possible")

      # Filter to only the checked categories.
      pts_filt    <- pts[pts$action %in% checked, , drop = FALSE]
      anchor_pts  <- pts_filt[pts_filt$action == "Anchor", ]
      other_pts   <- pts_filt[pts_filt$action != "Anchor", ]

      if (identical(view_mode, "heatmap")) {
        # --- Heatmap view ---
        # Density across the checked categories. Markers are deliberately
        # NOT drawn so the heatmap reads as a single continuous surface.
        # If only the anchor is checked there's nothing useful to plot;
        # we draw the anchor marker for orientation but skip the heatmap.
        if (nrow(other_pts) > 0) {
          m <- m %>% leaflet.extras::addHeatmap(
            data       = other_pts,
            lng        = ~longitud, lat = ~latitude,
            intensity  = 1,
            radius     = 28,
            blur       = 20,
            minOpacity = 0.35,
            max        = 1
          )
        }
        # Keep the anchor visible in either view so the user always has
        # a reference point.
        if (nrow(anchor_pts)) {
          m <- m %>% leaflet::addAwesomeMarkers(
            data = anchor_pts,
            lng = ~longitud, lat = ~latitude,
            icon = leaflet::awesomeIcons(
              icon = "star", library = "fa",
              iconColor = "#FFFFFF", markerColor = "purple"),
            label = lapply(anchor_pts$tip, htmltools::HTML),
            popup = lapply(anchor_pts$popup, htmltools::HTML),
            labelOptions = leaflet::labelOptions(
              direction = "auto", offset = c(0, -16),
              style = list("font-family" = "'Manrope', sans-serif",
                            "font-size" = "12px"))
          )
        }
      } else {
        # --- Points view (default) ---
        # One addCircleMarkers call per category, with cluster options
        # set tight so only true co-locations group.
        cluster_opts <- leaflet::markerClusterOptions(
          showCoverageOnHover     = FALSE,
          zoomToBoundsOnClick     = TRUE,
          spiderfyOnMaxZoom       = TRUE,
          disableClusteringAtZoom = 9,
          maxClusterRadius        = 1
        )

        for (act in c("Keep", "Maybe", "Proposed", "Possible")) {
          pts_act <- other_pts[other_pts$action == act, , drop = FALSE]
          if (!nrow(pts_act)) next
          m <- m %>% leaflet::addCircleMarkers(
            data  = pts_act,
            lng   = ~longitud, lat = ~latitude,
            color = ~color, fillColor = ~color,
            radius = 7, weight = 2, opacity = 1, fillOpacity = 0.75,
            label = lapply(pts_act$tip, htmltools::HTML),
            popup = lapply(pts_act$popup, htmltools::HTML),
            labelOptions = leaflet::labelOptions(
              direction = "auto", offset = c(0, -10),
              style = list("font-family" = "'Manrope', sans-serif",
                            "font-size" = "12px")),
            clusterOptions = cluster_opts
          )
        }

        if (nrow(anchor_pts)) {
          m <- m %>% leaflet::addAwesomeMarkers(
            data = anchor_pts,
            lng = ~longitud, lat = ~latitude,
            icon = leaflet::awesomeIcons(
              icon = "star", library = "fa",
              iconColor = "#FFFFFF", markerColor = "purple"),
            label = lapply(anchor_pts$tip, htmltools::HTML),
            popup = lapply(anchor_pts$popup, htmltools::HTML),
            labelOptions = leaflet::labelOptions(
              direction = "auto", offset = c(0, -16),
              style = list("font-family" = "'Manrope', sans-serif",
                            "font-size" = "12px"))
          )
        }
      }

      # Restore the user's last view if they've zoomed/panned, otherwise
      # fit to the cohort's bounds. This makes edits to the cohort feel
      # smooth: adding or removing a school refreshes markers without
      # snapping the map back to the default fit.
      lv <- isolate(.last_view())
      if (!is.null(lv) && all(is.finite(c(lv$lng, lv$lat, lv$zoom)))) {
        m %>% leaflet::setView(lng = lv$lng, lat = lv$lat, zoom = lv$zoom)
      } else {
        lng_rng <- range(pts$longitud, na.rm = TRUE)
        lat_rng <- range(pts$latitude, na.rm = TRUE)
        m %>% leaflet::fitBounds(
          lng1 = lng_rng[1] - 0.5, lat1 = lat_rng[1] - 0.5,
          lng2 = lng_rng[2] + 0.5, lat2 = lat_rng[2] + 0.5
        )
      }
    })

    output$cohort_dashboard <- renderUI({
      df    <- cohort_state(); if (is.null(df)) return(NULL)
      a_uid <- anchor_uid();   req(a_uid)
      univ  <- dashboard_universe()

      cards <- lapply(.DASHBOARD_METRICS, function(m) {
        if (!m %in% names(.SCHOOLS_WIDE)) return(NULL)
        meta <- .VARIABLES[match(m, .VARIABLES$metric), , drop = FALSE]
        dn   <- if (nrow(meta) && !is.na(meta$display_name)) meta$display_name
                else m
        fmt  <- if (nrow(meta)) meta$format else NA

        anchor_val    <- .SCHOOLS_WIDE[[m]][.SCHOOLS_WIDE$unitid == a_uid][1]
        rug_data      <- .build_rug_data(m)
        universe_vals <- univ[[m]]

        .dashboard_card(m, anchor_val, rug_data, universe_vals,
                         display_name = dn, fmt = fmt)
      })

      tagList(
        tags$hr(class = "cohort-section-divider"),
        h4("Cohort overview"),
        p(class = "section-intro",
          "At-a-glance view of how the in-cohort (Anchor + Keep + Maybe + ",
          "Proposed) sits on 11 key metrics. The faint curve is the ",
          "ranked universe distribution; each rug tick at the bottom is one ",
          "in-cohort school colored by status; the tall purple line is the ",
          "anchor. Click a card for the variable's description and a ",
          "per-school value table."),
        tags$div(class = "dash-grid", cards)
      )
    })

    # ---- Dashboard card click → modal with description + rug + values ----
    # The modal stays on-screen so the user doesn't lose the dashboard.
    # Its footer has an "Open in inspector" button that jumps to the
    # inspector (also updating the inspector's variable picker).
    observeEvent(input$dash_card_click, {
      payload <- input$dash_card_click
      if (is.null(payload) || is.null(payload$metric)) return()
      metric <- payload$metric
      if (!metric %in% names(.SCHOOLS_WIDE)) return()

      meta <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      dn   <- if (nrow(meta) && !is.na(meta$display_name)) meta$display_name
              else metric
      fmt  <- if (nrow(meta)) meta$format else NA

      # Description: prefer notes, then coverage_note. The raw IPEDS
      # formula is no longer a fallback — that detail lives on the
      # Source chip, not in the description.
      desc <- if (nrow(meta) && !is.na(meta$notes) && nzchar(meta$notes))
                meta$notes
              else if (nrow(meta) && !is.na(meta$coverage_note) &&
                        nzchar(meta$coverage_note))
                meta$coverage_note
              else "No description recorded for this variable."

      chips <- tagList()
      if (nrow(meta)) {
        src_label  <- .simplify_source(meta$source)
        is_derived <- .is_computed_source(meta$source)

        # Standard chips: Source, Category, Format, Years.
        chip_specs <- list(
          c("Source",   src_label),
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
          if (is_derived)
            tags$span(class = "dash-modal-chip dash-modal-chip-computed",
                      title = "This value is derived from one or more raw inputs.",
                      "Computed")
        )
      }

      a_uid    <- anchor_uid(); req(a_uid)
      anchor_v <- .SCHOOLS_WIDE[[metric]][.SCHOOLS_WIDE$unitid == a_uid][1]
      rug      <- .build_rug_data(metric)
      univ     <- dashboard_universe()

      # Larger strip in the modal: full container width up to 720px.
      big_strip <- .dashboard_strip_svg(univ[[metric]], anchor_v,
                                         rug_data = rug,
                                         width = 720, height = 80)

      # Universe percentile helper for the per-school table.
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
      tbl_rows$pct <- vapply(tbl_rows$value, pct, numeric(1))
      tbl_rows$pct_fmt <- ifelse(is.na(tbl_rows$pct), "—",
                                  sprintf("%.0f", tbl_rows$pct))

      # Order: Anchor first, then by descending raw value.
      anchor_ix    <- which(tbl_rows$action == "Anchor")
      other_ix     <- setdiff(seq_len(nrow(tbl_rows)), anchor_ix)
      other_order  <- other_ix[order(-tbl_rows$value[other_ix])]
      tbl_rows     <- tbl_rows[c(anchor_ix, other_order), , drop = FALSE]

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

      showModal(modalDialog(
        title = tagList(
          tags$div(class = "dash-modal-title", dn),
          tags$div(class = "dash-modal-chips", chips)
        ),
        size = "l",
        easyClose = TRUE,
        fade = TRUE,
        footer = tagList(
          actionButton(ns("dash_modal_open_inspector"),
                       "Open in inspector",
                       icon = icon("chart-area"),
                       class = "btn btn-outline-primary",
                       `data-metric` = metric),
          modalButton("Close")
        ),
        div(class = "dash-modal-body",
          tags$p(class = "dash-modal-desc", desc),
          tags$div(class = "dash-modal-strip-wrap", big_strip),
          tags$div(class = "dash-modal-legend",
            lapply(names(.DASH_ACTION_COLORS), function(a) {
              tags$span(class = "dash-modal-legend-item",
                tags$span(class = "dash-modal-legend-swatch",
                          style = sprintf("background: %s;",
                                           unname(.DASH_ACTION_COLORS[a]))),
                a)
            })
          ),
          tags$h6("Per-school values"),
          table_tag
        )
      ))

      # Stash the metric for the inspector hand-off button below.
      session$userData$dash_modal_metric <- metric
    })

    # "Open in inspector" button inside the modal: pre-select the metric
    # and scroll the inspector into view, then close the modal.
    observeEvent(input$dash_modal_open_inspector, {
      m <- session$userData$dash_modal_metric
      if (is.null(m)) return()
      updateSelectizeInput(session, "inspect_metric", selected = m)
      removeModal()
      shinyjs::runjs(sprintf(
        "var el = document.getElementById('%s'); if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});",
        ns("variable_inspector")))
    })

    # -------------------------------------------------------------------------
    # Variable inspector — pick one variable, see per-school values and a
    # distribution plot with the cohort overlaid. Modeled on Side-by-Side's
    # click-to-expand modal but rendered inline below the cohort table since
    # the cohort context is the whole reason for being on this tab.
    # -------------------------------------------------------------------------

    # Action color palette used in plotly markers and the per-school value
    # table. Matches the cohort row tinting.
    .COHORT_ACTION_COLORS <- c(
      "Keep"     = "#2e7d32",
      "Remove"   = "#b53737",
      "Maybe"    = "#AC9E94",
      "Proposed" = "#602D89",
      "Possible" = "#7591b3"
    )

    # Variable picker choices, grouped by category. Only numeric clustering /
    # descriptive variables that exist in .SCHOOLS_WIDE. Display_name → metric.
    inspector_choice_groups <- reactive({
      vars_df <- .VARIABLES %>%
        dplyr::filter(metric %in% names(.SCHOOLS_WIDE)) %>%
        dplyr::filter(!is.na(display_name))
      vars_df <- vars_df[order(vars_df$category, vars_df$display_name), ]

      groups <- split(vars_df, vars_df$category)
      # selectizeInput optgroups: named list, each entry a named character vec
      lapply(groups, function(g) {
        v <- g$metric
        names(v) <- g$display_name
        v
      })
    })

    output$variable_inspector <- renderUI({
      df <- cohort_state()
      if (is.null(df) || !nrow(df)) return(NULL)

      groups <- inspector_choice_groups()

      class_choices <- {
        cls <- sort(unique(stats::na.omit(.SCHOOLS$usnews_classification)))
        v <- cls
        names(v) <- .prettify_classification(cls)
        v
      }
      sector_choices <- c("Public" = "public",
                          "Private (nonprofit)" = "private_nfp")

      tagList(
        tags$hr(class = "cohort-section-divider"),
        h4("Variable inspector"),
        p(class = "section-intro",
          "Pick a variable to see how the cohort sits on it: each school's ",
          "value, a distribution across a chosen comparison pool, and the ",
          "anchor's percentile against that pool."),

        div(class = "cohort-inspector-controls",
          div(class = "cohort-inspector-control-row",
            selectizeInput(ns("inspect_metric"),
                           label = "Variable",
                           choices = groups,
                           selected = "total_enrollment_fall",
                           width = "100%",
                           options = list(placeholder = "Type to search variables"))
          ),
          div(class = "cohort-inspector-control-row cohort-pool-controls",
            div(class = "cohort-pool-control",
              selectizeInput(ns("pool_classification"),
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
              selectizeInput(ns("pool_sector"),
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
          uiOutput(ns("pool_description"))
        ),

        uiOutput(ns("inspector_body"))
      )
    })

    # Reactive pool — ranked universe filtered by the inspector's
    # classification/sector multi-selects. Empty selection means no filter
    # on that field.
    inspector_pool <- reactive({
      pool <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$in_ranked_universe %in% TRUE, ,
                            drop = FALSE]
      cls <- input$pool_classification
      sec <- input$pool_sector
      if (length(cls))
        pool <- pool[pool$usnews_classification %in% cls, , drop = FALSE]
      if (length(sec))
        pool <- pool[pool$control_grp %in% sec, , drop = FALSE]
      pool
    })

    output$pool_description <- renderUI({
      pool <- inspector_pool()
      cls <- input$pool_classification
      sec <- input$pool_sector
      parts <- c()
      if (length(cls))
        parts <- c(parts, sprintf("US News: %s",
                                   paste(.prettify_classification(cls),
                                         collapse = ", ")))
      if (length(sec))
        parts <- c(parts, sprintf("Sector: %s",
                                   paste(.prettify_control(sec),
                                         collapse = ", ")))
      label <- if (length(parts)) paste(parts, collapse = "  |  ")
               else "Full ranked universe (no pool filter)"
      tags$div(class = "cohort-pool-description",
        tags$small(
          tags$strong(sprintf("Pool: %s institutions  ",
                              format(nrow(pool), big.mark = ","))),
          tags$span(class = "text-muted", label)
        )
      )
    })

    # The body of the inspector, redrawn whenever the metric or cohort changes.
    output$inspector_body <- renderUI({
      metric <- input$inspect_metric
      req(metric)
      df    <- cohort_state();  req(df, nrow(df) > 0)
      a_uid <- anchor_uid();    req(a_uid)

      tagList(
        plotlyOutput(ns("inspector_plot"), height = "420px"),
        uiOutput(ns("inspector_stats")),
        h5("Per-school values"),
        DT::DTOutput(ns("inspector_table"))
      )
    })

    # ---- Inspector: plotly distribution with cohort rug ----
    output$inspector_plot <- renderPlotly({
      metric <- input$inspect_metric
      req(metric)
      df    <- cohort_state();  req(df, nrow(df) > 0)
      a_uid <- anchor_uid();    req(a_uid)
      req(metric %in% names(.SCHOOLS_WIDE))

      pool_df <- inspector_pool()
      pool_vals <- pool_df[[metric]]
      pool_vals <- pool_vals[is.finite(pool_vals)]
      validate(need(length(pool_vals) >= 5,
                    "Not enough finite values to plot a distribution."))

      a_val <- .SCHOOLS_WIDE[[metric]][.SCHOOLS_WIDE$unitid == a_uid][1]
      anchor_name <- .SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1]

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA
      x_label <- if (nrow(meta_row) && !is.na(meta_row$display_name))
                   meta_row$display_name else metric

      # Freedman-Diaconis binwidth, floored by data range / 40
      iqr <- diff(stats::quantile(pool_vals, c(0.25, 0.75),
                                  na.rm = TRUE, names = FALSE))
      bw  <- max(2 * iqr / length(pool_vals)^(1/3),
                 diff(range(pool_vals)) / 40)

      x_hover_fmt <- switch(
        as.character(fmt) %||% "",
        currency   = "$%{x:,.0f}",
        percentage = "%{x:.1f}%",  # single % — plotly hovertemplate is not d3-escaped
        count      = "%{x:,.0f}",
        ratio      = "%{x:.2f}",
        "%{x:.4g}"
      )

      pool_label <- if (length(input$pool_classification) ||
                        length(input$pool_sector))
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

      # Cohort schools as rug markers at y = 0, color-coded by action.
      cohort_uids <- df$unitid
      cohort_vals <- .SCHOOLS_WIDE[[metric]][match(cohort_uids,
                                                   .SCHOOLS_WIDE$unitid)]
      cohort_actions <- as.character(df$action)
      cohort_names   <- df$instnm
      ok <- is.finite(cohort_vals)

      for (act in names(.COHORT_ACTION_COLORS)) {
        ix <- which(ok & cohort_actions == act)
        if (!length(ix)) next
        p <- p %>% add_markers(
          x = cohort_vals[ix],
          y = rep(0, length(ix)),
          name = act,
          text = cohort_names[ix],
          marker = list(symbol = "diamond", size = 11,
                        color = unname(.COHORT_ACTION_COLORS[act]),
                        line = list(color = "#FFFFFF", width = 1)),
          hovertemplate = paste0("<b>%{text}</b><br>",
                                  sprintf("Action: %s<br>", act),
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
        cohc_modebar(filename_root = "cohort_inspector")
    })

    # ---- Inspector: per-school table ----
    output$inspector_table <- DT::renderDT({
      metric <- input$inspect_metric
      req(metric)
      df    <- cohort_state();  req(df, nrow(df) > 0)
      a_uid <- anchor_uid();    req(a_uid)
      req(metric %in% names(.SCHOOLS_WIDE))

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA

      # Build display table: anchor row first, then cohort rows.
      uids <- c(a_uid, df$unitid)
      actions <- c("Anchor", as.character(df$action))
      names_v <- c(.SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1], df$instnm)
      states  <- c(.SCHOOLS$stabbr[.SCHOOLS$unitid == a_uid][1], df$stabbr)
      raw_vals <- .SCHOOLS_WIDE[[metric]][match(uids, .SCHOOLS_WIDE$unitid)]

      # Compute percentile rank against the inspector's selected pool
      pool_df <- inspector_pool()
      pool_vals <- pool_df[[metric]]; pool_vals <- pool_vals[is.finite(pool_vals)]
      pct <- vapply(raw_vals, function(v) {
        if (!is.finite(v) || !length(pool_vals)) return(NA_real_)
        100 * mean(pool_vals < v)
      }, numeric(1))

      tbl <- data.frame(
        Action      = actions,
        School      = names_v,
        State       = states,
        Value       = vapply(raw_vals, function(v) .format_value(v, fmt),
                             character(1)),
        Percentile  = ifelse(is.na(pct), "—",
                             sprintf("%.0f", pct)),
        `_sort`     = ifelse(is.finite(raw_vals), raw_vals, -Inf),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )

      # Color action cells in DT via rowCallback. Simpler: use formatStyle
      # via DT::datatable.
      dt <- DT::datatable(
        tbl,
        rownames = FALSE,
        selection = "none",
        options = list(
          pageLength = 50,
          dom = "tip",
          order = list(list(5, "desc")),  # sort by hidden numeric
          columnDefs = list(
            list(visible = FALSE, targets = 5),  # hide _sort
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
            c("Anchor",  names(.COHORT_ACTION_COLORS)),
            c("#602D89", unname(.COHORT_ACTION_COLORS))
          ),
          fontWeight = "600"
        )
      dt
    })

    # ---- Inspector: summary stats ----
    output$inspector_stats <- renderUI({
      metric <- input$inspect_metric
      req(metric)
      df    <- cohort_state();  req(df, nrow(df) > 0)
      a_uid <- anchor_uid();    req(a_uid)
      req(metric %in% names(.SCHOOLS_WIDE))

      meta_row <- .VARIABLES[match(metric, .VARIABLES$metric), , drop = FALSE]
      fmt <- if (nrow(meta_row)) meta_row$format else NA

      a_val <- .SCHOOLS_WIDE[[metric]][.SCHOOLS_WIDE$unitid == a_uid][1]
      pool_df <- inspector_pool()
      pool_vals <- pool_df[[metric]]; pool_vals <- pool_vals[is.finite(pool_vals)]

      # Cohort = everything committed to the main list (mirrors budget).
      in_cohort_uids <- df$unitid[df$action %in% c("Keep", "Maybe",
                                                     "Remove", "Proposed")]
      cohort_vals <- .SCHOOLS_WIDE[[metric]][match(in_cohort_uids,
                                                    .SCHOOLS_WIDE$unitid)]
      cohort_vals <- cohort_vals[is.finite(cohort_vals)]

      pct_anchor <- if (is.finite(a_val) && length(pool_vals))
                       sprintf("%.0fth", 100 * mean(pool_vals < a_val))
                     else "—"

      tags$dl(class = "distribution-stats",
        tags$dt("Anchor"),
        tags$dd(sprintf("%s  (%s pct.)",
                        .format_value(a_val, fmt), pct_anchor)),
        tags$dt("Cohort median"),
        tags$dd(if (length(cohort_vals))
                  .format_value(stats::median(cohort_vals), fmt) else "—"),
        tags$dt("Cohort range"),
        tags$dd(if (length(cohort_vals))
                  sprintf("%s to %s",
                          .format_value(min(cohort_vals), fmt),
                          .format_value(max(cohort_vals), fmt))
                else "—"),
        tags$dt("Cohort N reporting"),
        tags$dd(sprintf("%d of %d", length(cohort_vals),
                        length(in_cohort_uids))),
        tags$dt("Pool N"),
        tags$dd(format(length(pool_vals), big.mark = ","))
      )
    })

    # -------------------------------------------------------------------------
    # Data export — handler bound to the sidebar's Download button.
    # The cohort is exported as a CSV with the anchor row at the top and
    # all clustering + descriptive variables joined in.
    # -------------------------------------------------------------------------
    output$download_cohort_csv <- downloadHandler(
      filename = function() {
        a_uid <- anchor_uid()
        anchor_slug <- if (!is.null(a_uid)) {
          nm <- .SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1]
          gsub("[^A-Za-z0-9]+", "_", nm)
        } else "anchor"
        sprintf("cohort_%s_%s.zip", anchor_slug, format(Sys.time(), "%Y%m%d"))
      },
      contentType = "application/zip",
      content = function(file) {
        df    <- cohort_state()
        a_uid <- anchor_uid()

        # Assemble the cohort export the same way as before: anchor row
        # prepended, then cohort_state, then all of .SCHOOLS_WIDE joined in.
        if (is.null(df) || !nrow(df)) {
          out <- tibble::tibble()
        } else {
          a_row <- if (!is.null(a_uid))
                     tibble::tibble(
                       unitid = a_uid,
                       instnm_file = NA_character_,
                       instnm = .SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1],
                       stabbr = .SCHOOLS$stabbr[.SCHOOLS$unitid == a_uid][1],
                       action = "Anchor"
                     )
                   else NULL

          cohort_out <- df %>%
            dplyr::mutate(action = as.character(action)) %>%
            dplyr::select(unitid, instnm_file, instnm, stabbr, action)

          out <- dplyr::bind_rows(a_row, cohort_out)

          wide_cols <- setdiff(names(.SCHOOLS_WIDE), c("instnm", "stabbr"))
          wide_slice <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid %in% out$unitid,
                                      wide_cols, drop = FALSE]
          out <- dplyr::left_join(out, wide_slice, by = "unitid")

          # Workaround: .SCHOOLS_WIDE inherits a column collision from
          # global.R (earnings_ratio appears in both .SCHOOLS and the
          # facts-derived wide matrix), surfacing as `.x` / `.y` suffixed
          # columns. Coalesce any such pairs back into a single column so
          # the export and codebook stay clean. Tracked separately for
          # upstream fix.
          x_cols <- grep("\\.x$", names(out), value = TRUE)
          for (xc in x_cols) {
            base <- sub("\\.x$", "", xc)
            yc   <- paste0(base, ".y")
            if (yc %in% names(out)) {
              out[[base]] <- dplyr::coalesce(out[[xc]], out[[yc]])
              out[[xc]] <- NULL
              out[[yc]] <- NULL
            }
          }
        }

        # Build the codebook from the actual export columns so the
        # documentation always matches the data file.
        codebook <- if (ncol(out)) .build_cohort_codebook(out)
                    else tibble::tibble()

        # README narrating what's in the bundle. Plain ASCII so it opens
        # cleanly in any text editor on Windows / macOS / Linux.
        a_name <- if (!is.null(a_uid))
                    .SCHOOLS$instnm[.SCHOOLS$unitid == a_uid][1] else "(none)"
        n_rows <- nrow(out)
        readme_lines <- c(
          "Peer Schools Explorer — Cohort export",
          "=====================================",
          "",
          sprintf("Generated: %s",
                  format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
          sprintf("Anchor:    %s", a_name),
          sprintf("Rows:      %d  (includes the anchor row at the top)",
                  n_rows),
          "",
          "Files in this bundle:",
          "  cohort.csv    - one row per school, all clustering and",
          "                  descriptive variables joined in. The anchor",
          "                  row has Action = Anchor.",
          "  codebook.csv  - one row per column of cohort.csv, with type,",
          "                  category, display name, description, format,",
          "                  source, and notes.",
          "  README.txt    - this file.",
          "",
          "Action values:",
          "  Anchor   - the anchor (home) institution.",
          "  Keep     - in the original peer list, retained.",
          "  Maybe    - in the original peer list, undecided.",
          "  Remove   - in the original peer list, marked for replacement.",
          "  Proposed - user-added candidate committed to the cohort.",
          "  Possible - user-added candidate still being brainstormed.",
          ""
        )

        # Stage all three files in a temp dir, then zip into `file`.
        td <- tempfile("cohort_bundle_")
        dir.create(td)
        on.exit(unlink(td, recursive = TRUE), add = TRUE)

        readr::write_csv(out,      file.path(td, "cohort.csv"))
        readr::write_csv(codebook, file.path(td, "codebook.csv"))
        writeLines(readme_lines,   file.path(td, "README.txt"))

        zip::zip(
          zipfile = file,
          files   = c("cohort.csv", "codebook.csv", "README.txt"),
          root    = td
        )
      }
    )

    # Main rendered view
    output$cohort_view <- renderUI({
      df    <- cohort_state()
      a_uid <- anchor_uid()
      if (is.null(df)) {
        return(div(class = "note-box",
                   tags$strong("No cohort loaded. "),
                   "The bundled NECHE cohort file was not found at ",
                   tags$code(.DEFAULT_COHORT_FILE), ". ",
                   "Use the Add-a-school control in the sidebar to start ",
                   "building a cohort from scratch."))
      }
      wide_df <- cohort_wide(); req(wide_df)

      # Synthetic anchor row, prepended to the main cohort table so the
      # anchor school appears in-list with an Anchor badge.
      anchor_meta <- .SCHOOLS[.SCHOOLS$unitid == a_uid, , drop = FALSE]
      anchor_row_df <- if (nrow(anchor_meta))
        tibble::tibble(
          unitid = anchor_meta$unitid,
          instnm_file = NA_character_,
          instnm = anchor_meta$instnm,
          stabbr = anchor_meta$stabbr,
          action = factor("Anchor",
                          levels = c("Anchor", .COHORT_ACTIONS)),
          origin = factor("anchor",
                          levels = c("original", "addition", "anchor"))
        ) else NULL

      # Partition by action.
      #   IN  side (left column):  Anchor + Keep + Maybe + Proposed
      #   OUT side (right column): Possible (top) + Remove (bottom)
      # Within each side, sort by action group, then alphabetically by
      # school name. Remove sits below Possible on the Out side because
      # Possibles are the active brainstorm queue (most interactive),
      # while Removes are settled "we're done with these" rows.
      in_cohort  <- df[df$action %in% c("Keep", "Maybe", "Proposed"), ]
      out_cohort <- df[df$action %in% c("Remove", "Possible"), ]

      in_order  <- c("Keep", "Maybe", "Proposed")
      out_order <- c("Possible", "Remove")
      in_cohort  <- in_cohort[order(match(as.character(in_cohort$action),
                                            in_order),
                                      in_cohort$instnm), ]
      out_cohort <- out_cohort[order(match(as.character(out_cohort$action),
                                             out_order),
                                       out_cohort$instnm), ]

      # In-cohort active count: Keep + Maybe + Proposed only. Anchor is
      # NOT counted (the question is "how many peers do we have", not
      # "how many rows are in the In column"). Remove is also excluded
      # since those rows are queued for replacement.
      n_active   <- nrow(in_cohort)
      n_target   <- .COHORT_TARGET_SIZE
      n_remain   <- max(0L, n_target - n_active)
      n_overflow <- max(0L, n_active - n_target)
      n_out      <- nrow(out_cohort)

      remaining_msg <- if (n_overflow > 0)
        sprintf("%d over the target", n_overflow)
      else if (n_remain == 0)
        "cohort is full"
      else
        sprintf("%d slot%s remaining", n_remain,
                if (n_remain == 1) "" else "s")

      tagList(
        tags$div(class = "cohort-two-col",
          tags$section(class = "cohort-section cohort-section-in",
            tags$h5(sprintf("In Cohort — %d of %d", n_active, n_target),
                    tags$small(class = "cohort-budget-pill",
                                remaining_msg)),
            tags$p(class = "section-intro",
              tags$small(
                "Anchor + ", tags$strong("Keep"), " / ",
                tags$strong("Maybe"), " / ", tags$strong("Proposed"),
                ". The anchor doesn't count toward the ", n_target,
                "-school target. Click ",
                tags$span(class = "cohort-inline-arrow", "→"),
                " on any row to move it Out.")),
            .cohort_table(in_cohort, wide_df, side = "in",
                          anchor_row_df = anchor_row_df)
          ),

          tags$section(class = "cohort-section cohort-section-out",
            tags$h5(sprintf("Out / Considering (%d)", n_out)),
            tags$p(class = "section-intro",
              tags$small(
                tags$strong("Possible"),
                " (brainstormed additions not yet committed) at top, ",
                tags$strong("Remove"),
                " (originals flagged for replacement) at bottom. ",
                "Click ", tags$span(class = "cohort-inline-arrow", "←"),
                " to move a row back In.")),
            if (n_out > 0)
              .cohort_table(out_cohort, wide_df, side = "out")
            else
              tags$div(class = "cohort-empty-col",
                tags$em("Nothing marked for removal or being considered."))
          )
        )
      )
    })

    # Expose state for future phases (suggestions, finalize)
    list(
      anchor_uid    = anchor_uid,
      cohort_state  = cohort_state
    )
  })
}
