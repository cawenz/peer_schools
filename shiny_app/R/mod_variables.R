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
      "in the peer-distance calculation. Filter by category or source, ",
      "search the names or descriptions, and click any row for the full ",
      "definition."),

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

    # Build a working frame with pretty labels.
    vars_df <- reactive({
      df <- .VARIABLES
      df$category_pretty <- .category_label(df$category)
      df$source_pretty   <- .source_label(df$source)
      df$role_pretty     <- .role_label(df$use_type)
      df$description     <- vapply(seq_len(nrow(df)), function(i) {
        if (!is.na(df$notes[i]) && nzchar(df$notes[i])) df$notes[i]
        else if (!is.na(df$coverage_note[i]) && nzchar(df$coverage_note[i]))
          df$coverage_note[i]
        else NA_character_
      }, character(1))
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

    output$var_table <- DT::renderDT({
      df <- filtered_df()
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

      DT::datatable(
        display_df,
        rownames = FALSE,
        selection = list(mode = "single", target = "row"),
        options = list(
          pageLength = 25,
          dom = "ftip",   # search box + table + info + pagination
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
      )
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
        div(class = "asp-modal-body",
          tags$div(class = "dash-modal-chips", chips),
          if (!is.na(row$description))
            tags$p(class = "dash-modal-desc", row$description),
          # Show the comparison-scope and (if present) the formula notes
          # as a secondary detail block.
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
