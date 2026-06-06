# =============================================================================
# Download bundle builder. Given a saved-search object (as packed by the
# Saved Searches tab), writes a zip file containing:
#
#   peers.csv         the peer results table for this search
#   peers_wide.csv    wide matrix of all variables (clustering + descriptive)
#                     for the anchor + returned peers, with school metadata
#   codebook.csv      combined variable metadata across the 5 modules
#   methodology.txt   plain-text snapshot of the search settings used
#
# The methodology snapshot is the audit trail: it records the anchor,
# candidate-pool filters, theme weights, distance metric, coverage
# threshold, the variables that actually contributed to the distance,
# and the variables that were dropped (and why).
# =============================================================================

suppressMessages(library(zip))

bundle_download <- function(saved_search, out_path) {
  if (is.null(saved_search) || is.null(saved_search$peer_result))
    stop("bundle_download: saved_search is missing peer_result.")

  tmp <- tempfile("peer_bundle_")
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  res   <- saved_search$peer_result
  state <- saved_search$sidebar_state

  # ---- 1. peers.csv ---------------------------------------------------------
  utils::write.csv(res$peers,
                    file.path(tmp, "peers.csv"),
                    row.names = FALSE, na = "")

  # ---- 2. peers_wide.csv ----------------------------------------------------
  uids <- unique(c(res$meta$anchor_unitid, res$peers$unitid))
  wide <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid %in% uids, , drop = FALSE]
  # Attach rank from peers; anchor gets rank 0 to sort first
  rank_lookup <- c(setNames(0L, res$meta$anchor_unitid),
                   setNames(res$peers$rank, res$peers$unitid))
  wide$rank <- rank_lookup[as.character(wide$unitid)]
  wide <- wide[order(wide$rank), , drop = FALSE]
  # Move rank, unitid, instnm to the front for readability
  front <- c("rank", "unitid", "instnm")
  ordered_cols <- c(intersect(front, names(wide)),
                    setdiff(names(wide), front))
  utils::write.csv(wide[, ordered_cols, drop = FALSE],
                    file.path(tmp, "peers_wide.csv"),
                    row.names = FALSE, na = "")

  # ---- 3. codebook.csv ------------------------------------------------------
  utils::write.csv(build_codebook(),
                    file.path(tmp, "codebook.csv"),
                    row.names = FALSE, na = "")

  # ---- 4. methodology.txt ---------------------------------------------------
  writeLines(.build_methodology_snapshot(saved_search),
             file.path(tmp, "methodology.txt"))

  # ---- Zip the directory contents into out_path -----------------------------
  files <- list.files(tmp, full.names = FALSE, recursive = FALSE)
  old_wd <- setwd(tmp); on.exit(setwd(old_wd), add = TRUE)
  zip::zip(out_path, files = files, mode = "cherry-pick")

  invisible(out_path)
}

# -----------------------------------------------------------------------------
# methodology.txt content builder. Plain text, audit-friendly.
# -----------------------------------------------------------------------------
.build_methodology_snapshot <- function(saved_search) {
  res   <- saved_search$peer_result
  meta  <- res$meta
  state <- saved_search$sidebar_state

  hr <- strrep("-", 72)

  # Theme weights as a fixed-width block
  tw_lines <- vapply(names(state$theme_weights), function(t) {
    sprintf("  %-14s : %.2f", t, state$theme_weights[[t]])
  }, character(1))

  # Variables-dropped-coverage block
  dropped_cov <- meta$variables_dropped_coverage
  dropped_cov_lines <- if (is.data.frame(dropped_cov) && nrow(dropped_cov) > 0) {
    vapply(seq_len(nrow(dropped_cov)), function(i) {
      sprintf("  %s  (%.1f%% coverage in pool)",
              dropped_cov$metric[i],
              100 * as.numeric(dropped_cov$coverage[i]))
    }, character(1))
  } else "  (none)"

  dropped_anc <- meta$variables_dropped_anchor_na %||% character(0)
  dropped_anc_lines <- if (length(dropped_anc) > 0) {
    paste0("  ", dropped_anc)
  } else "  (none)"

  vars_used <- meta$variables_used %||% character(0)

  c(
    "Peer Schools search snapshot",
    hr,
    sprintf("Label:     %s", saved_search$label),
    sprintf("Saved at:  %s", format(saved_search$saved_at, "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "Search settings",
    hr,
    sprintf("Anchor institution    : %s (unitid %d)",
            meta$anchor_name, meta$anchor_unitid),
    sprintf("Peers requested (K)   : %d", state$k %||% NA),
    sprintf("Peers returned        : %d", nrow(res$peers)),
    sprintf("Distance metric       : %s", meta$distance_metric),
    sprintf("Coverage threshold    : %.0f%%",
            100 * (meta$coverage_threshold %||% NA)),
    "",
    "Candidate pool",
    hr,
    sprintf("Pool size after filter: %d", meta$candidate_pool_size),
    sprintf("Filter description    : %s",
            .describe_pool_filter(state$candidate_pool)),
    "",
    "Theme weights (1.0 = balanced default)",
    hr,
    tw_lines,
    "",
    sprintf("Variables used in distance computation (%d)", length(vars_used)),
    hr,
    if (length(vars_used) > 0) paste("  ", vars_used, sep = "") else "  (none)",
    "",
    "Variables dropped (below coverage threshold)",
    hr,
    dropped_cov_lines,
    "",
    "Variables dropped (anchor had no value)",
    hr,
    dropped_anc_lines,
    "",
    hr,
    "Generated by the Peer Schools Explorer Shiny app.",
    "See docs/Shiny_App_Spec.md and output/Peer_Schools_Methodology.docx",
    "for full methodology documentation."
  )
}
