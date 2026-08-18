# =============================================================================
# global.R — Shiny app startup
#
# Runs once when the app is launched. Loads compute_peers() from
# R/peer_pipeline.R, loads schools.csv and all 5 facts files, and builds a
# wide all-variables matrix used by the side-by-side comparison view.
#
# Working directory at startup is shiny_app/, so project paths are relative
# to the parent: "../R/peer_pipeline.R", "../output/...".
# =============================================================================

suppressMessages({
  library(dplyr); library(tidyr); library(stringr)
  library(readr); library(tibble); library(purrr)
  library(ggplot2)
  library(plotly)
  library(leaflet)
  library(leaflet.extras)   # for addHeatmap
})

# -----------------------------------------------------------------------------
# Defensive: mclust and clustvarsel may be loaded from prior session work
# (variable-selection exploration in R/explore_clustvarsel.R). They export
# `em()`, `map()`, and other names that collide with shiny / bslib internals.
# In some load orders bslib's UI assembly resolves `em()` to mclust::em and
# crashes with "Error in numeric(nrowz) : invalid 'length' argument" before
# the app can render. Unload them here — the app doesn't need them.
# -----------------------------------------------------------------------------
for (pkg in c("clustvarsel", "mclust")) {
  if (paste0("package:", pkg) %in% search())
    try(detach(paste0("package:", pkg), character.only = TRUE, unload = TRUE),
        silent = TRUE)
  if (pkg %in% loadedNamespaces())
    try(unloadNamespace(pkg), silent = TRUE)
}

# -----------------------------------------------------------------------------
# Project paths
# -----------------------------------------------------------------------------
.PROJECT_ROOT <- normalizePath("..", mustWork = TRUE)
.OUTPUT_DIR   <- file.path(.PROJECT_ROOT, "output")
.PIPELINE_R   <- file.path(.PROJECT_ROOT, "R", "peer_pipeline.R")

# -----------------------------------------------------------------------------
# Defensive sourcing of peer_pipeline.R
#
# peer_pipeline.R has un-commented compute_peers() calls in its trailing
# "Usage:" comment block (lines ~568-569 and ~600-605) that execute on
# source(). The functions we need are all defined above the Usage block,
# so read the file, truncate at "# Usage:", and source the truncated
# version. Tracked as a separate bug to fix in source.
# -----------------------------------------------------------------------------
.safe_source_peer_pipeline <- function(path = .PIPELINE_R) {
  txt <- readLines(path, warn = FALSE)
  usage_idx <- grep("^#\\s*Usage:", txt)
  if (length(usage_idx)) txt <- txt[seq_len(usage_idx[1] - 1)]
  tmp <- tempfile(fileext = ".R")
  writeLines(txt, tmp); on.exit(unlink(tmp), add = TRUE)
  sys.source(tmp, envir = globalenv())
}
.safe_source_peer_pipeline()

# Sanity check the functions we need are now in scope.
stopifnot(exists("compute_peers", mode = "function"),
          exists("print_peers",   mode = "function"))

# -----------------------------------------------------------------------------
# Load data once at startup
# -----------------------------------------------------------------------------
.SCHOOLS <- read_csv(file.path(.OUTPUT_DIR, "schools.csv"),
                     show_col_types = FALSE) %>%
  mutate(unitid = as.integer(unitid),
         in_ranked_universe = as.logical(in_ranked_universe))

# Filter to the ranked universe up front. The app's entire purpose is
# institutional benchmarking among schools US News actively ranks
# (National Universities, National Liberal Arts Colleges, Regional
# Universities, Regional Colleges) — the ~1,100 unranked specialty /
# small / for-profit institutions in IPEDS aren't meaningful peers for
# the apps users (IR shops at US 4-year non-profits). Filtering here
# instead of via a sidebar checkbox:
#   - simplifies the candidate-pool UI (one less switch)
#   - raises coverage of CDS-sourced vars (most pass the 70% threshold
#     in the ranked universe but failed in the full universe)
#   - shrinks .SCHOOLS_WIDE / .FACTS for downstream perf
# in_ranked_universe is now always TRUE in .SCHOOLS; saved searches
# carrying candidate_pool$in_ranked_universe = TRUE remain compatible
# (the filter becomes a no-op against the already-filtered pool).
.SCHOOLS <- .SCHOOLS %>%
  filter(!is.na(in_ranked_universe) & in_ranked_universe)
message(sprintf("[shiny global] filtered to ranked universe: %d schools",
                nrow(.SCHOOLS)))

# Join AJCU (Association of Jesuit Colleges and Universities) membership
# as a boolean flag. Independent of religious_tradition: a school can be
# both Catholic AND Jesuit; the sidebar exposes them as separate filters
# so users can narrow to "Catholic peers" or "Jesuit peers" or "Catholic
# AND Jesuit peers". Source list lives in data/ajcu_members.csv.
.ajcu_path <- file.path(.PROJECT_ROOT, "data", "ajcu_members.csv")
if (file.exists(.ajcu_path)) {
  .AJCU_UNITIDS <- read_csv(.ajcu_path, show_col_types = FALSE)$unitid
  .SCHOOLS$is_jesuit <- .SCHOOLS$unitid %in% .AJCU_UNITIDS
  message(sprintf("[shiny global] AJCU flag set on %d schools",
                  sum(.SCHOOLS$is_jesuit)))
} else {
  .SCHOOLS$is_jesuit <- FALSE
  message("[shiny global] data/ajcu_members.csv not found; is_jesuit = FALSE for all")
}

# Join EADA-derived categorical extras (athletics body / division /
# conference / has_football / classification) if the file is present.
# Produced by R/athletics_module_pipeline.R. Graceful fallback when the
# file is missing — the app still works without athletics, the
# athletics-* columns just don't appear in .SCHOOLS.
.schools_ath_path <- file.path(.OUTPUT_DIR, "schools_athletics.csv")
if (file.exists(.schools_ath_path)) {
  .SCHOOLS_ATH <- read_csv(.schools_ath_path, show_col_types = FALSE) %>%
    mutate(unitid = as.integer(unitid))
  .SCHOOLS <- left_join(.SCHOOLS, .SCHOOLS_ATH, by = "unitid")
  message(sprintf(
    "[shiny global] joined schools_athletics: %d schools have athletics_body, %d have conference",
    sum(!is.na(.SCHOOLS$athletics_body)),
    sum(!is.na(.SCHOOLS$athletics_conference))))
} else {
  message("[shiny global] schools_athletics.csv not found; athletics columns absent.")
}

.MODULE_KEYS <- c("aid", "adm", "enr", "out", "fin", "ath")

.load_module_pair <- function(mk) {
  facts <- read_csv(file.path(.OUTPUT_DIR, paste0(mk, "_facts.csv")),
                    show_col_types = FALSE)
  vars  <- read_csv(file.path(.OUTPUT_DIR, paste0(mk, "_variables.csv")),
                    show_col_types = FALSE) %>% mutate(module = mk)
  list(facts = facts, variables = vars)
}

.MODULES <- set_names(map(.MODULE_KEYS, .load_module_pair), .MODULE_KEYS)

.VARIABLES <- map_dfr(.MODULES, "variables")
.FACTS     <- map_dfr(.MODULES, "facts")

# Build the wide all-variables matrix (clustering + descriptive + detail race)
# used by the side-by-side comparison view. 5-year mean per (unitid, metric).
.WIDE_ALL <- .FACTS %>%
  group_by(unitid, metric) %>%
  summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(value)) %>%
  pivot_wider(names_from = metric, values_from = value)

# Join schools metadata so downstream code has a single tibble to filter
# and display from.
.SCHOOLS_WIDE <- .SCHOOLS %>%
  left_join(.WIDE_ALL, by = "unitid")

# -----------------------------------------------------------------------------
# Per-variable aggregation summary. For each metric, look at which panel
# years actually have finite data. Used to label variables in the
# side-by-side view so readers know whether a value is a 5-year average,
# a single-year snapshot, or something in between.
# -----------------------------------------------------------------------------
.VAR_YEARS_DF <- .FACTS %>%
  filter(is.finite(value)) %>%
  group_by(metric) %>%
  summarise(
    n_years  = n_distinct(year),
    min_year = min(year),
    max_year = max(year),
    .groups  = "drop"
  )

.VAR_YEARS_LABEL <- setNames(
  vapply(seq_len(nrow(.VAR_YEARS_DF)), function(i) {
    n    <- .VAR_YEARS_DF$n_years[i]
    ymin <- .VAR_YEARS_DF$min_year[i]
    ymax <- .VAR_YEARS_DF$max_year[i]
    if (n == 1) {
      sprintf("snapshot (%d)", ymin)
    } else if (n == 5 && ymin == 2020 && ymax == 2024) {
      "5-yr avg"
    } else {
      sprintf("%d-yr avg (%d-%d)", n, ymin, ymax)
    }
  }, character(1)),
  .VAR_YEARS_DF$metric
)

# -----------------------------------------------------------------------------
# Stratum group descriptions (used by the Stratified Peers tab to show
# definitions for each Carnegie / classification value via an info icon).
# The lookup file is editable: add rows for any (dimension, value) pair to
# extend coverage. Missing entries just render no info icon.
# -----------------------------------------------------------------------------
.STRATUM_DESCRIPTIONS <- {
  desc_path <- "data/stratum_descriptions.csv"
  if (file.exists(desc_path)) {
    read_csv(desc_path, show_col_types = FALSE)
  } else {
    tibble::tibble(dimension = character(),
                   value     = character(),
                   description = character())
  }
}

.lookup_stratum_description <- function(dim_key, value) {
  if (is.null(.STRATUM_DESCRIPTIONS) || !nrow(.STRATUM_DESCRIPTIONS))
    return(NA_character_)
  m <- which(.STRATUM_DESCRIPTIONS$dimension == dim_key &
             .STRATUM_DESCRIPTIONS$value     == value)
  if (length(m) == 0) return(NA_character_)
  .STRATUM_DESCRIPTIONS$description[m[1]]
}

# -----------------------------------------------------------------------------
# Small constants the UI will need
# -----------------------------------------------------------------------------
.THEMES <- c("size", "selectivity", "resources", "finance",
             "outcomes", "aid", "student_body", "athletics")

# Display labels for the theme keys above. Used by slider/header
# renderers in place of stringr::str_to_title() so multi-word themes
# (e.g. student_body → "Student body") render cleanly instead of
# "Student_body". Add new theme keys here when extending .THEMES.
.THEME_LABELS <- c(
  size         = "Size",
  selectivity  = "Selectivity",
  resources    = "Resources",
  finance      = "Finance",
  outcomes     = "Outcomes",
  aid          = "Aid",
  student_body = "Student body",
  athletics    = "Athletics"
)

# Map an internal theme key (or a vector of keys) to its display label.
# Falls back to stringr::str_to_title() for anything not in the lookup
# (e.g. ad-hoc keys, "descriptive", etc.) so the renderer never breaks.
.theme_label <- function(th) {
  out <- unname(.THEME_LABELS[th])
  miss <- is.na(out)
  if (any(miss)) out[miss] <- stringr::str_to_title(th[miss])
  out
}

.DEFAULT_ANCHOR_UNITID <- 166124L  # Holy Cross

# Pre-build the anchor-picker choices vector once at app startup. Used
# by every selectizeInput across the app (Peer Search sidebar, Side-by-
# Side, Aspirant, Stratified). Building this at module level instead of
# per-session shaves ~10ms off every session start and keeps the
# memory footprint small since the vector is shared.
.ANCHOR_CHOICES <- {
  vals <- .SCHOOLS$unitid
  names(vals) <- sprintf("%s (%s)", .SCHOOLS$instnm, .SCHOOLS$stabbr)
  vals[order(names(vals))]
}

# -----------------------------------------------------------------------------
# Source the app's R/ helpers and module stubs
# -----------------------------------------------------------------------------
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = FALSE)
}

message(sprintf(
  "[shiny global] loaded: %d schools, %d variables, %d facts rows, %d wide cols.",
  nrow(.SCHOOLS), nrow(.VARIABLES), nrow(.FACTS), ncol(.WIDE_ALL) - 1
))

# -----------------------------------------------------------------------------
# Suppress a specific noisy Shiny warning:
#   "The select input \"<id>\" contains a large number of options;
#    consider using server-side selectize for massively improved
#    performance. See the Details section of the ?selectizeInput help topic."
#
# We use client-side selectize for the school pickers deliberately. Server-side
# mode buries obvious matches past `maxOptions: 50` whenever the user types a
# common prefix (typing "Holy" returned matches in unitid order, with the
# College of the Holy Cross sitting at position 284 — past the cap, invisible).
# Client-side selectize uses Sifter's word-start ranking and surfaces the
# right school immediately. The warning is Shiny telling us to revert to the
# behavior we explicitly moved away from; muffle it so the console stays
# readable.
#
# This is the narrowest possible silencer — only the exact selectize warning
# is muffled; every other R warning still propagates normally.
local({
  selectize_warning_pat <-
    "consider using server-side selectize for massively improved performance"
  globalCallingHandlers(
    warning = function(w) {
      if (grepl(selectize_warning_pat, conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    })
})
