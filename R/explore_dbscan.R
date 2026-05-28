# =============================================================================
# DBSCAN + HDBSCAN exploration
# Holy Cross peer-comparison project
#
# Purpose:
#   Run density-based clustering (DBSCAN and HDBSCAN) on the same z-scored
#   clustering matrix the rest of the project uses, and report:
#     - whether natural clusters emerge at all (vs. one big blob + noise)
#     - cluster count, noise share, and silhouette at a few parameter settings
#     - where Holy Cross lands (cluster id, cluster size, what else is in it)
#     - how HC's HDBSCAN cluster compares to compute_peers()'s top-K
#       weighted-Euclidean peers (overlap and what's different)
#
# What this script is NOT:
#   - A replacement for compute_peers(). Methodology stays weighted Euclidean.
#     This is a sanity check: do density methods find a structure consistent
#     with what the production pipeline returns?
#
# Approach:
#   1. Reuse prepare_clustvarsel_data() from explore_clustvarsel.R to build
#      the X matrix (ranked universe, 0.85 coverage, median imputation,
#      log-transformed where appropriate, z-scored).
#   2. DBSCAN: pick eps from a kNN distance plot ("knee") for each minPts.
#   3. HDBSCAN: vary minPts; HDBSCAN auto-picks its own scale via the
#      condensed cluster tree.
#   4. Locate HC, summarize membership, compare to weighted-Euclidean peers.
#
# Usage:
#   source("R/explore_clustvarsel.R")     # for prepare_clustvarsel_data()
#   source("R/explore_dbscan.R")
#
#   # Build the same matrix the clustvarsel work used (~30s).
#   prep <- prepare_clustvarsel_data()
#
#   # Pick eps off the kNN plot — writes output/dbscan_knn_*.png and returns
#   # a suggested eps per minPts value.
#   knn  <- dbscan_knn_plot(prep, minPts_grid = c(5, 10, 20),
#                           save_dir = "output")
#
#   # DBSCAN runs across a small parameter grid.
#   db   <- run_dbscan_grid(prep,
#                           param_grid = list(
#                             list(eps = knn$suggested["10"], minPts = 10),
#                             list(eps = knn$suggested["20"], minPts = 20)
#                           ))
#
#   # HDBSCAN across a few minPts; HDBSCAN doesn't need eps.
#   hdb  <- run_hdbscan_grid(prep, minPts_grid = c(5, 10, 15, 25))
#
#   # Per-method summary.
#   summarize_dbscan(db,  prep)
#   summarize_hdbscan(hdb, prep)
#
#   # Cross-method comparison against the production peer ranking.
#   compare_to_weighted_euclidean(hdb, prep, k = 25)
#
#   # Persist for the findings doc.
#   saveRDS(list(prep = prep, knn = knn, dbscan = db, hdbscan = hdb),
#           "output/dbscan_run.rds")
# =============================================================================

suppressMessages({
  library(dplyr); library(tidyr); library(stringr); library(readr); library(tibble)
})

.require_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop(sprintf("Package '%s' is required. install.packages(\"%s\").",
                 pkg, pkg), call. = FALSE)
}

# -----------------------------------------------------------------------------
# Anchor lookup helper. prep$X has unitids as rownames; we need HC's row index.
# -----------------------------------------------------------------------------
.anchor_index <- function(prep, anchor_unitid = 166124L) {
  rn <- rownames(prep$X)
  ix <- which(as.integer(rn) == as.integer(anchor_unitid))
  if (!length(ix))
    stop(sprintf("Anchor unitid %d not found in prep$X rownames.",
                 anchor_unitid))
  ix
}

# -----------------------------------------------------------------------------
# k-NN distance plot. For each minPts in the grid, compute each point's
# distance to its k-th nearest neighbor, sort descending, and pick the
# "knee" as a suggested eps. Writes one PNG per minPts.
# -----------------------------------------------------------------------------

#' @param prep         Output of prepare_clustvarsel_data().
#' @param minPts_grid  Integer vector of minPts values to evaluate.
#' @param save_dir     Where to write the PNGs (NULL = no plot, just compute).
#' @param knee_quantile Quantile used as a heuristic for the knee. Default
#'   0.95 picks eps roughly at the 95th percentile of k-NN distances, which
#'   tends to leave ~5% of points as noise — usually a sensible starting
#'   point for DBSCAN.
#'
#' @return list(distances = matrix [n x length(minPts_grid)],
#'              suggested = named numeric vector eps[minPts])
dbscan_knn_plot <- function(prep,
                            minPts_grid    = c(5, 10, 20),
                            save_dir       = "output",
                            knee_quantile  = 0.95) {
  .require_pkg("dbscan")
  X <- as.matrix(prep$X)

  out_dist <- matrix(NA_real_, nrow = nrow(X), ncol = length(minPts_grid))
  colnames(out_dist) <- as.character(minPts_grid)
  suggested <- setNames(numeric(length(minPts_grid)),
                         as.character(minPts_grid))

  for (i in seq_along(minPts_grid)) {
    k <- minPts_grid[i]
    # kNNdist returns distances to the k-th nearest neighbor (excluding self).
    d <- dbscan::kNNdist(X, k = k)
    out_dist[, i] <- d
    eps_hat <- as.numeric(stats::quantile(d, probs = knee_quantile,
                                          na.rm = TRUE))
    suggested[as.character(k)] <- eps_hat

    if (!is.null(save_dir)) {
      if (!dir.exists(save_dir)) dir.create(save_dir, recursive = TRUE)
      png(file.path(save_dir, sprintf("dbscan_knn_minPts_%02d.png", k)),
          width = 900, height = 600, res = 120)
      plot(sort(d), type = "l", lwd = 2, col = "#602D89",
           main = sprintf("k-NN distance plot (k = %d)", k),
           xlab = "Points sorted by distance",
           ylab = sprintf("Distance to %d-th nearest neighbor", k))
      abline(h = eps_hat, col = "#AC9E94", lty = 2, lwd = 1.5)
      mtext(sprintf("Suggested eps (q%.0f) = %.3f",
                    100 * knee_quantile, eps_hat),
            side = 3, line = 0.3, cex = 0.95, col = "#251230")
      dev.off()
    }
  }

  message(sprintf("kNN suggested eps:  %s",
                  paste(sprintf("minPts=%d -> %.3f",
                                 minPts_grid, suggested),
                         collapse = "  |  ")))
  list(distances = out_dist, suggested = suggested,
       knee_quantile = knee_quantile)
}

# -----------------------------------------------------------------------------
# DBSCAN grid runner
# -----------------------------------------------------------------------------

#' @param prep        Output of prepare_clustvarsel_data().
#' @param param_grid  List of list(eps, minPts) entries.
#'
#' @return list of per-setting results, each:
#'   list(eps, minPts, n_clusters, n_noise, noise_share, sizes,
#'        cluster, silhouette_mean)
run_dbscan_grid <- function(prep, param_grid) {
  .require_pkg("dbscan")
  X <- as.matrix(prep$X)

  lapply(param_grid, function(p) {
    fit <- dbscan::dbscan(X, eps = p$eps, minPts = p$minPts)
    cl  <- fit$cluster
    n_clusters <- length(unique(cl[cl > 0]))
    n_noise    <- sum(cl == 0)
    sizes      <- as.integer(table(cl[cl > 0]))

    sil_mean <- NA_real_
    if (n_clusters >= 2 && (length(cl) - n_noise) >= 5) {
      # Mean silhouette over non-noise points only — noise points carry no
      # cluster assignment so they're excluded from the score.
      keep <- cl > 0
      sil_mean <- tryCatch({
        s <- cluster::silhouette(cl[keep], stats::dist(X[keep, , drop = FALSE]))
        mean(s[, "sil_width"], na.rm = TRUE)
      }, error = function(e) NA_real_)
    }

    list(
      eps             = p$eps,
      minPts          = p$minPts,
      n_clusters      = n_clusters,
      n_noise         = n_noise,
      noise_share     = n_noise / length(cl),
      sizes           = sizes,
      cluster         = cl,
      silhouette_mean = sil_mean
    )
  })
}

# -----------------------------------------------------------------------------
# HDBSCAN grid runner. minPts only — HDBSCAN doesn't take an eps.
# -----------------------------------------------------------------------------

#' @return list of per-minPts results, each:
#'   list(minPts, n_clusters, n_noise, noise_share, sizes, cluster,
#'        membership_prob, outlier_score, silhouette_mean,
#'        cluster_tree_depth, fit (raw hdbscan object))
run_hdbscan_grid <- function(prep, minPts_grid = c(5, 10, 15, 25)) {
  .require_pkg("dbscan")
  X <- as.matrix(prep$X)

  lapply(minPts_grid, function(mp) {
    fit <- dbscan::hdbscan(X, minPts = mp)
    cl  <- fit$cluster
    n_clusters <- length(unique(cl[cl > 0]))
    n_noise    <- sum(cl == 0)
    sizes      <- as.integer(table(cl[cl > 0]))

    sil_mean <- NA_real_
    if (n_clusters >= 2 && (length(cl) - n_noise) >= 5) {
      keep <- cl > 0
      sil_mean <- tryCatch({
        s <- cluster::silhouette(cl[keep], stats::dist(X[keep, , drop = FALSE]))
        mean(s[, "sil_width"], na.rm = TRUE)
      }, error = function(e) NA_real_)
    }

    list(
      minPts          = mp,
      n_clusters      = n_clusters,
      n_noise         = n_noise,
      noise_share     = n_noise / length(cl),
      sizes           = sizes,
      cluster         = cl,
      membership_prob = fit$membership_prob,
      outlier_score   = fit$outlier_scores,
      silhouette_mean = sil_mean,
      fit             = fit
    )
  })
}

# -----------------------------------------------------------------------------
# Pretty summaries
# -----------------------------------------------------------------------------

.cluster_member_table <- function(prep, cl, anchor_unitid = 166124L,
                                   schools_csv = "output/schools.csv",
                                   top_n = 25) {
  schools <- read_csv(schools_csv, show_col_types = FALSE) %>%
    select(unitid, instnm, stabbr,
            any_of(c("control_grp", "usnews_classification")))
  rn <- as.integer(rownames(prep$X))
  ai <- .anchor_index(prep, anchor_unitid)
  hc_cluster <- cl[ai]

  if (hc_cluster == 0) {
    return(list(hc_cluster = 0L,
                msg = "Holy Cross was classified as NOISE under this setting.",
                table = tibble()))
  }

  mates_ix <- which(cl == hc_cluster)
  mates <- tibble(unitid = rn[mates_ix]) %>%
    left_join(schools, by = "unitid")

  list(
    hc_cluster = hc_cluster,
    msg = sprintf("Holy Cross is in cluster %d (size = %d).",
                  hc_cluster, length(mates_ix)),
    table = head(mates, top_n)
  )
}

summarize_dbscan <- function(db, prep, anchor_unitid = 166124L,
                              top_n = 25) {
  for (i in seq_along(db)) {
    r <- db[[i]]
    cat(sprintf(
      "\nDBSCAN setting %d:  eps = %.3f, minPts = %d\n",
      i, r$eps, r$minPts))
    cat(sprintf("  clusters: %d   noise: %d (%.1f%%)   silhouette: %s\n",
                r$n_clusters, r$n_noise, 100 * r$noise_share,
                ifelse(is.na(r$silhouette_mean), "n/a",
                       sprintf("%.3f", r$silhouette_mean))))
    if (length(r$sizes))
      cat(sprintf("  cluster sizes: %s\n",
                  paste(r$sizes, collapse = ", ")))
    m <- .cluster_member_table(prep, r$cluster, anchor_unitid, top_n = top_n)
    cat("  ", m$msg, "\n", sep = "")
    if (nrow(m$table)) {
      print(m$table)
    }
  }
  invisible(NULL)
}

summarize_hdbscan <- function(hdb, prep, anchor_unitid = 166124L,
                               top_n = 25) {
  for (i in seq_along(hdb)) {
    r <- hdb[[i]]
    cat(sprintf("\nHDBSCAN setting %d:  minPts = %d\n", i, r$minPts))
    cat(sprintf("  clusters: %d   noise: %d (%.1f%%)   silhouette: %s\n",
                r$n_clusters, r$n_noise, 100 * r$noise_share,
                ifelse(is.na(r$silhouette_mean), "n/a",
                       sprintf("%.3f", r$silhouette_mean))))
    if (length(r$sizes))
      cat(sprintf("  cluster sizes: %s\n",
                  paste(r$sizes, collapse = ", ")))
    m <- .cluster_member_table(prep, r$cluster, anchor_unitid, top_n = top_n)
    ai <- .anchor_index(prep, anchor_unitid)
    if (!is.null(r$membership_prob))
      cat(sprintf("  HC membership probability: %.2f\n",
                  r$membership_prob[ai]))
    if (!is.null(r$outlier_score))
      cat(sprintf("  HC outlier score (GLOSH):  %.3f\n",
                  r$outlier_score[ai]))
    cat("  ", m$msg, "\n", sep = "")
    if (nrow(m$table)) {
      print(m$table)
    }
  }
  invisible(NULL)
}

# -----------------------------------------------------------------------------
# Cross-method comparison: how does HC's HDBSCAN cluster compare to the
# weighted-Euclidean top-K peers from compute_peers()?
# -----------------------------------------------------------------------------

#' Requires compute_peers() in scope. The simplest way: source the truncated
#' peer_pipeline.R the way shiny_app/global.R does. We replicate the trick
#' here to avoid the un-commented Usage calls in peer_pipeline.R firing.
.source_peer_pipeline <- function(path = "R/peer_pipeline.R") {
  txt <- readLines(path, warn = FALSE)
  usage_idx <- grep("^#\\s*Usage:", txt)
  if (length(usage_idx)) txt <- txt[seq_len(usage_idx[1] - 1)]
  tmp <- tempfile(fileext = ".R")
  writeLines(txt, tmp); on.exit(unlink(tmp), add = TRUE)
  sys.source(tmp, envir = globalenv())
}

#' For each HDBSCAN setting:
#'  - compute_peers() for HC (k peers, weighted Euclidean).
#'  - Compare against HC's HDBSCAN cluster mates (set overlap).
#'  - Report the overlap count and which weighted-Euclidean peers fell
#'    outside HC's HDBSCAN cluster (suggests HDBSCAN is grouping by
#'    different structure, or that they're border/noise points).
#'
#' @return tibble with one row per HDBSCAN setting.
compare_to_weighted_euclidean <- function(hdb, prep,
                                           anchor_unitid = 166124L,
                                           k = 25) {
  if (!exists("compute_peers", mode = "function")) {
    .source_peer_pipeline()
  }
  rn <- as.integer(rownames(prep$X))

  # Production peer set (weighted Euclidean, ranked universe, default
  # theme weights). Matching what the Shiny app does by default.
  peers <- compute_peers(
    anchor_unitid   = anchor_unitid,
    candidate_pool  = list(in_ranked_universe = TRUE),
    distance_metric = "euclidean",
    k               = k
  )
  prod_uids <- peers$peers$unitid

  schools <- read_csv("output/schools.csv", show_col_types = FALSE) %>%
    select(unitid, instnm, stabbr)

  rows <- lapply(seq_along(hdb), function(i) {
    r  <- hdb[[i]]
    ai <- .anchor_index(prep, anchor_unitid)
    hc_cluster  <- r$cluster[ai]
    if (hc_cluster == 0) {
      return(tibble(
        minPts                  = r$minPts,
        hc_in_noise             = TRUE,
        cluster_size            = NA_integer_,
        overlap_with_weighted_k = NA_integer_,
        overlap_pct             = NA_real_
      ))
    }
    mate_uids <- rn[r$cluster == hc_cluster]
    overlap   <- intersect(prod_uids, mate_uids)
    tibble(
      minPts                  = r$minPts,
      hc_in_noise             = FALSE,
      cluster_size            = length(mate_uids),
      overlap_with_weighted_k = length(overlap),
      overlap_pct             = length(overlap) / k
    )
  })
  out <- bind_rows(rows)

  # Print a short narrative.
  for (i in seq_along(hdb)) {
    r <- hdb[[i]]
    ai <- .anchor_index(prep, anchor_unitid)
    hc_cluster <- r$cluster[ai]
    cat(sprintf("\n[minPts = %d]\n", r$minPts))
    if (hc_cluster == 0) {
      cat("  HC is NOISE; no overlap with top-K weighted peers.\n")
    } else {
      mate_uids <- rn[r$cluster == hc_cluster]
      both      <- intersect(prod_uids, mate_uids)
      only_wt   <- setdiff(prod_uids, mate_uids)
      cat(sprintf("  HC cluster size: %d   overlap with top-%d weighted peers: %d (%.0f%%)\n",
                  length(mate_uids), k, length(both),
                  100 * length(both) / k))
      if (length(only_wt)) {
        cat("  Top weighted peers NOT in HC's HDBSCAN cluster:\n")
        miss <- tibble(unitid = only_wt) %>%
          left_join(schools, by = "unitid") %>%
          mutate(rank = match(unitid, prod_uids)) %>%
          arrange(rank)
        print(head(miss, 10))
      }
    }
  }
  invisible(out)
}
