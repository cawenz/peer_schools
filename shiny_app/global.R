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
.THEMES <- c("scale", "selectivity", "resources", "finance",
             "outcomes", "aid", "composition", "athletics")

.DEFAULT_ANCHOR_UNITID <- 166124L  # Holy Cross

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
