# =============================================================================
# Variable Catalog generator
# Holy Cross peer-comparison project
#
# Reads:  output/{aid,adm,enr,out,fin,ath}_variables.csv
# Writes: docs/VARIABLE_CATALOG.md
#
# Produces a stakeholder-readable markdown catalog of every variable the
# app exposes, grouped by category. Re-run any time variables are added
# or relabeled. The output file can be hand-edited after generation if
# you want to override the auto-generated wording for specific entries;
# re-running this script will overwrite those edits, so save them
# elsewhere if you want them preserved.
#
# Usage:
#   Rscript R/tools/generate_variable_catalog.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(purrr); library(tibble)
})

# Resolve repo root: prefer the directory the script is being sourced from
# (works under both source() and Rscript), fall back to getwd().
REPO_ROOT <- tryCatch({
  script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(script_arg))
    normalizePath(file.path(dirname(sub("^--file=", "", script_arg)),
                             "..", ".."),
                  mustWork = FALSE)
  else getwd()
}, error = function(e) getwd())
if (!dir.exists(REPO_ROOT)) REPO_ROOT <- getwd()
OUTPUT_DIR <- file.path(REPO_ROOT, "output")
DOCS_DIR   <- file.path(REPO_ROOT, "docs")
OUT_PATH   <- file.path(DOCS_DIR, "VARIABLE_CATALOG.md")

if (!dir.exists(DOCS_DIR)) dir.create(DOCS_DIR, recursive = TRUE)

# ---- Load every module's variable catalog -----------------------------------
MODULE_KEYS <- c("aid", "adm", "enr", "out", "fin", "ath")

all_vars <- map_dfr(MODULE_KEYS, function(mk) {
  vp <- file.path(OUTPUT_DIR, paste0(mk, "_variables.csv"))
  if (!file.exists(vp)) {
    warning(sprintf("Skipping module %s — missing %s", mk, vp))
    return(NULL)
  }
  read_csv(vp, show_col_types = FALSE) %>% mutate(module = mk)
})

# ---- Source label simplification (mirrors mod_cohort's .simplify_source) ----
SOURCE_LABELS <- c(
  ipeds          = "IPEDS",
  ipeds_derived  = "IPEDS (computed)",
  ccihe          = "Carnegie 2025 Data File",
  cds_ai         = "Common Data Set (via Academic Insights)",
  cds_ai_derived = "Common Data Set (computed)",
  scorecard      = "College Scorecard",
  eada           = "EADA (Equity in Athletics Disclosure Act)",
  eada_derived   = "EADA (computed)"
)
simplify_source <- function(s) {
  ifelse(is.na(s) | !nzchar(s),
         "Unknown source",
         ifelse(s %in% names(SOURCE_LABELS), SOURCE_LABELS[s], s))
}

# Friendly category headings.
CATEGORY_LABELS <- c(
  admissions  = "Selectivity & Admissions",
  enrollment  = "Enrollment & Composition",
  resources   = "Resources",
  finance     = "Finance",
  outcomes    = "Outcomes & Programs",
  aid         = "Financial Aid",
  athletics   = "Athletics (EADA)"
)
category_label <- function(c) {
  ifelse(is.na(c) | !nzchar(c), "(Uncategorized)",
         ifelse(c %in% names(CATEGORY_LABELS), CATEGORY_LABELS[c],
                str_to_title(c)))
}

# ---- Compose markdown -------------------------------------------------------
md_escape <- function(s) {
  if (is.na(s)) "" else gsub("\\|", "\\\\|", as.character(s))
}

build_catalog_md <- function(vars_df) {
  vars_df <- vars_df %>%
    mutate(
      category_label = category_label(category),
      source_label   = simplify_source(source),
      use_label      = case_when(
        use_type == "clustering"     ~ "Used in peer distance",
        use_type == "descriptive"    ~ "Descriptive only",
        use_type == "exploratory"    ~ "Exploratory",
        TRUE                         ~ as.character(use_type)
      )
    ) %>%
    arrange(category_label, display_name)

  # Header
  hdr <- c(
    "# Variable Catalog",
    "",
    "Every numeric variable the Peer Schools Explorer surfaces, grouped by category.",
    "",
    sprintf("Generated from `output/*_variables.csv` on %s.  Re-run `Rscript R/tools/generate_variable_catalog.R` after adding variables.",
            format(Sys.Date(), "%B %d, %Y")),
    "",
    "**Reading the columns:**",
    "",
    "- **Variable** — the display name shown throughout the app.",
    "- **Metric ID** — internal column name used in `.SCHOOLS_WIDE` and the facts CSVs. The Side-by-Side inspector, the cohort dashboard, and the codebook export all key off this.",
    "- **Format** — how the value is rendered: `percentage`, `count`, `currency`, `ratio`, `score`.",
    "- **Source** — where the value comes from.",
    "- **Role** — whether the variable is included in peer-distance computation (clustering) or shown for reference only (descriptive).",
    "- **Notes** — coverage caveats and methodological notes worth knowing.",
    "",
    "---",
    ""
  )

  # One section per category
  by_cat <- split(vars_df, vars_df$category_label)
  sections <- imap(by_cat, function(g, cat_name) {
    n <- nrow(g)
    rows <- pmap_chr(g, function(metric, display_name, format,
                                  source_label, use_label,
                                  coverage_note, notes, ...) {
      desc <- if (!is.na(notes) && nzchar(notes)) notes
              else if (!is.na(coverage_note) && nzchar(coverage_note))
                coverage_note
              else ""
      sprintf("| %s | `%s` | %s | %s | %s | %s |",
              md_escape(display_name),
              md_escape(metric),
              md_escape(format %||% ""),
              md_escape(source_label),
              md_escape(use_label),
              md_escape(desc))
    })
    c(
      sprintf("## %s  (%d variables)", cat_name, n),
      "",
      "| Variable | Metric ID | Format | Source | Role | Notes |",
      "|---|---|---|---|---|---|",
      rows,
      ""
    )
  })

  c(hdr, unlist(sections, use.names = FALSE))
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

md <- build_catalog_md(all_vars)
writeLines(md, OUT_PATH)

cat(sprintf("Wrote %d variables across %d categories to %s\n",
            nrow(all_vars),
            length(unique(category_label(all_vars$category))),
            OUT_PATH))
