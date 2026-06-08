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

# -----------------------------------------------------------------------------
# Disk-I/O cache. compute_peers() internally calls .load_schools() and
# .load_wide_facts() on every invocation — those re-read schools.csv and
# 12 module CSVs, bind/aggregate/pivot them, and produce the wide facts
# matrix. None of that data changes during a Shiny session, so we wrap
# them with memoise here (in globalenv, after .safe_source_peer_pipeline
# placed the originals there). compute_peers() looks them up by name at
# call time, so the rebound memoised versions get used automatically —
# no change to compute_peers() needed.
#
# Cache key is the argument list (just output_dir, typically a constant
# for the session). First search pays the disk-read cost; subsequent
# searches hit a hot in-memory cache, saving 400-700ms per call.
# -----------------------------------------------------------------------------
.load_wide_facts <- memoise::memoise(.load_wide_facts)
.load_schools    <- memoise::memoise(.load_schools)

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
