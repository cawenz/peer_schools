# =============================================================================
# Memoized wrapper around compute_peers().
#
# Repeat calls with identical arguments within a session return the cached
# result instead of re-running the (1-3s) peer computation. Memoise hashes
# the argument list, so any change in anchor, pool, weights, K, or distance
# metric busts the cache.
#
# Step 1: defined but not yet called. The Peer Search tab (step 3) will use
# this in place of compute_peers() directly.
# =============================================================================

suppressMessages(library(memoise))

compute_peers_cached <- memoise::memoise(function(
    anchor_unitid     = .DEFAULT_ANCHOR_UNITID,
    candidate_pool    = list(in_ranked_universe = TRUE),
    theme_weights     = list(),
    variable_weights  = list(),
    exclude_variables = NULL,
    coverage_threshold = 0.70,
    log_transform     = "default",
    distance_metric   = "euclidean",
    k                 = 20
) {
  compute_peers(
    anchor_unitid      = anchor_unitid,
    candidate_pool     = candidate_pool,
    theme_weights      = theme_weights,
    variable_weights   = variable_weights,
    exclude_variables  = exclude_variables,
    coverage_threshold = coverage_threshold,
    log_transform      = log_transform,
    distance_metric    = distance_metric,
    k                  = k,
    output_dir         = .OUTPUT_DIR
  )
})
