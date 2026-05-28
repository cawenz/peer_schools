# =============================================================================
# clustvarsel exploration — Layer 3 variable selection
# Holy Cross peer-comparison project
#
# Purpose:
#   Run clustvarsel (forward-backward variable selection for Gaussian mixture
#   models) over the project's 53 clustering variables to see which subset
#   carries cluster signal. The output is a research finding to inform the
#   Shiny app's default variable set, NOT a replacement for compute_peers().
#
# What this script does (and doesn't do):
#   - Builds the same wide variable matrix compute_peers() uses (ranked
#     universe by default), applies the same log transforms and z-scoring,
#     then hands a clean matrix to clustvarsel.
#   - Handles missing data via (1) a stricter per-variable coverage threshold,
#     then (2) median imputation on the residual gaps. mclust/clustvarsel
#     require complete-case data; the 70% threshold used by compute_peers
#     leaves enough NAs that listwise deletion would gut the matrix.
#   - Does NOT integrate findings back into compute_peers(). That's a
#     downstream decision after we look at the output.
#
# Why we don't source("R/peer_pipeline.R"):
#   That file has stray un-commented `compute_peers()` calls in its Usage
#   footer (~lines 568-569 and 600-605) that fire on source. Helpers used
#   here are duplicated locally until that's fixed.
#
# Usage:
#   source("R/explore_clustvarsel.R")
#
#   # 1) Validate plumbing first (small subset, small G range, ~minutes):
#   prep <- prepare_clustvarsel_data(quick_test = TRUE)
#   fit  <- run_clustvarsel_analysis(prep, G = 2:4, parallel = FALSE)
#   summarize_clustvarsel(fit, prep)
#
#   # 2) Real run (ranked universe, G = 1:9, parallel; can take 30+ minutes):
#   prep <- prepare_clustvarsel_data()
#   fit  <- run_clustvarsel_analysis(prep, parallel = TRUE)
#   summarize_clustvarsel(fit, prep)
#
#   # 3) Persist
#   saveRDS(list(prep = prep, fit = fit), "output/clustvarsel_run.rds")
# =============================================================================

suppressMessages({
  library(dplyr); library(tidyr); library(stringr); library(readr); library(tibble)
})

.require_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop(sprintf("Package '%s' is required. Install with: install.packages(\"%s\")",
                 pkg, pkg), call. = FALSE)
}

# -----------------------------------------------------------------------------
# Helpers duplicated from peer_pipeline.R (see header comment for why)
# Keep these in sync if THEME_VARS / LOG_TRANSFORM_VARS change upstream.
# -----------------------------------------------------------------------------

.THEME_VARS <- list(
  scale = c(
    "total_enrollment", "undergraduate_enrollment",
    "first_time_enrollment", "full_time_enrollment"
  ),
  selectivity = c(
    "acceptance_rate", "yield_rate", "application_volume",
    "pct_submitting_sat", "pct_submitting_act", "pct_top10_hs",
    "ed_acceptance_rate", "ed_share_of_applications", "yield_gap_men_women"
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
    "avg_net_price", "avg_net_price_income_0_30k", "pct_pell", "pell_count",
    "pct_grant_aid", "avg_inst_grant", "inst_discount_rate",
    "pct_borrowing", "avg_fed_loan", "pct_need_met", "pct_need_fully_met"
  ),
  composition = c(
    "pct_undergrad", "pct_part_time", "pct_age_25plus",
    "pct_first_generation", "median_family_income",
    "pct_white", "pct_international", "pct_bipoc", "pct_race_unknown",
    "transfer_in_enrollment", "residential_share"
    # same_religious_tradition deliberately excluded here — it's anchor-relative
    # and not meaningful for unsupervised variable selection.
  )
)

.COMPOSITION_HALF_WEIGHT <- c(
  "pct_black", "pct_hispanic", "pct_asian",
  "pct_nhpi", "pct_aian", "pct_two_or_more"
)

.LOG_TRANSFORM_VARS <- c(
  "total_enrollment", "undergraduate_enrollment",
  "first_time_enrollment", "full_time_enrollment",
  "transfer_in_enrollment",
  "application_volume",
  "endowment_per_fte", "net_assets_per_fte", "core_expenses_per_fte",
  "instruction_per_fte", "academic_support_per_fte",
  "student_services_per_fte", "herd_avg",
  "published_tuition_fees", "avg_net_price", "avg_net_price_income_0_30k",
  "avg_inst_grant", "avg_fed_loan",
  "pell_count", "doctoral_degrees_awarded",
  "avg_ft_faculty_salary", "median_earnings_10yr", "median_earnings_6yr",
  "median_family_income"
)

.var_theme <- function(v) {
  for (t in names(.THEME_VARS)) if (v %in% .THEME_VARS[[t]]) return(t)
  if (v %in% .COMPOSITION_HALF_WEIGHT) return("composition")
  NA_character_
}

# -----------------------------------------------------------------------------
# Data loading
# -----------------------------------------------------------------------------

.load_schools <- function(path = "output/schools.csv") {
  read_csv(path, show_col_types = FALSE) %>%
    mutate(unitid = as.integer(unitid),
           in_ranked_universe = as.logical(in_ranked_universe))
}

.load_wide_facts <- function(output_dir = "output") {
  module_keys <- c("aid", "adm", "enr", "out", "fin")
  all_facts <- list(); all_vars <- list()
  for (mk in module_keys) {
    fp <- file.path(output_dir, paste0(mk, "_facts.csv"))
    vp <- file.path(output_dir, paste0(mk, "_variables.csv"))
    if (!file.exists(fp) || !file.exists(vp)) {
      warning(sprintf("Skipping module %s — missing files", mk))
      next
    }
    all_facts[[mk]] <- read_csv(fp, show_col_types = FALSE)
    all_vars[[mk]]  <- read_csv(vp, show_col_types = FALSE) %>% mutate(module = mk)
  }
  vars <- bind_rows(all_vars)
  facts <- bind_rows(all_facts)

  clustering_vars <- vars %>% filter(use_type == "clustering") %>% pull(metric)
  clustering_vars <- union(clustering_vars, .COMPOSITION_HALF_WEIGHT)

  aggregated <- facts %>%
    filter(metric %in% clustering_vars) %>%
    group_by(unitid, metric) %>%
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
    filter(is.finite(value))

  wide <- aggregated %>%
    select(unitid, metric, value) %>%
    pivot_wider(names_from = metric, values_from = value)

  list(wide = wide, variables = vars,
       available_metrics = unique(aggregated$metric))
}

# -----------------------------------------------------------------------------
# Data preparation for clustvarsel
# -----------------------------------------------------------------------------

#' Build a complete-case standardized matrix ready for clustvarsel.
#'
#' @param candidate_pool Named list of schools.csv filters. Default ranked
#'   universe.
#' @param coverage_threshold Drop variables with within-pool coverage below
#'   this. Default 0.85 (stricter than compute_peers' 0.70, because we want
#'   a dense matrix; lower threshold means more imputation downstream).
#' @param impute One of "median", "mean", "none". Default "median". "none"
#'   does listwise deletion — usually decimates the matrix.
#' @param log_transform "default" applies log10(x+1) to .LOG_TRANSFORM_VARS;
#'   "none" disables.
#' @param quick_test If TRUE, restrict to a random sample of 250 schools and
#'   the 25 highest-coverage variables. Use to validate the pipeline before
#'   the real run.
#' @param seed Used only for quick_test sampling and for any imputation that
#'   needs reproducibility.
#'
#' @return list with: X (matrix, rows = unitids, cols = variables, all
#'   z-scored and complete), unitids, vars_used, vars_dropped_coverage,
#'   imputation_summary, log_transformed, anchor_unitid.
prepare_clustvarsel_data <- function(
    candidate_pool     = list(in_ranked_universe = TRUE),
    coverage_threshold = 0.85,
    impute             = c("median", "mean", "none"),
    log_transform      = "default",
    quick_test         = FALSE,
    anchor_unitid      = 166124L,
    seed               = 1L,
    output_dir         = "output"
) {
  impute <- match.arg(impute)
  set.seed(seed)

  schools <- .load_schools(file.path(output_dir, "schools.csv"))
  loaded  <- .load_wide_facts(output_dir)
  wide    <- loaded$wide

  candidates <- schools
  for (col in names(candidate_pool)) {
    if (!col %in% names(candidates))
      stop(sprintf("Filter column '%s' not in schools.csv", col))
    candidates <- candidates %>% filter(.data[[col]] %in% candidate_pool[[col]])
  }
  # Make sure the anchor is present so we can locate it in the output later.
  if (!anchor_unitid %in% candidates$unitid) {
    candidates <- bind_rows(candidates, schools %>% filter(unitid == anchor_unitid))
  }

  cdat <- candidates %>%
    select(unitid, instnm) %>%
    left_join(wide, by = "unitid")

  candidate_metrics <- intersect(loaded$available_metrics, names(cdat))

  coverage_df <- tibble(
    metric = candidate_metrics,
    coverage = vapply(candidate_metrics,
                      function(m) mean(!is.na(cdat[[m]])), numeric(1))
  ) %>% arrange(desc(coverage))

  vars_passing <- coverage_df %>%
    filter(coverage >= coverage_threshold) %>% pull(metric)
  vars_dropped_cov <- coverage_df %>% filter(coverage < coverage_threshold)

  if (quick_test) {
    vars_passing <- head(vars_passing, 25)
    # Sample a small slice but keep the anchor in.
    keep_unitids <- unique(c(anchor_unitid,
                             sample(cdat$unitid, min(250, nrow(cdat)))))
    cdat <- cdat %>% filter(unitid %in% keep_unitids)
  }

  if (!length(vars_passing))
    stop("No variables clear the coverage threshold.")

  X <- cdat %>%
    select(unitid, all_of(vars_passing)) %>%
    column_to_rownames("unitid") %>%
    as.data.frame()

  # Log-transform first (so imputation operates in log space for skewed vars).
  vars_to_log <- if (identical(log_transform, "default")) {
    intersect(.LOG_TRANSFORM_VARS, vars_passing)
  } else if (identical(log_transform, "none")) {
    character(0)
  } else if (is.character(log_transform)) {
    intersect(log_transform, vars_passing)
  } else {
    stop("log_transform must be 'default', 'none', or a character vector")
  }
  for (v in vars_to_log) {
    X[[v]] <- ifelse(is.na(X[[v]]), NA_real_, log10(pmax(X[[v]], 0) + 1))
  }

  # Imputation pass — record how many cells were filled per variable so the
  # findings doc can call out heavily-imputed variables (their loadings in
  # the clustvarsel output should be read with extra skepticism).
  na_counts_before <- sapply(X, function(col) sum(is.na(col)))
  if (impute != "none") {
    fill_fn <- if (impute == "median") function(x) median(x, na.rm = TRUE)
               else                    function(x) mean(x,   na.rm = TRUE)
    for (v in names(X)) {
      if (anyNA(X[[v]])) {
        X[[v]][is.na(X[[v]])] <- fill_fn(X[[v]])
      }
    }
  } else {
    X <- X[complete.cases(X), , drop = FALSE]
  }

  # Z-score (after imputation so means/sd are computed on filled values).
  for (v in names(X)) {
    mu <- mean(X[[v]], na.rm = TRUE)
    sigma <- sd(X[[v]], na.rm = TRUE)
    if (is.na(sigma) || sigma == 0) X[[v]] <- 0
    else                            X[[v]] <- (X[[v]] - mu) / sigma
  }

  if (anyNA(X)) {
    # Should be impossible after impute, but defensive.
    n_before <- nrow(X)
    X <- X[complete.cases(X), , drop = FALSE]
    message(sprintf("Dropped %d rows that still had NA after imputation.",
                    n_before - nrow(X)))
  }

  list(
    X                 = as.matrix(X),
    unitids           = as.integer(rownames(X)),
    instnm_lookup     = setNames(cdat$instnm, as.character(cdat$unitid)),
    vars_used         = colnames(X),
    coverage_df       = coverage_df,
    vars_dropped_coverage = vars_dropped_cov,
    log_transformed   = vars_to_log,
    imputation        = list(method = impute, na_counts_before = na_counts_before),
    candidate_pool    = candidate_pool,
    coverage_threshold = coverage_threshold,
    anchor_unitid     = anchor_unitid,
    quick_test        = quick_test
  )
}

# -----------------------------------------------------------------------------
# clustvarsel runner
# -----------------------------------------------------------------------------

#' Run clustvarsel on a prepared matrix.
#'
#' @param prep List returned by prepare_clustvarsel_data().
#' @param G Vector of cluster counts to evaluate. Default 1:9 (clustvarsel
#'   default).
#' @param search "headlong" (faster, accepts the first improving move) or
#'   "greedy" (more exhaustive).
#' @param direction "forward", "backward", or both via two passes.
#' @param parallel If TRUE, uses all but one core.
#' @param verbose Pass-through to clustvarsel.
#'
#' @return list with: cv (raw clustvarsel object), mclust_fit (Mclust on the
#'   selected variables), selected, rejected, G_chosen, elapsed_secs.
run_clustvarsel_analysis <- function(
    prep,
    G          = 1:9,
    search     = c("headlong", "greedy"),
    direction  = c("forward", "backward"),
    parallel   = FALSE,
    verbose    = TRUE
) {
  .require_pkg("mclust"); .require_pkg("clustvarsel")
  # clustvarsel dispatches its forward/backward routines via match.fun(),
  # which needs both packages on the search path — namespace-only access via
  # :: is not enough.
  suppressMessages({ library(mclust); library(clustvarsel) })
  search    <- match.arg(search)
  direction <- match.arg(direction)

  X <- prep$X
  if (anyNA(X)) stop("prep$X must be complete-case; got NAs.")

  parallel_arg <- if (isTRUE(parallel)) TRUE else FALSE

  t0 <- Sys.time()
  cv <- clustvarsel::clustvarsel(
    data      = X,
    G         = G,
    search    = search,
    direction = direction,
    parallel  = parallel_arg,
    verbose   = verbose
  )
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  selected_vars <- if (is.null(cv$subset)) character(0)
                   else colnames(X)[cv$subset]
  rejected_vars <- setdiff(colnames(X), selected_vars)

  mclust_fit <- if (length(selected_vars))
    mclust::Mclust(X[, selected_vars, drop = FALSE], G = G, verbose = FALSE)
    else NULL

  list(
    cv             = cv,
    mclust_fit     = mclust_fit,
    selected       = selected_vars,
    rejected       = rejected_vars,
    G_chosen       = if (!is.null(mclust_fit)) mclust_fit$G else NA_integer_,
    elapsed_secs   = elapsed,
    search         = search,
    direction      = direction,
    G_range        = G
  )
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

#' Print a human-readable summary of a clustvarsel run.
summarize_clustvarsel <- function(fit, prep) {
  cat("== clustvarsel summary ==\n")
  cat(sprintf("Candidate pool: %d schools, %d variables submitted\n",
              nrow(prep$X), ncol(prep$X)))
  cat(sprintf("Coverage threshold: %.0f%%; imputation: %s\n",
              100 * prep$coverage_threshold, prep$imputation$method))
  cat(sprintf("Quick-test mode: %s\n", prep$quick_test))
  cat(sprintf("Search: %s, %s; G range: %s; elapsed: %.1fs\n",
              fit$search, fit$direction,
              paste(range(fit$G_range), collapse = "-"), fit$elapsed_secs))
  cat(sprintf("\nSelected %d / %d variables; best G = %s\n",
              length(fit$selected), ncol(prep$X), fit$G_chosen))

  if (!length(fit$selected)) {
    cat("(clustvarsel selected no variables — model is the null mixture)\n")
    return(invisible(NULL))
  }

  by_theme <- tibble(
    metric  = colnames(prep$X),
    theme   = vapply(colnames(prep$X), .var_theme, character(1)),
    status  = ifelse(colnames(prep$X) %in% fit$selected, "selected", "rejected")
  )

  cat("\nBy theme (selected / total):\n")
  per_theme <- by_theme %>%
    group_by(theme) %>%
    summarise(selected = sum(status == "selected"),
              total    = n(),
              vars_selected = paste(metric[status == "selected"], collapse = ", "),
              .groups = "drop") %>%
    arrange(desc(selected / total))
  print(per_theme %>% select(theme, selected, total))

  cat("\nSelected variables (by theme):\n")
  for (i in seq_len(nrow(per_theme))) {
    cat(sprintf("  [%s] %s\n",
                per_theme$theme[i],
                if (nchar(per_theme$vars_selected[i]))
                  per_theme$vars_selected[i] else "(none)"))
  }

  cat("\nRejected variables:\n")
  rej <- by_theme %>% filter(status == "rejected") %>% arrange(theme, metric)
  for (t in unique(rej$theme)) {
    these <- rej %>% filter(theme == t) %>% pull(metric)
    cat(sprintf("  [%s] %s\n", t, paste(these, collapse = ", ")))
  }

  # Anchor's component assignment + a few co-members
  if (!is.null(fit$mclust_fit) && prep$anchor_unitid %in% prep$unitids) {
    idx <- match(prep$anchor_unitid, prep$unitids)
    if (!is.na(idx)) {
      cls <- fit$mclust_fit$classification[idx]
      same_cls_unitids <- prep$unitids[fit$mclust_fit$classification == cls]
      same_cls_names   <- prep$instnm_lookup[as.character(same_cls_unitids)]
      cat(sprintf(
        "\nAnchor unitid %d → component %d (%d co-members; sample:\n  %s\n)\n",
        prep$anchor_unitid, cls, length(same_cls_unitids),
        paste(head(setdiff(same_cls_names, NA), 12), collapse = ", ")
      ))
    }
  }

  invisible(by_theme)
}

# -----------------------------------------------------------------------------
# End of file. No auto-execution — call the functions above explicitly.
# -----------------------------------------------------------------------------
