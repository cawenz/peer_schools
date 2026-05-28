# =============================================================================
# Codebook builder. Combines all 5 modules' *_variables.csv into a single
# tibble for the download bundle. The columns are the union of what each
# module records; rows are sorted by category then metric so the codebook
# reads naturally when opened in Excel or a data viewer.
# =============================================================================

build_codebook <- function(variables_df = .VARIABLES) {
  cols <- c("metric", "category", "display_name", "source",
            "ipeds_table_or_formula", "use_type", "comparison_scope",
            "format", "neche_peer_set", "neche_dashboard",
            "coverage_note", "notes")
  cols <- intersect(cols, names(variables_df))

  variables_df %>%
    select(all_of(cols)) %>%
    arrange(category, metric)
}
