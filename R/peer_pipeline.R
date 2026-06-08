# =============================================================================
# Peer Selection Pipeline
# Holy Cross peer-comparison project
#
# Reads:  output/schools.csv
#         output/aid_facts.csv, aid_variables.csv
#         output/adm_facts.csv, adm_variables.csv
#         output/enr_facts.csv, enr_variables.csv
#         output/out_facts.csv, out_variables.csv
#         output/fin_facts.csv, fin_variables.csv
#         output/ath_facts.csv, ath_variables.csv  (EADA athletics)
#
# Provides:
#   compute_peers()  - core function for computing peer similarity
#   print_peers()    - pretty-printer for results
#
# Algorithm:
#   1. Load schools.csv and all 5 module facts/variables
#   2. Filter to clustering variables (and the 6 detail race vars at half weight)
#   3. Compute 5-year average for multi-year vars, single value for snapshots
#   4. Pivot wide: one row per institution
#   5. Apply candidate_pool filter
#   6. Compute per-variable coverage within candidate pool
#   7. Drop variables below coverage_threshold (default 0.70)
#   8. Apply log transforms to heavily right-skewed variables (default on)
#   9. Auto-normalize weights by theme (so theme weight is independent of
#      how many variables the theme contains)
#   10. Standardize each variable to z-scores using candidate-pool stats
#   11. Compute weighted distance from anchor (Euclidean or Mahalanobis)
#   12. Return top-k with diagnostics
#
# Methodology decisions encoded:
#   - Candidate pool defaults to US News ranked universe (~1,235 schools)
#   - 5-year average for multi-year variables
#   - 70% coverage threshold within the candidate pool
#   - Auto-normalize by theme (equal-by-default theme weighting)
#   - Detail race variables (pct_black, hispanic, asian, nhpi, aian,
#     two_or_more) get half weight in Composition theme
#   - Religious affiliation is in schools.csv (religious_affiliation_code,
#     religious_affiliation, religious_tradition). A synthetic binary
#     same_religious_tradition variable is computed per call from the
#     anchor's affiliation and contributes to the Composition theme. The
#     binary is 1 if a candidate shares the anchor's tradition (e.g.,
#     both Catholic), 0 otherwise.
#   - Log transforms applied to right-skewed variables before z-scoring
#     (currency / counts / endowment); disabled for rates, percentages,
#     signed gaps, and already-normalized ratios
#   - Distance metric defaults to Euclidean; Mahalanobis available via
#     distance_metric = "mahalanobis"
# =============================================================================

suppressMessages({
  library(dplyr); library(tidyr); library(stringr); library(readr); library(tibble)
})

# -----------------------------------------------------------------------------
# THEME ASSIGNMENTS
# -----------------------------------------------------------------------------
# These determine which variables contribute to each theme. Mission attributes
# (usnews_classification, control_grp, region, accreditor) are NOT in any
# theme - they are used as filters via candidate_pool, not as similarity
# dimensions.
THEME_VARS <- list(
  size = c(
    "total_enrollment", "undergraduate_enrollment",
    "first_time_enrollment", "full_time_enrollment"
  ),
  selectivity = c(
    "acceptance_rate", "yield_rate", "application_volume",
    "pct_submitting_sat", "pct_submitting_act", "pct_top10_hs",
    "ed_acceptance_rate", "ed_share_of_applications", "yield_men_vs_women"
  ),
  resources = c(
    "student_faculty_ratio", "tenure_track_share", "avg_ft_faculty_salary",
    "instruction_per_fte", "academic_support_per_fte", "student_services_per_fte",
    "instructional_share", "pct_classes_under_20", "pct_classes_50plus"
  ),
  finance = c(
    "endowment_per_fte", "endowment_coverage_years", "tuition_share_of_expenses",
    "core_expenses_per_fte", "operating_margin_ex_inv_return_per_fte",
    "net_assets_per_fte", "published_tuition_fees", "herd_avg"
  ),
  outcomes = c(
    "grad_rate_6yr", "grad_rate_4yr", "retention_rate", "transfer_out_rate",
    "pell_grad_gap", "first_gen_grad_rate_6yr",
    "median_earnings_10yr", "median_earnings_6yr", "loan_repayment_rate",
    "earnings_ratio", "doctoral_degrees_awarded", "grad_rate_men_vs_women"
  ),
  aid = c(
    "avg_net_price_aided", "avg_net_price_income_0_30k", "pct_pell", "pell_count",
    "pct_any_grant", "avg_inst_grant", "inst_discount_rate",
    "pct_federal_loan", "avg_federal_loan", "pct_need_met", "pct_need_fully_met"
  ),
  student_body = c(
    "pct_undergrad", "pct_part_time", "pct_age_25plus",
    "pct_first_generation", "median_family_income",
    "pct_white", "pct_international", "pct_bipoc", "pct_race_unknown",
    "transfer_in_enrollment", "residential_share",
    # Religious affiliation match with anchor (binary 0/1). Added via
    # the candidates-side join in compute_peers; not in any facts CSV.
    "same_religious_tradition"
  ),
  # Athletics theme (EADA-derived). Default weight is 0 in compute_peers —
  # existing peer searches behave identically until a user dials it up.
  # The three CLUSTERING signals (orthogonal: intensity, breadth, culture)
  # drive peer distance; the rest are descriptive only and never reach
  # the weight calc (compute_peers filters to use_type == "clustering"
  # in .load_wide_facts before THEME_VARS is consulted). Listing them
  # all here so .var_theme() groups them together in the Side-by-Side
  # view rather than dumping the descriptive ones into "Descriptive".
  athletics = c(
    # Clustering (in peer distance):
    "pct_athletes_overall", "total_varsity_sports", "multi_sport_ratio",
    # Descriptive (visible in Side-by-Side and the inspector, no weight):
    "mens_varsity_sports", "womens_varsity_sports",
    "male_athletes_undup", "female_athletes_undup", "total_athletes_undup",
    "pct_male_athletes",   "pct_female_athletes"
  )
)

# 6 detail race variables get half weight in the Student body theme
# (kept legacy constant name `COMPOSITION_HALF_WEIGHT` available below
# as an alias so any external scripts that referenced it keep working.)
STUDENT_BODY_HALF_WEIGHT <- c(
  "pct_black", "pct_hispanic", "pct_asian",
  "pct_nhpi", "pct_aian", "pct_two_or_more"
)
# Alias kept so any older code/scripts that referenced the prior name
# continue to work. Safe to remove once we're sure nothing reads it.
COMPOSITION_HALF_WEIGHT <- STUDENT_BODY_HALF_WEIGHT

# -----------------------------------------------------------------------------
# LOG TRANSFORM ASSIGNMENTS
# -----------------------------------------------------------------------------
# Variables that span multiple orders of magnitude or are heavily right-skewed.
# Applied as log10(value + 1) before z-scoring so 0 values pass through and
# the transform handles non-positive edge cases gracefully.
#
# NOT in this list (by design):
#   - Percentages and rates (pct_*, *_rate, *_share) - already 0-100 bounded
#   - Signed gaps (pell_grad_gap, yield_gap_men_women) - sign would break
#   - Already-normalized ratios (earnings_ratio, student_faculty_ratio,
#     endowment_coverage_years, inst_discount_rate)
LOG_TRANSFORM_VARS <- c(
  # Enrollment scale
  "total_enrollment", "undergraduate_enrollment",
  "first_time_enrollment", "full_time_enrollment",
  "transfer_in_enrollment",
  # Applications (heavy right tail)
  "application_volume",
  # Financial scale (currency, large dynamic range)
  "endowment_per_fte", "net_assets_per_fte", "core_expenses_per_fte",
  "instruction_per_fte", "academic_support_per_fte",
  "student_services_per_fte", "herd_avg",
  # Tuition and aid currency
  "published_tuition_fees", "avg_net_price", "avg_net_price_income_0_30k",
  "avg_inst_grant", "avg_fed_loan",
  # Counts
  "pell_count", "doctoral_degrees_awarded",
  # Salary and earnings (currency)
  "avg_ft_faculty_salary", "median_earnings_10yr", "median_earnings_6yr",
  "median_family_income"
)

# =============================================================================
# Aspirant peer search — preferred-direction lookup
# =============================================================================
# Metrics that compute_aspirant_peers() understands as aspirational, plus
# the direction the user wants to move on each. "higher" = candidate must
# be ABOVE the anchor to count as aspirational; "lower" = candidate must
# be BELOW the anchor (e.g., more selective acceptance rate).
#
# Edit this list to add, remove, or re-direction metrics. Anything not in
# this dict cannot be selected as an aspirational metric in the app's UI.
ASPIRANT_DIRECTIONS <- list(
  # Selectivity
  acceptance_rate     = "lower",     # more selective
  yield_rate          = "higher",    # more sought-after
  sat_mid50           = "higher",    # stronger entering class
  # Outcomes
  grad_rate_6yr        = "higher",
  grad_rate_4yr        = "higher",
  retention_rate       = "higher",
  median_earnings_10yr = "higher",
  loan_repayment_rate  = "higher",
  # Resources
  student_faculty_ratio = "lower",   # more intensive
  avg_ft_faculty_salary = "higher",
  instruction_per_fte   = "higher",
  # Finance
  endowment_per_fte     = "higher",
  herd_avg              = "higher",
  # Aid
  pct_pell             = "higher",   # access (some IR shops aspire higher,
                                     # some don't; toggle by removing
                                     # this entry if it doesn't apply)
  pct_need_met         = "higher"
)

# Display labels paired with the preferred-direction phrasing used by the
# UI's "Aspire higher on" multi-select. Keys must match ASPIRANT_DIRECTIONS.
ASPIRANT_LABELS <- list(
  acceptance_rate       = "Acceptance rate (more selective)",
  yield_rate            = "Yield rate (higher)",
  sat_mid50             = "SAT mid-50% composite (higher)",
  grad_rate_6yr         = "6-year graduation rate (higher)",
  grad_rate_4yr         = "4-year graduation rate (higher)",
  retention_rate        = "Retention rate (higher)",
  median_earnings_10yr  = "Median earnings, 10-year (higher)",
  loan_repayment_rate   = "Loan repayment rate (higher)",
  student_faculty_ratio = "Student-faculty ratio (lower)",
  avg_ft_faculty_salary = "Average FT faculty salary (higher)",
  instruction_per_fte   = "Instruction $ per FTE (higher)",
  endowment_per_fte     = "Endowment per FTE (higher)",
  herd_avg              = "HERD R&D expenditures (higher)",
  pct_pell              = "% Pell (higher)",
  pct_need_met          = "% need met (higher)"
)

# Look up the theme for a variable name (NA if not assigned to any)
.var_theme <- function(var_name) {
  for (theme in names(THEME_VARS)) {
    if (var_name %in% THEME_VARS[[theme]]) return(theme)
  }
  if (var_name %in% STUDENT_BODY_HALF_WEIGHT) return("student_body")
  NA_character_
}

# -----------------------------------------------------------------------------
# DATA LOADING
# -----------------------------------------------------------------------------

.load_schools <- function(schools_path = "output/schools.csv") {
  s <- read_csv(schools_path, show_col_types = FALSE) %>%
    mutate(
      unitid = as.integer(unitid),
      in_ranked_universe = as.logical(in_ranked_universe)
    )
  # Religious affiliation columns are added by a later version of
  # schools_pipeline.R. If the user is running peers_pipeline on an older
  # schools.csv, fill the missing columns with NA so downstream code works
  # uniformly. A reminder is logged so the user can rerun build_schools().
  if (!"religious_tradition" %in% names(s)) {
    message("Note: schools.csv predates religious-affiliation support; ",
            "the same_religious_tradition clustering variable will be NA. ",
            "Rerun build_schools() to refresh.")
    s$religious_affiliation_code <- NA_integer_
    s$religious_affiliation      <- NA_character_
    s$religious_tradition        <- NA_character_
  }
  s
}

# Multi-year vars: mean across all available years (5-year average)
# Single-snapshot vars: single value (mean of one year is just that value)
.aggregate_facts <- function(facts) {
  facts %>%
    group_by(unitid, metric) %>%
    summarise(
      value = mean(value, na.rm = TRUE),
      n_years = n_distinct(year),
      .groups = "drop"
    ) %>%
    filter(is.finite(value))
}

# Load all 5 modules, filter to clustering vars + detail race, aggregate, pivot
.load_wide_facts <- function(output_dir = "output") {
  module_keys <- c("aid", "adm", "enr", "out", "fin", "ath")
  all_facts <- list(); all_vars <- list()
  
  for (mk in module_keys) {
    f_path <- file.path(output_dir, paste0(mk, "_facts.csv"))
    v_path <- file.path(output_dir, paste0(mk, "_variables.csv"))
    if (!file.exists(f_path) || !file.exists(v_path)) {
      warning(sprintf("Skipping module %s - missing files at %s", mk, output_dir))
      next
    }
    all_facts[[mk]] <- read_csv(f_path, show_col_types = FALSE)
    all_vars[[mk]]  <- read_csv(v_path, show_col_types = FALSE) %>%
      mutate(module = mk)
  }
  
  vars_combined  <- bind_rows(all_vars)
  facts_combined <- bind_rows(all_facts)
  
  # Clustering variables + 6 detail race vars (descriptive in variables.csv
  # but used at half weight in clustering math).
  clustering_vars <- vars_combined %>%
    filter(use_type == "clustering") %>% pull(metric)
  clustering_vars <- union(clustering_vars, COMPOSITION_HALF_WEIGHT)
  
  facts_clust <- facts_combined %>%
    filter(metric %in% clustering_vars)
  
  aggregated <- .aggregate_facts(facts_clust)
  
  wide <- aggregated %>%
    select(unitid, metric, value) %>%
    pivot_wider(names_from = metric, values_from = value)
  
  list(
    wide = wide,
    variables = vars_combined,
    available_metrics = unique(aggregated$metric)
  )
}

# -----------------------------------------------------------------------------
# MAIN FUNCTION
# -----------------------------------------------------------------------------

#' Compute peer similarity for an anchor institution.
#'
#' @param anchor_unitid IPEDS unitid. Default 166124 (Holy Cross).
#' @param candidate_pool Named list of filter conditions on schools.csv.
#'                       Default in_ranked_universe = TRUE (~1,460 schools).
#'                       Pass list() for no filter (full universe).
#' @param theme_weights Named list of theme weight overrides. Default all 1.0.
#'                       Themes: size, selectivity, resources, finance,
#'                       outcomes, aid, student_body, athletics.
#' @param variable_weights Named list of per-variable weight overrides.
#'                          Multiplies the theme contribution for that variable.
#' @param exclude_variables Character vector of variables to exclude entirely.
#' @param coverage_threshold Fraction. Drop variables with coverage below this
#'                            within the candidate pool. Default 0.70.
#' @param log_transform One of "default", "all", "none", or a character vector
#'                       of variable names to log-transform. "default" applies
#'                       log10(x+1) to the variables in LOG_TRANSFORM_VARS
#'                       (counts, currency, endowment-related). "all" applies
#'                       to every numeric variable (not recommended for rates).
#'                       "none" disables. A character vector specifies an
#'                       explicit override list.
#' @param distance_metric "euclidean" (default) or "mahalanobis". Mahalanobis
#'                        adjusts for correlation between variables using the
#'                        candidate-pool covariance matrix - useful when many
#'                        variables are highly correlated, but less directly
#'                        interpretable. With Mahalanobis, theme/variable
#'                        weights are still applied via a diagonal weighting
#'                        matrix that scales each dimension before the
#'                        Mahalanobis computation.
#' @param k Number of peers to return. Default 20.
#' @param output_dir Directory containing facts and variables CSVs. Default "output".
#'
#' @return list with:
#'   - peers: data frame, top-K peers with distance, attrs, rank
#'   - meta: list of methodology details (vars used, dropped, weights, etc.)
compute_peers <- function(
    anchor_unitid     = 166124L,
    candidate_pool    = list(in_ranked_universe = TRUE),
    theme_weights     = list(),
    variable_weights  = list(),
    exclude_variables = NULL,
    coverage_threshold = 0.70,
    log_transform     = "default",
    distance_metric   = "euclidean",
    k                 = 20,
    output_dir        = "output"
) {
  # -- 0. Validate arguments --
  distance_metric <- match.arg(distance_metric, c("euclidean", "mahalanobis"))
  
  # -- 1. Load data --
  schools <- .load_schools(file.path(output_dir, "schools.csv"))
  loaded  <- .load_wide_facts(output_dir)
  wide    <- loaded$wide
  
  # -- 2. Theme weights with defaults --
  all_themes <- names(THEME_VARS)
  theme_w <- setNames(rep(1.0, length(all_themes)), all_themes)
  # Athletics is opt-in: starts at 0 weight so every existing peer search
  # (which omits theme_weights or sets only academic themes) behaves
  # identically to the pre-EADA pipeline. Users opt in by passing
  # theme_weights = list(athletics = 1.0) or via the Peer Search slider.
  if ("athletics" %in% all_themes) theme_w["athletics"] <- 0
  for (t in names(theme_weights)) {
    if (!t %in% all_themes) {
      warning(sprintf("Unknown theme '%s' ignored", t))
      next
    }
    theme_w[t] <- theme_weights[[t]]
  }
  
  # -- 3. Apply candidate-pool filter --
  candidates <- schools
  for (col in names(candidate_pool)) {
    if (!col %in% names(candidates)) {
      stop(sprintf("Filter column '%s' not in schools.csv", col))
    }
    val <- candidate_pool[[col]]
    candidates <- candidates %>% filter(.data[[col]] %in% val)
  }
  
  # Ensure anchor is in the candidate pool (needed for distance computation)
  if (!anchor_unitid %in% candidates$unitid) {
    anchor_row <- schools %>% filter(unitid == anchor_unitid)
    if (!nrow(anchor_row))
      stop(sprintf("Anchor unitid %d not found in schools.csv", anchor_unitid))
    candidates <- bind_rows(candidates, anchor_row)
    message(sprintf("Note: anchor %d not in pool's filter; added back for distance reference",
                    anchor_unitid))
  }
  
  # -- 4. Join wide facts to candidates --
  # External-ranking fields (usnews_rank, wamo_rank, wamo_category) may be
  # absent from older schools.csv files; tidyselect's any_of() drops them
  # gracefully. The display layer treats missing as NA.
  cdat <- candidates %>%
    select(unitid, instnm, sector, control_grp,
           usnews_classification, in_ranked_universe, stabbr,
           religious_affiliation, religious_tradition,
           any_of(c("usnews_rank", "wamo_rank", "wamo_category",
                    "forbes_rank"))) %>%
    left_join(wide, by = "unitid")
  
  # -- 4b. Build the same_religious_tradition clustering variable from the
  # anchor's religious tradition. This is a 0/1 binary value: 1 if the
  # candidate shares the anchor's tradition (e.g., both Catholic), 0
  # otherwise. NA tradition (public schools, no affiliation) maps to 0 -
  # i.e., the variable is "shared religious-Christian-or-similar identity
  # with the anchor," which is a real similarity dimension that simply
  # doesn't apply for institutions without affiliation. The candidate
  # contributes 0 z-score impact in those cases, which is what we want.
  anchor_tradition <- candidates %>%
    filter(unitid == anchor_unitid) %>% pull(religious_tradition)
  if (length(anchor_tradition) == 1 && !is.na(anchor_tradition)) {
    cdat$same_religious_tradition <- as.integer(
      !is.na(cdat$religious_tradition) &
        cdat$religious_tradition == anchor_tradition
    )
  } else {
    # Anchor has no affiliation; the variable is undefined / not meaningful.
    cdat$same_religious_tradition <- NA_integer_
  }
  
  # -- 5. Available variables in the data --
  candidate_metrics <- intersect(loaded$available_metrics, names(cdat))
  # The synthetic same_religious_tradition variable lives in cdat (not in
  # any facts CSV) but is a clustering variable - include it explicitly
  # when the anchor has a defined affiliation (it's all NA otherwise and
  # will fall out via the coverage threshold).
  if ("same_religious_tradition" %in% names(cdat) &&
      any(!is.na(cdat$same_religious_tradition)))
    candidate_metrics <- union(candidate_metrics, "same_religious_tradition")
  if (!is.null(exclude_variables))
    candidate_metrics <- setdiff(candidate_metrics, exclude_variables)
  
  # -- 6. Coverage within candidate pool --
  coverage_df <- tibble(
    metric = candidate_metrics,
    coverage = sapply(candidate_metrics, function(m) {
      mean(!is.na(cdat[[m]]))
    })
  ) %>% arrange(coverage)
  
  vars_passing <- coverage_df %>%
    filter(coverage >= coverage_threshold) %>% pull(metric)
  vars_dropped_cov <- coverage_df %>%
    filter(coverage < coverage_threshold)
  
  if (!length(vars_passing))
    stop("No variables pass the coverage threshold")
  
  # -- 7. Anchor must have a value for each variable used --
  anchor_row <- cdat %>% filter(unitid == anchor_unitid)
  anchor_has_value <- sapply(vars_passing, function(m) !is.na(anchor_row[[m]]))
  vars_anchor_na <- vars_passing[!anchor_has_value]
  vars_final     <- vars_passing[anchor_has_value]
  
  if (!length(vars_final))
    stop("Anchor has no values for variables passing the coverage threshold")
  
  # -- 8. Per-variable weights: theme_w * var_w * half_weight_factor / theme_n --
  weights <- numeric(length(vars_final))
  names(weights) <- vars_final
  
  for (v in vars_final) {
    theme <- .var_theme(v)
    if (is.na(theme)) { weights[v] <- 0; next }
    
    # Variables in this theme that survived (full-weight and half-weight)
    theme_full <- intersect(THEME_VARS[[theme]], vars_final)
    theme_half <- intersect(
      if (theme == "student_body") STUDENT_BODY_HALF_WEIGHT else character(0),
      vars_final
    )
    theme_n <- length(theme_full) + 0.5 * length(theme_half)
    
    var_w_override <- if (v %in% names(variable_weights))
      variable_weights[[v]] else 1.0
    half_factor <- if (v %in% COMPOSITION_HALF_WEIGHT) 0.5 else 1.0
    
    weights[v] <- (theme_w[theme] * var_w_override * half_factor) / theme_n
  }
  
  # -- 9. Resolve log_transform argument to an actual variable list --
  vars_to_log <- if (identical(log_transform, "default")) {
    intersect(LOG_TRANSFORM_VARS, vars_final)
  } else if (identical(log_transform, "all")) {
    vars_final
  } else if (identical(log_transform, "none")) {
    character(0)
  } else if (is.character(log_transform)) {
    intersect(log_transform, vars_final)
  } else {
    stop("log_transform must be 'default', 'all', 'none', or a character vector")
  }
  
  # -- 10. Build data matrix; log-transform selected vars; z-score everything --
  # We use log10(x + 1) so zero values pass through and non-positive edge cases
  # are handled gracefully. The +1 offset matters mostly for count variables
  # (some institutions have 0 transfer-in students or 0 doctoral degrees);
  # for currency variables the offset is negligible against the typical scale.
  data_mat <- cdat %>%
    select(unitid, all_of(vars_final)) %>%
    column_to_rownames("unitid")
  
  for (v in vars_final) {
    vals <- data_mat[[v]]
    if (v %in% vars_to_log) {
      # Floor at zero so negative values (e.g., operating margins) wouldn't
      # break log; but operating_margin_ex_inv_return_per_fte is NOT in
      # LOG_TRANSFORM_VARS, so this guard is belt-and-suspenders.
      vals <- ifelse(is.na(vals), NA_real_, log10(pmax(vals, 0) + 1))
    }
    mu <- mean(vals, na.rm = TRUE)
    sigma <- sd(vals, na.rm = TRUE)
    if (is.na(sigma) || sigma == 0) {
      data_mat[[v]] <- 0  # constant or all-NA variable contributes nothing
    } else {
      data_mat[[v]] <- (vals - mu) / sigma
    }
  }
  
  # -- 11. Weighted distance from anchor (Euclidean or Mahalanobis) --
  anchor_z <- as.numeric(data_mat[as.character(anchor_unitid), ])
  
  # Active dimensions: variables with strictly-positive weight. Zero-weighted
  # dimensions must NOT contribute to the distance — including them folds in
  # 0 (positive*0=0) contributions that collapse a candidate's distance to 0
  # whenever they have NA on the active dimensions, producing the
  # "alphabetical with distance=0" bug when only one theme is weighted.
  active_idx <- which(weights > 0)
  if (!length(active_idx))
    stop("All theme weights are 0 - no dimensions to compute distance on.")

  if (distance_metric == "euclidean") {
    # Weighted Euclidean: dim-wise weighting, then sqrt of sum of squares.
    # Candidates with NA on ALL active dimensions get distance = NA and sort
    # to the bottom of the ranking, rather than ranking first with 0.
    #
    # Vectorized: one matrix subtraction + one element-wise weight + one
    # rowSums. ~10-30x faster than the per-row sapply loop for typical
    # candidate-pool sizes (1,500 schools, ~50 active vars). Behavior is
    # bit-for-bit identical to the loop — same NA semantics (drop NA
    # contributions per row; all-NA rows -> NA distance).
    anchor_active <- anchor_z[active_idx]
    w_active      <- weights[active_idx]
    data_active   <- as.matrix(data_mat)[, active_idx, drop = FALSE]
    diffs_sq      <- sweep(data_active, 2, anchor_active, "-")^2
    weighted_sq   <- sweep(diffs_sq, 2, w_active, "*")
    n_valid       <- rowSums(!is.na(weighted_sq))
    distances     <- sqrt(rowSums(weighted_sq, na.rm = TRUE))
    distances[n_valid == 0] <- NA_real_
    
  } else {
    # Mahalanobis: adjusts for correlation between variables using the
    # candidate-pool covariance matrix. We pre-multiply each column by
    # sqrt(weight) so the dimension weights still apply within the
    # Mahalanobis metric.
    sqrt_weights <- sqrt(weights[vars_final])
    Xw <- as.matrix(data_mat) %*% diag(sqrt_weights, nrow = length(sqrt_weights))
    colnames(Xw) <- vars_final
    
    # Compute covariance on complete pairs; if singular, fall back to
    # diagonal (which reduces to weighted Euclidean) with a warning.
    Sigma <- tryCatch(cov(Xw, use = "pairwise.complete.obs"),
                      error = function(e) NULL)
    Sigma_inv <- tryCatch(solve(Sigma),
                          error = function(e) NULL)
    
    if (is.null(Sigma_inv)) {
      warning("Mahalanobis covariance is singular; falling back to weighted Euclidean.")
      distance_metric <- "euclidean (Mahalanobis fallback)"
      anchor_active <- anchor_z[active_idx]
      w_active      <- weights[active_idx]
      distances <- sapply(seq_len(nrow(data_mat)), function(i) {
        cand_z <- as.numeric(data_mat[i, ])
        diffs  <- (cand_z[active_idx] - anchor_active)^2 * w_active
        diffs  <- diffs[!is.na(diffs)]
        if (!length(diffs)) return(NA_real_)
        sqrt(sum(diffs))
      })
    } else {
      anchor_w <- Xw[as.character(anchor_unitid), ]
      distances <- sapply(seq_len(nrow(Xw)), function(i) {
        cand_w <- Xw[i, ]
        diff <- cand_w - anchor_w
        # Pairwise NA handling: drop NA dims from both vectors and Sigma_inv
        keep <- !is.na(diff)
        if (sum(keep) < 2) return(NA_real_)
        d <- diff[keep]
        S <- Sigma_inv[keep, keep, drop = FALSE]
        # Mahalanobis distance: sqrt(d^T S^-1 d)
        val <- as.numeric(t(d) %*% S %*% d)
        if (is.na(val) || val < 0) return(NA_real_)
        sqrt(val)
      })
    }
  }
  
  # -- 12. Build result --
  # First, capture the full pool-distance distribution before truncating
  # to top-K. The Shiny app uses this for cross-search comparable metrics
  # (relative_distance = d / median, percentile_rank = where d sits in the
  # distribution). Excludes the anchor itself and any NA distances.
  pool_distances <- distances
  names(pool_distances) <- rownames(data_mat)
  pool_distances <- pool_distances[
    names(pool_distances) != as.character(anchor_unitid) &
      is.finite(pool_distances)
  ]
  pool_median_distance <- if (length(pool_distances)) median(pool_distances)
                           else NA_real_

  result <- tibble(
    unitid = as.integer(rownames(data_mat)),
    distance = distances
  ) %>%
    filter(unitid != anchor_unitid, !is.na(distance)) %>%
    arrange(distance) %>%
    mutate(rank = row_number()) %>%
    head(k) %>%
    left_join(
      candidates %>% select(unitid, instnm, sector, control_grp,
                            usnews_classification, stabbr,
                            religious_affiliation,
                            any_of(c("usnews_rank", "wamo_rank",
                                      "wamo_category", "forbes_rank"))),
      by = "unitid"
    ) %>%
    select(rank, unitid, instnm, sector, usnews_classification,
           any_of(c("usnews_rank", "wamo_rank", "wamo_category",
                    "forbes_rank")),
           stabbr, control_grp, religious_affiliation, distance)

  meta <- list(
    anchor_unitid    = anchor_unitid,
    anchor_name      = anchor_row$instnm,
    candidate_pool_size = nrow(cdat),
    coverage_threshold  = coverage_threshold,
    distance_metric  = distance_metric,
    log_transformed  = vars_to_log,
    theme_weights    = theme_w,
    variables_used   = vars_final,
    variables_dropped_coverage = vars_dropped_cov,
    variables_dropped_anchor_na = vars_anchor_na,
    weights = weights,
    # Comparable-distance support (see Shiny app's stratified peers tab):
    pool_distances        = pool_distances,
    pool_median_distance  = pool_median_distance
  )
  
  list(peers = result, meta = meta)
}

# -----------------------------------------------------------------------------
# PRETTY-PRINTER
# -----------------------------------------------------------------------------
print_peers <- function(res) {
  cat(sprintf("== Peer Similarity for %s (unitid %d) ==\n",
              res$meta$anchor_name, res$meta$anchor_unitid))
  cat(sprintf("Candidate pool size: %d\n", res$meta$candidate_pool_size))
  cat(sprintf("Distance metric: %s\n", res$meta$distance_metric))
  cat(sprintf("Variables used: %d (of which %d log-transformed)\n",
              length(res$meta$variables_used),
              length(res$meta$log_transformed)))
  cat(sprintf("Variables dropped (coverage < %.0f%%): %d\n",
              100 * res$meta$coverage_threshold,
              nrow(res$meta$variables_dropped_coverage)))
  if (length(res$meta$variables_dropped_anchor_na))
    cat(sprintf("Variables dropped (anchor has NA): %d\n",
                length(res$meta$variables_dropped_anchor_na)))
  cat("\nTheme weights:\n")
  print(res$meta$theme_weights)
  cat("\nTop peers:\n")
  print(res$peers, n = nrow(res$peers))
  invisible(res)
}

# =============================================================================
# Aspirant peer search — strict + near-miss
# =============================================================================
#
# Wrap compute_peers() and apply a directional filter on user-chosen
# aspirational metrics. "Strict" aspirants are candidates that beat the
# anchor on every chosen metric (in the preferred direction). "Near-miss"
# aspirants beat the anchor on all but one chosen metric.
#
# @param anchor_unitid Same as compute_peers().
# @param candidate_pool Same.
# @param theme_weights Same — typically the user has zeroed out the themes
#   their aspirational metrics live in so that distance is computed over
#   the CONTEXT themes only (size, sector, region etc.).
# @param k Final number of strict aspirants to return.
# @param aspirant_metrics Character vector of metric names. Each must be a
#   key in ASPIRANT_DIRECTIONS or the function errors.
# @param near_miss_k Number of near-miss candidates to keep (default 10).
# @param ... Forwarded to compute_peers (distance_metric, coverage_threshold,
#   etc.).
#
# @return A list with:
#   strict_peers     tibble of K aspirant rows (compute_peers' peer schema
#                    plus per-aspirational-metric anchor / candidate / gap)
#   near_miss_peers  tibble (up to near_miss_k rows) of candidates that
#                    failed on exactly one aspirational metric, plus a
#                    `missed_metric` column naming which one
#   aspirant_metrics Named list metric -> "higher" | "lower"
#   anchor_values    Named numeric, the anchor's value on each metric
#   meta             Pass-through from compute_peers()
compute_aspirant_peers <- function(
    anchor_unitid    = .DEFAULT_ANCHOR_UNITID %||% 166124L,
    candidate_pool   = list(in_ranked_universe = TRUE),
    theme_weights    = list(),
    k                = 20L,
    aspirant_metrics = character(0),
    near_miss_k      = 10L,
    output_dir       = "output",
    ...
) {
  if (!length(aspirant_metrics))
    stop("aspirant_metrics is empty. Pick at least one metric to aspire on.")

  bad <- setdiff(aspirant_metrics, names(ASPIRANT_DIRECTIONS))
  if (length(bad))
    stop("Unknown aspirant metric(s): ", paste(bad, collapse = ", "),
         ". Add to ASPIRANT_DIRECTIONS in R/peer_pipeline.R first.")

  # We need enough room for the directional filter to leave a useful
  # ranking. Pull 4x the requested K (capped at 200) from compute_peers,
  # then filter, then truncate. If the user wants K=20 strict aspirants
  # the underlying compute_peers will return 80 raw candidates.
  raw_k <- min(200L, max(k * 4L, 50L))

  res <- compute_peers(
    anchor_unitid   = anchor_unitid,
    candidate_pool  = candidate_pool,
    theme_weights   = theme_weights,
    k               = raw_k,
    output_dir      = output_dir,
    ...
  )

  # Pull the wide pool so we can read each candidate's value on each
  # aspirational metric. compute_peers exposes the pool through
  # pool_distances and pool_unitids; we re-read the wide matrix instead
  # since we need the raw values, not z-scored.
  loaded <- .load_wide_facts(output_dir)
  schools <- .load_schools(file.path(output_dir, "schools.csv"))
  wide_full <- schools %>%
    select(unitid, instnm, stabbr) %>%
    left_join(loaded$wide, by = "unitid")

  anchor_row <- wide_full %>% filter(unitid == anchor_unitid)
  if (!nrow(anchor_row))
    stop(sprintf("Anchor unitid %d missing from wide matrix.", anchor_unitid))

  anchor_values <- vapply(aspirant_metrics, function(m) {
    if (!m %in% names(anchor_row)) return(NA_real_)
    as.numeric(anchor_row[[m]][1])
  }, numeric(1))

  if (any(is.na(anchor_values))) {
    miss <- aspirant_metrics[is.na(anchor_values)]
    stop("Anchor has no value for aspirational metric(s): ",
         paste(miss, collapse = ", "),
         ". Pick different metrics or another anchor.")
  }

  # Per-row directional check: TRUE if candidate beats anchor on metric m.
  better_than_anchor <- function(cand_val, anchor_val, direction) {
    if (!is.finite(cand_val) || !is.finite(anchor_val)) return(NA)
    if (direction == "higher") cand_val > anchor_val
    else if (direction == "lower") cand_val < anchor_val
    else NA
  }

  # Attach aspirational-metric values + per-metric "better" flags to the
  # peer table.
  augmented <- res$peers %>%
    left_join(wide_full %>%
                select(unitid, all_of(aspirant_metrics)),
              by = "unitid")

  # Build a per-row "beats" matrix.
  beats <- vapply(aspirant_metrics, function(m) {
    dir <- ASPIRANT_DIRECTIONS[[m]]
    vapply(augmented[[m]], function(v) {
      better_than_anchor(v, anchor_values[[m]], dir)
    }, logical(1))
  }, logical(nrow(augmented)))
  if (!is.matrix(beats)) beats <- matrix(beats, ncol = length(aspirant_metrics))
  colnames(beats) <- aspirant_metrics

  # Strict: beats on ALL metrics (NA counts as fail). Near-miss: beats on
  # all but exactly one metric.
  beats_real      <- beats; beats_real[is.na(beats_real)] <- FALSE
  beats_per_row   <- rowSums(beats_real)
  n_metrics       <- length(aspirant_metrics)

  strict_ix    <- which(beats_per_row == n_metrics)
  near_miss_ix <- which(beats_per_row == (n_metrics - 1L) & n_metrics > 1L)

  # For near-miss rows, identify which metric they missed.
  missed_metric <- vapply(near_miss_ix, function(i) {
    m_idx <- which(!beats_real[i, ])
    if (length(m_idx) == 1L) aspirant_metrics[m_idx] else NA_character_
  }, character(1))

  # Truncate
  strict_peers <- augmented[strict_ix, , drop = FALSE]
  if (nrow(strict_peers) > k) strict_peers <- strict_peers[seq_len(k), ]
  if (nrow(strict_peers)) strict_peers$rank <- seq_len(nrow(strict_peers))

  near_miss_peers <- augmented[near_miss_ix, , drop = FALSE]
  if (nrow(near_miss_peers)) {
    near_miss_peers$missed_metric <- missed_metric
    if (nrow(near_miss_peers) > near_miss_k)
      near_miss_peers <- near_miss_peers[seq_len(near_miss_k), ]
    near_miss_peers$rank <- seq_len(nrow(near_miss_peers))
  }

  list(
    strict_peers     = strict_peers,
    near_miss_peers  = near_miss_peers,
    aspirant_metrics = setNames(
      as.list(unlist(ASPIRANT_DIRECTIONS[aspirant_metrics])),
      aspirant_metrics),
    anchor_values    = anchor_values,
    meta             = res$meta
  )
}

# -----------------------------------------------------------------------------
# Usage:
#   source("R/peers_pipeline.R")
#   res <- compute_peers()
#   print_peers(res)
#
#   # Adjust theme weights (boost outcomes + finance)
#   res2 <- compute_peers(theme_weights = list(outcomes = 2.0, finance = 2.0))
#
#   # Different anchor (Williams = 168342)
#   res3 <- compute_peers(anchor_unitid = 168342)
#
#   # New England regional pool
#   res4 <- compute_peers(
#     candidate_pool = list(
#       in_ranked_universe = TRUE,
#       stabbr = c("MA","CT","RI","NH","VT","ME")
#     )
#   )
#
#   # Mahalanobis distance instead of Euclidean (accounts for correlation)
#   res5 <- compute_peers(distance_metric = "mahalanobis")
#
#   # Disable log transforms (compare with-vs-without to see the effect)
#   res6 <- compute_peers(log_transform = "none")
#
#   # Custom log-transform list
#   res7 <- compute_peers(log_transform = c("endowment_per_fte", "total_enrollment"))
#
#   # Compare methodologies side by side
#   euc <- compute_peers(distance_metric = "euclidean")
#   mah <- compute_peers(distance_metric = "mahalanobis")
#   intersect(euc$peers$unitid, mah$peers$unitid)  # shared peers across methods
#
#   # Filter to Catholic institutions only (uses religious_affiliation field)
#   res_cath <- compute_peers(
#     candidate_pool = list(
#       in_ranked_universe = TRUE,
#       religious_tradition = "Catholic"
#     )
#   )

#   # Up-weight Student body to make religious-tradition match more impactful
#   res_sb <- compute_peers(theme_weights = list(student_body = 2.0))
#
#   # Diagnostics
#   res$meta$variables_dropped_coverage   # variables below 70% in pool
#   res$meta$variables_used               # variables actually used
#   res$meta$log_transformed              # which were log-transformed
#   res$meta$weights                      # final per-variable weights
#   res$meta$distance_metric              # which distance was used
# -----------------------------------------------------------------------------