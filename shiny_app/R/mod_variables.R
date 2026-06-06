# =============================================================================
# Variables tab
#
# A native, searchable browser of every variable the app exposes. Lives in
# the Help / reference part of the navbar so users have a stable answer
# to "what does this metric actually measure?" without having to open a
# file outside the app.
#
# Reads from .VARIABLES (the global catalog of metric metadata). Each row
# is clickable; the modal shows the variable's full definition plus the
# source, format, theme, and role.
# =============================================================================

variablesUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Variables"),
    p(class = "section-intro",
      "Every variable the app surfaces, with the source, format, and role ",
      "in the peer-distance calculation."),

    # ---- Instructions block --------------------------------------------
    div(class = "var-instructions",
      tags$h6("How to use this page"),
      tags$ol(class = "var-instructions-steps",
        tags$li(tags$strong("Filter"),
                " by Category, Source, or Role (the three pickers above ",
                "the table) to narrow the list. The pickers cascade — ",
                "choices in Source and Role only show options that ",
                "actually appear given your Category selection."),
        tags$li(tags$strong("Search"),
                " the table's built-in search box (top right of the ",
                "table) to look up variables by name."),
        tags$li(tags$strong("Click any row"),
                " to open the full definition: what the variable ",
                "measures, the data source, caveats, and how it's computed.")
      ),

      tags$h6("What the columns mean"),
      tags$dl(class = "var-glossary",
        tags$dt("Category"),
        tags$dd("The analytical theme — Selectivity & Admissions, ",
                 "Enrollment, Resources, Finance, Outcomes, Financial Aid, ",
                 "Athletics. Used to group similar variables and to wire ",
                 "the theme-weight sliders in the Peer Search sidebar."),

        tags$dt("Source"),
        tags$dd("Where the underlying data comes from: ",
                 tags$strong("IPEDS"), " (the federal survey, mandatory ",
                 "for any institution receiving Title IV funds), ",
                 tags$strong("Carnegie"), " (institutional classifications), ",
                 tags$strong("Common Data Set"), " (voluntary survey, ",
                 "~45% response rate), ",
                 tags$strong("College Scorecard"), " (federal student ",
                 "outcomes), or ",
                 tags$strong("EADA"), " (Equity in Athletics Disclosure Act). ",
                 "Computed sources are derived from one or more raw inputs."),

        tags$dt("Format"),
        tags$dd("How values are rendered: ",
                 tags$em("count"), " (whole numbers), ",
                 tags$em("percentage"), " (0–100), ",
                 tags$em("currency"), " (dollars), or ",
                 tags$em("ratio"), " (unbounded numeric)."),

        tags$dt("Role"),
        tags$dd(tags$strong("Used in peer distance"),
                 " variables feed the weighted Euclidean similarity ",
                 "calculation. ",
                 tags$strong("Descriptive only"),
                 " variables are shown on Side-by-Side, dashboards, ",
                 "and the inspector but do not influence which peers ",
                 "get returned. ",
                 tags$strong("Exploratory"),
                 " variables are tracked but flagged as work-in-progress."),

        tags$dt("Notes"),
        tags$dd("Short description shown inline. Full plain-English ",
                 "definitions, caveats, and computation details ",
                 "appear in the click-to-open modal.")
      )
    ),

    # Compact filter bar above the table.
    tags$div(class = "var-filter-bar",
      tags$div(class = "var-filter",
        tags$label("Category"),
        selectizeInput(ns("filter_category"),
                       label = NULL,
                       choices = NULL, multiple = TRUE,
                       width = "100%",
                       options = list(placeholder = "All categories",
                                       plugins = list("remove_button")))
      ),
      tags$div(class = "var-filter",
        tags$label("Source"),
        selectizeInput(ns("filter_source"),
                       label = NULL,
                       choices = NULL, multiple = TRUE,
                       width = "100%",
                       options = list(placeholder = "All sources",
                                       plugins = list("remove_button")))
      ),
      tags$div(class = "var-filter",
        tags$label("Role"),
        selectizeInput(ns("filter_role"),
                       label = NULL,
                       choices = c("Used in peer distance" = "clustering",
                                    "Descriptive only"      = "descriptive",
                                    "Exploratory"           = "exploratory"),
                       multiple = TRUE,
                       width = "100%",
                       options = list(placeholder = "All roles",
                                       plugins = list("remove_button")))
      )
    ),

    # ---- DEBUG: minimal table that must render if DT is wired correctly ----
    tags$div(style = "background:#fef2cd; padding:0.5rem 1rem; margin-bottom:0.5rem; border:1px dashed #b58900;",
      tags$strong("DEBUG table (should always render with 3 rows): "),
      DT::DTOutput(ns("debug_table"))),

    DT::DTOutput(ns("var_table"))
  )
}

variablesServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Stakeholder-friendly source / category / role labels ---
    .SRC_LBLS <- c(
      ipeds          = "IPEDS",
      ipeds_derived  = "IPEDS (computed)",
      ccihe          = "Carnegie 2025 Data File",
      cds_ai         = "Common Data Set",
      cds_ai_derived = "Common Data Set (computed)",
      scorecard      = "College Scorecard",
      eada           = "EADA",
      eada_derived   = "EADA (computed)"
    )
    .source_label <- function(s) {
      out <- vapply(s, function(x) {
        if (is.na(x) || !nzchar(x)) "Unknown"
        else if (x %in% names(.SRC_LBLS)) .SRC_LBLS[[x]]
        else x
      }, character(1))
      unname(out)
    }

    .CAT_LBLS <- c(
      admissions = "Selectivity & Admissions",
      enrollment = "Enrollment & Composition",
      resources  = "Resources",
      finance    = "Finance",
      outcomes   = "Outcomes & Programs",
      aid        = "Financial Aid",
      athletics  = "Athletics (EADA)"
    )
    .category_label <- function(c) {
      out <- vapply(c, function(x) {
        if (is.na(x) || !nzchar(x)) "(Uncategorized)"
        else if (x %in% names(.CAT_LBLS)) .CAT_LBLS[[x]]
        else stringr::str_to_title(x)
      }, character(1))
      unname(out)
    }

    .role_label <- function(u) {
      out <- vapply(u, function(x) {
        if (is.na(x)) "(Unspecified)"
        else if (x == "clustering")  "Used in peer distance"
        else if (x == "descriptive") "Descriptive only"
        else if (x == "exploratory") "Exploratory"
        else x
      }, character(1))
      unname(out)
    }

    # ---- Hand-curated plain-English description lookup ------------------
    # data/variables_descriptions.csv has shape (metric, description) and
    # is editable in Excel/etc. so non-developers can extend it. Missing
    # entries fall back to coverage_note from the pipeline.
    .desc_lookup <- {
      desc_path <- file.path(
        if (exists(".DATA_DIR")) .DATA_DIR
        else file.path(.PROJECT_ROOT, "data"),
        "variables_descriptions.csv")
      if (file.exists(desc_path)) {
        d <- suppressMessages(readr::read_csv(desc_path,
                                               show_col_types = FALSE))
        setNames(d$description, d$metric)
      } else {
        character(0)
      }
    }
    .human_description <- function(metric) {
      if (length(metric) != 1 || is.na(metric)) return(NA_character_)
      if (!metric %in% names(.desc_lookup)) return(NA_character_)
      v <- unname(.desc_lookup[[metric]])
      # Defensive coercion: lookup could return length 0 (missing) or
      # length > 1 (duplicate key); collapse to a single string.
      if (length(v) == 0) return(NA_character_)
      v <- as.character(v[1])
      if (is.na(v) || !nzchar(v)) return(NA_character_)
      v
    }

    # Build a working frame with pretty labels.
    vars_df <- reactive({
      df <- .VARIABLES
      df$category_pretty <- .category_label(df$category)
      df$source_pretty   <- .source_label(df$source)
      df$role_pretty     <- .role_label(df$use_type)

      # Two description streams:
      #   human_desc : from data/variables_descriptions.csv (preferred)
      #   tech_desc  : pipeline notes / coverage_note (fallback)
      df$human_desc <- vapply(df$metric, .human_description, character(1))
      df$tech_desc  <- vapply(seq_len(nrow(df)), function(i) {
        if (!is.na(df$notes[i]) && nzchar(df$notes[i])) df$notes[i]
        else if (!is.na(df$coverage_note[i]) && nzchar(df$coverage_note[i]))
          df$coverage_note[i]
        else NA_character_
      }, character(1))

      # Combined description shown inline in the table (truncated). Prefer
      # human; fall back to technical.
      df$description <- ifelse(!is.na(df$human_desc),
                                df$human_desc, df$tech_desc)
      df
    })

    # --- Initialize category choices (the top of the cascade) ---
    observe({
      df <- vars_df()
      updateSelectizeInput(session, "filter_category",
                           choices  = sort(unique(df$category_pretty)),
                           selected = character(0),
                           server   = FALSE)
    }, priority = 100)

    # --- Cascading filters ---
    #
    # Source choices are narrowed to those that actually appear in the
    # currently-selected category set. Role choices are further narrowed
    # to those that appear given Category AND Source. Currently-selected
    # values are preserved if they remain valid; values that fall outside
    # the new set are silently dropped.
    #
    # Order matters: Source observer fires first when Category changes,
    # then the Role observer reacts to whatever ended up in Source.

    observe({
      df <- vars_df()
      if (length(input$filter_category))
        df <- df[df$category_pretty %in% input$filter_category, , drop = FALSE]

      avail <- sort(unique(df$source_pretty))
      preserve <- intersect(input$filter_source %||% character(0), avail)
      updateSelectizeInput(session, "filter_source",
                           choices  = avail,
                           selected = preserve,
                           server   = FALSE)
    })

    observe({
      df <- vars_df()
      if (length(input$filter_category))
        df <- df[df$category_pretty %in% input$filter_category, , drop = FALSE]
      if (length(input$filter_source))
        df <- df[df$source_pretty %in% input$filter_source, , drop = FALSE]

      role_map <- c("Used in peer distance" = "clustering",
                    "Descriptive only"      = "descriptive",
                    "Exploratory"           = "exploratory")
      avail_codes <- unique(df$use_type[!is.na(df$use_type)])
      avail_choices <- role_map[role_map %in% avail_codes]

      preserve <- intersect(input$filter_role %||% character(0), avail_choices)
      updateSelectizeInput(session, "filter_role",
                           choices  = avail_choices,
                           selected = preserve,
                           server   = FALSE)
    })

    filtered_df <- reactive({
      df <- vars_df()
      if (length(input$filter_category))
        df <- df[df$category_pretty %in% input$filter_category, ]
      if (length(input$filter_source))
        df <- df[df$source_pretty %in% input$filter_source, ]
      if (length(input$filter_role))
        df <- df[df$use_type %in% input$filter_role, ]
      df
    })

    # DEBUG: minimal 3-row table. If this DOESNT render, DT itself is
    # broken on the Variables tab (CSS / layout / asset path issue). If
    # this DOES render but var_table doesnt, the bug is in the real
    # table-build path below.
    output$debug_table <- DT::renderDT({
      message("[debug-table] render firing")
      DT::datatable(
        data.frame(A = 1:3, B = c("x", "y", "z")),
        rownames = FALSE,
        options = list(dom = "t"))
    })

    output$var_table <- DT::renderDT({
      message("[var-table] render firing")
      df <- tryCatch(filtered_df(),
                     error = function(e) {
                       message("[var-table] filtered_df ERROR: ",
                               conditionMessage(e))
                       NULL
                     })
      if (is.null(df)) {
        return(DT::datatable(
          data.frame(Error = "filtered_df errored — check R console",
                     check.names = FALSE),
          rownames = FALSE))
      }
      message("[var-table] got ", nrow(df), " rows, cols: ",
              paste(names(df), collapse = ","))
      if (!nrow(df)) {
        return(DT::datatable(data.frame(
          Variable = character(),
          Category = character(),
          Format = character(),
          Source = character(),
          Role = character(),
          Notes = character(),
          stringsAsFactors = FALSE,
          check.names = FALSE
        ), rownames = FALSE))
      }

      display_df <- data.frame(
        Variable = df$display_name,
        Category = df$category_pretty,
        Format   = ifelse(is.na(df$format), "—", df$format),
        Source   = df$source_pretty,
        Role     = df$role_pretty,
        Notes    = ifelse(is.na(df$description), "—",
                          # Truncate long notes for table display; full
                          # text lives in the click-to-open modal.
                          ifelse(nchar(df$description) > 120,
                                  paste0(substr(df$description, 1, 117), "..."),
                                  df$description)),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )

      message("[var-table] display_df built: ", nrow(display_df),
              " rows, ", ncol(display_df), " cols")
      tryCatch(
        DT::datatable(
          display_df,
          rownames = FALSE,
          selection = list(mode = "single", target = "row"),
          options = list(
            pageLength = 25,
            dom = "ftip",
            order = list(list(1, "asc"), list(0, "asc")),
            columnDefs = list(
              list(width = "20%", targets = 0),
              list(width = "15%", targets = 1),
              list(width = "10%", targets = 2),
              list(width = "15%", targets = 3),
              list(width = "12%", targets = 4),
              list(width = "28%", targets = 5)
            )
          ),
          class = "compact stripe hover"
        ),
        error = function(e) {
          message("[var-table] datatable() ERROR: ", conditionMessage(e))
          DT::datatable(
            data.frame(Error = paste("DT failed:", conditionMessage(e)),
                       check.names = FALSE),
            rownames = FALSE)
        })
    })

    # ---- Row click -> variable detail modal ----
    observeEvent(input$var_table_rows_selected, {
      df <- filtered_df()
      ix <- input$var_table_rows_selected
      if (!length(ix) || ix > nrow(df)) return()
      row <- df[ix, ]

      chips <- tagList(
        tags$span(class = "dash-modal-chip",
                  tags$strong("Source: "), row$source_pretty),
        tags$span(class = "dash-modal-chip",
                  tags$strong("Category: "), row$category_pretty),
        if (!is.na(row$format))
          tags$span(class = "dash-modal-chip",
                    tags$strong("Format: "), row$format),
        tags$span(class = "dash-modal-chip",
                  tags$strong("Years: "),
                  .VAR_YEARS_LABEL[[row$metric]] %||% "(unknown)"),
        tags$span(class = "dash-modal-chip",
                  tags$strong("Role: "), row$role_pretty),
        if (isTRUE(row$neche_dashboard))
          tags$span(class = "dash-modal-chip dash-modal-chip-computed",
                    "On NECHE dashboard")
      )

      showModal(modalDialog(
        title = tagList(
          tags$div(class = "asp-modal-title", row$display_name),
          tags$div(class = "asp-modal-subtitle",
                   tags$code(row$metric))
        ),
        size = "l", easyClose = TRUE, fade = TRUE,
        footer = modalButton("Close"),
        div(class = "asp-modal-body var-modal-body",
          tags$div(class = "dash-modal-chips", chips),

          # ---- What this measures (hand-curated description first) ----
          tags$h6("What this measures"),
          if (!is.na(row$human_desc)) {
            tags$p(class = "var-modal-human", row$human_desc)
          } else if (!is.na(row$tech_desc)) {
            tagList(
              tags$p(class = "var-modal-tech", row$tech_desc),
              tags$p(class = "var-modal-note text-muted",
                     tags$small(
                       "(No hand-curated description yet — this text is ",
                       "from the pipeline's technical notes. Add an entry ",
                       "for ", tags$code(row$metric),
                       " in ", tags$code("data/variables_descriptions.csv"),
                       " to replace it with plain-English text.")))
          } else {
            tags$p(class = "text-muted",
                   tags$em("No description recorded yet. Add an entry for "),
                   tags$code(row$metric),
                   tags$em(" in "),
                   tags$code("data/variables_descriptions.csv"),
                   tags$em(" to write one."))
          },

          # ---- Caveats / coverage notes (only when distinct from main) ----
          if (!is.na(row$human_desc) && !is.na(row$tech_desc) &&
              row$human_desc != row$tech_desc) tagList(
            tags$h6("Pipeline notes (technical)"),
            tags$p(class = "var-modal-tech text-muted",
                   tags$small(row$tech_desc))
          ),

          # ---- Technical detail block ----
          tags$h6("Technical detail"),
          tags$dl(class = "var-detail-list",
            tags$dt("Comparison scope"),
            tags$dd(if (is.na(row$comparison_scope)) "—"
                     else row$comparison_scope),
            if (!is.na(row$ipeds_table_or_formula) &&
                nzchar(row$ipeds_table_or_formula)) tagList(
              tags$dt("How it's derived"),
              tags$dd(tags$code(row$ipeds_table_or_formula))
            )
          )
        )
      ))

      DT::dataTableProxy(ns("var_table")) %>% DT::selectRows(NULL)
    })

    invisible(NULL)
  })
}
