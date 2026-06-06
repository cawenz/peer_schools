# =============================================================================
# global.R — Cohort Builder app startup
#
# Standalone Shiny app sibling to shiny_app/, sharing the same project's
# output/ and data/ directories so that re-running R/schools_pipeline.R
# refreshes both apps automatically.
#
# Working directory at startup is cohort_app/, so paths are relative to
# the parent project root.
# =============================================================================

suppressMessages({
  library(dplyr); library(tidyr); library(stringr)
  library(readr); library(tibble); library(purrr)
  library(ggplot2)
  library(plotly)
  library(leaflet)
  library(leaflet.extras)   # for addHeatmap in the cohort map view
})

# -----------------------------------------------------------------------------
# Defensive: mclust and clustvarsel may be loaded from prior session work;
# they export `em()` / `map()` that collide with shiny/bslib internals.
# -----------------------------------------------------------------------------
for (pkg in c("clustvarsel", "mclust")) {
  if (paste0("package:", pkg) %in% search())
    try(detach(paste0("package:", pkg), character.only = TRUE, unload = TRUE),
        silent = TRUE)
  if (pkg %in% loadedNamespaces())
    try(unloadNamespace(pkg), silent = TRUE)
}

# -----------------------------------------------------------------------------
# Project paths — share the parent project's output/ and data/ directories
# so both apps pick up the same pipeline-built CSVs.
# -----------------------------------------------------------------------------
.PROJECT_ROOT <- normalizePath("..", mustWork = TRUE)
.OUTPUT_DIR   <- file.path(.PROJECT_ROOT, "output")
.DATA_DIR     <- file.path(.PROJECT_ROOT, "data")

# Default anchor used by the cohort builder. HC = 166124.
.DEFAULT_ANCHOR_UNITID <- 166124L

# Region constants — Side-by-Side's classifications block computes a
# region label for each institution from these state mappings.
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

# -----------------------------------------------------------------------------
# Load data once at startup
# -----------------------------------------------------------------------------
.SCHOOLS <- read_csv(file.path(.OUTPUT_DIR, "schools.csv"),
                     show_col_types = FALSE) %>%
  mutate(unitid = as.integer(unitid),
         in_ranked_universe = as.logical(in_ranked_universe))

# Join EADA-derived athletics columns if present.
.schools_ath_path <- file.path(.OUTPUT_DIR, "schools_athletics.csv")
if (file.exists(.schools_ath_path)) {
  .SCHOOLS_ATH <- read_csv(.schools_ath_path, show_col_types = FALSE) %>%
    mutate(unitid = as.integer(unitid))
  .SCHOOLS <- left_join(.SCHOOLS, .SCHOOLS_ATH, by = "unitid")
}

# Per-module facts + variables tables, then the wide all-variables matrix
# used by the dashboard cards and inspector.
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

# 5-year mean per (unitid, metric) pivoted wide.
.WIDE_ALL <- .FACTS %>%
  group_by(unitid, metric) %>%
  summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(value)) %>%
  pivot_wider(names_from = metric, values_from = value)
.SCHOOLS_WIDE <- .SCHOOLS %>% left_join(.WIDE_ALL, by = "unitid")

# Per-variable year-window labels ("snapshot (2024)" / "5-yr avg" / ...).
.VAR_YEARS_DF <- .FACTS %>%
  filter(is.finite(value)) %>%
  group_by(metric) %>%
  summarise(n_years  = n_distinct(year),
            min_year = min(year),
            max_year = max(year),
            .groups  = "drop")

.VAR_YEARS_LABEL <- setNames(
  vapply(seq_len(nrow(.VAR_YEARS_DF)), function(i) {
    n    <- .VAR_YEARS_DF$n_years[i]
    ymin <- .VAR_YEARS_DF$min_year[i]
    ymax <- .VAR_YEARS_DF$max_year[i]
    if (n == 1) sprintf("snapshot (%d)", ymin)
    else if (n == 5 && ymin == 2020 && ymax == 2024) "5-yr avg"
    else sprintf("%d-yr avg (%d-%d)", n, ymin, ymax)
  }, character(1)),
  .VAR_YEARS_DF$metric
)

# -----------------------------------------------------------------------------
# Source the app's R/ helpers and module stubs.
# -----------------------------------------------------------------------------
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = FALSE)
}

message(sprintf(
  "[cohort global] loaded: %d schools, %d variables, %d facts rows, %d wide cols.",
  nrow(.SCHOOLS), nrow(.VARIABLES), nrow(.FACTS), ncol(.WIDE_ALL) - 1
))

# Suppress the noisy Shiny client-side-selectize warning (same reason as
# in shiny_app/global.R: we use client-side mode deliberately).
local({
  selectize_warning_pat <-
    "consider using server-side selectize for massively improved performance"
  globalCallingHandlers(
    warning = function(w) {
      if (grepl(selectize_warning_pat, conditionMessage(w), fixed = TRUE))
        invokeRestart("muffleWarning")
    })
})
