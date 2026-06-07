# =============================================================================
# Download builders for the Peer Search page.
#
#   build_peer_xlsx(peer_result, state, out_path)
#     Two-sheet workbook:
#       Sheet 1 "Peer list" — same columns the user sees in the DT
#       Sheet 2 "Variables" — every clustering + descriptive variable for
#                             anchor + returned peers (wide matrix from
#                             .SCHOOLS_WIDE).
#
#   build_peer_pdf(peer_result, state, out_path)
#     Compact one-pager: anchor + filters + theme weights, the ranked
#     list as a table, then the 5 composition cards (US News classification,
#     Carnegie size, region, research activity, athletics division). Uses
#     rmarkdown via shiny_app/templates/peer_report.Rmd and tinytex.
#
# Both functions are pure helpers — no Shiny dependencies, just take a
# peer_result + state and write to a path. The Shiny downloadHandlers in
# mod_peer_table.R bind them to buttons in the results-header.
# =============================================================================

suppressMessages({
  library(openxlsx)
})

# -----------------------------------------------------------------------------
# Curated "key variables" list used by both downloads. ~20 metrics covering
# every clustering theme, picked for institutional-research prominence:
# - Size: enrollment headcounts
# - Selectivity: admit + yield + entering-class quality (sat_mid50 is
#   descriptive but the most-asked-for benchmark)
# - Aid: net price + Pell + discount rate
# - Resources: faculty ratio + faculty salary + small-class share
# - Finance: endowment + tuition
# - Outcomes: grad + retention + earnings + Pell-grad gap
# - Student body: BIPOC + first-gen + residential share
# Edit this list if a different cut should drive the report; the Excel
# "Key variables" sheet and the PDF density plots both read from it.
.KEY_VARS_20 <- c(
  # Size
  "total_enrollment", "undergraduate_enrollment",
  # Selectivity
  "acceptance_rate", "yield_rate", "sat_mid50",
  # Aid
  "avg_net_price_aided", "pct_pell", "inst_discount_rate",
  # Resources
  "student_faculty_ratio", "avg_ft_faculty_salary", "pct_classes_under_20",
  # Finance
  "endowment_per_fte", "published_tuition_fees",
  # Outcomes
  "grad_rate_6yr", "retention_rate", "median_earnings_10yr", "pell_grad_gap",
  # Student body
  "pct_bipoc", "pct_first_generation", "residential_share"
)

# The 8-variable subset that the PDF density plots feature. Picked to fit
# legibly in a 2x4 grid on a single page. Subset of .KEY_VARS_20 above.
.PDF_DENSITY_VARS <- c(
  "total_enrollment",
  "acceptance_rate",
  "pct_pell",
  "avg_net_price_aided",
  "student_faculty_ratio",
  "endowment_per_fte",
  "grad_rate_6yr",
  "median_earnings_10yr"
)

# -----------------------------------------------------------------------------
# XLSX
# -----------------------------------------------------------------------------
build_peer_xlsx <- function(peer_result, state, out_path) {
  if (is.null(peer_result) || is.null(peer_result$peers))
    stop("build_peer_xlsx: peer_result is missing.")

  peers <- peer_result$peers
  anchor_uid <- peer_result$meta$anchor_unitid

  # ---- Sheet 1 — visible columns ------------------------------------------
  wamo_short <- c("Liberal Arts" = "LA", "Baccalaureate" = "Bacc",
                   "Master's" = "Mas",  "National" = "Nat")
  .wamo_str <- function(rank, cat) {
    if (is.na(rank)) return("")
    if (is.na(cat %||% NA)) return(as.character(rank))
    paste0(rank, " (", wamo_short[cat] %||% cat, ")")
  }
  .one <- function(v) if (is.null(v) || length(v) == 0 || is.na(v)) "" else as.character(v)

  .col <- function(df, name, default = NA) {
    if (name %in% names(df)) df[[name]] else rep(default, nrow(df))
  }

  peers_disp <- data.frame(
    Rank          = peers$rank,
    School        = peers$instnm,
    Classification = .prettify_classification(.col(peers, "usnews_classification")),
    `USN Rank`    = ifelse(is.na(.col(peers, "usnews_rank")), "",
                            as.character(.col(peers, "usnews_rank"))),
    `WM Rank`     = mapply(.wamo_str,
                            .col(peers, "wamo_rank", NA),
                            .col(peers, "wamo_category", NA_character_)),
    `Forbes Rank` = ifelse(is.na(.col(peers, "forbes_rank")), "",
                            as.character(.col(peers, "forbes_rank"))),
    Sector        = .prettify_control(.col(peers, "control_grp")),
    State         = .col(peers, "stabbr"),
    Distance      = round(peers$distance, 3),
    check.names      = FALSE,
    stringsAsFactors = FALSE
  )

  if (!is.null(anchor_uid)) {
    a <- .SCHOOLS[.SCHOOLS$unitid == anchor_uid, , drop = FALSE]
    if (nrow(a) == 1) {
      anchor_row <- data.frame(
        Rank          = 0L,
        School        = paste0("★ ", a$instnm, "  (anchor)"),
        Classification = .prettify_classification(a$usnews_classification),
        `USN Rank`    = .one(a$usnews_rank),
        `WM Rank`     = .wamo_str(a$wamo_rank, a$wamo_category),
        `Forbes Rank` = .one(a$forbes_rank),
        Sector        = .prettify_control(a$control_grp),
        State         = .one(a$stabbr),
        Distance      = 0,
        check.names      = FALSE,
        stringsAsFactors = FALSE
      )
      peers_disp <- rbind(anchor_row, peers_disp)
    }
  }

  # ---- Sheet 2 — curated key variables ---------------------------------
  # Trimmed from the full ~85-column wide matrix down to the 20 most
  # frequently-asked-for metrics across every theme. Users who want the
  # full matrix can pull it via the Saved Searches bundle download.
  uids <- unique(c(anchor_uid, peers$unitid))
  wide <- .SCHOOLS_WIDE[.SCHOOLS_WIDE$unitid %in% uids, , drop = FALSE]
  rank_lookup <- c(setNames(0L, anchor_uid),
                   setNames(peers$rank, peers$unitid))
  wide$rank <- rank_lookup[as.character(wide$unitid)]
  wide <- wide[order(wide$rank), , drop = FALSE]

  # Front matter (rank, unitid, instnm) + the 20 curated metrics, in that
  # order. intersect() preserves the .KEY_VARS_20 ordering so the sheet
  # always reads in the theme-grouped sequence defined above.
  front <- c("rank", "unitid", "instnm")
  keep  <- c(intersect(front, names(wide)),
             intersect(.KEY_VARS_20, names(wide)))
  wide  <- wide[, keep, drop = FALSE]

  # ---- Sheet 3 — search summary (metadata) -------------------------------
  # Compact key/value block so users can reproduce the search later.
  meta <- peer_result$meta
  tw <- state$theme_weights %||% list()
  tw_str <- if (length(tw)) paste(sprintf("%s = %.2f", names(tw), unlist(tw)),
                                   collapse = "; ") else ""
  vw <- state$variable_weights %||% list()
  vw_str <- if (length(vw)) paste(sprintf("%s = %.2f", names(vw), unlist(vw)),
                                   collapse = "; ") else "(none)"
  summary_df <- data.frame(
    Field = c(
      "Anchor", "Anchor unitid", "Peers requested (K)", "Peers returned",
      "Distance metric", "Coverage threshold",
      "Candidate-pool size", "Candidate-pool filter",
      "Theme weights", "Variable overrides",
      "Generated"
    ),
    Value = c(
      meta$anchor_name %||% "",
      as.character(meta$anchor_unitid %||% ""),
      as.character(state$k %||% NA),
      as.character(nrow(peers)),
      meta$distance_metric %||% "weighted_euclidean",
      sprintf("%.0f%%", 100 * (meta$coverage_threshold %||% NA)),
      as.character(meta$candidate_pool_size %||% ""),
      .describe_pool_filter(state$candidate_pool),
      tw_str,
      vw_str,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    ),
    stringsAsFactors = FALSE
  )

  # ---- Build & save workbook ---------------------------------------------
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Peer list")
  openxlsx::addWorksheet(wb, "Key variables")
  openxlsx::addWorksheet(wb, "Search summary")

  openxlsx::writeData(wb, "Peer list",       peers_disp)
  openxlsx::writeData(wb, "Key variables",   wide)
  openxlsx::writeData(wb, "Search summary",  summary_df)

  hdr_style <- openxlsx::createStyle(textDecoration = "bold",
                                     halign = "left",
                                     fgFill = "#F4EDEC")
  openxlsx::addStyle(wb, "Peer list",       hdr_style,
                     rows = 1, cols = seq_len(ncol(peers_disp)))
  openxlsx::addStyle(wb, "Key variables",   hdr_style,
                     rows = 1, cols = seq_len(ncol(wide)))
  openxlsx::addStyle(wb, "Search summary",  hdr_style,
                     rows = 1, cols = seq_len(ncol(summary_df)))

  openxlsx::freezePane(wb, "Peer list",      firstRow = TRUE)
  openxlsx::freezePane(wb, "Key variables",  firstRow = TRUE,
                       firstActiveCol = min(4, ncol(wide)))
  openxlsx::setColWidths(wb, "Peer list",
                         cols = seq_len(ncol(peers_disp)), widths = "auto")
  openxlsx::setColWidths(wb, "Key variables",
                         cols = seq_len(ncol(wide)), widths = "auto")
  openxlsx::setColWidths(wb, "Search summary",
                         cols = 1:2, widths = c(28, 70))

  openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
  invisible(out_path)
}

# -----------------------------------------------------------------------------
# PDF
# -----------------------------------------------------------------------------
# We delegate the heavy lifting to an rmarkdown template that reads
# peer_result + state from its render envir. The template uses tinytex
# (already installed); the first PDF render in a fresh tinytex install
# auto-fetches the small set of LaTeX packages it needs (booktabs,
# tabularnewline, etc.) — that one-time fetch can take 30-60s but is
# silent on subsequent runs.
build_peer_pdf <- function(peer_result, state, out_path) {
  if (is.null(peer_result) || is.null(peer_result$peers))
    stop("build_peer_pdf: peer_result is missing.")

  tpl_src <- file.path(.PROJECT_ROOT, "shiny_app", "templates",
                       "peer_report.Rmd")
  if (!file.exists(tpl_src))
    stop("build_peer_pdf: template not found at ", tpl_src)

  tmp <- tempfile("peer_pdf_")
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  tpl_tmp <- file.path(tmp, "peer_report.Rmd")
  file.copy(tpl_src, tpl_tmp, overwrite = TRUE)

  render_env <- new.env(parent = globalenv())
  render_env$peer_result <- peer_result
  render_env$state       <- state
  # Make the helpers the template needs available in the render env.
  render_env$.SCHOOLS <- .SCHOOLS
  # .SCHOOLS_WIDE feeds the new "Distribution of key indicators"
  # density-plot section — Rmd reads pool values for each metric from
  # this and overlays the anchor + peer-median lines.
  render_env$.SCHOOLS_WIDE <- .SCHOOLS_WIDE
  render_env$.PDF_DENSITY_VARS <- .PDF_DENSITY_VARS
  render_env$.prettify_classification <- .prettify_classification
  render_env$.prettify_control        <- .prettify_control
  render_env$.describe_pool_filter    <- .describe_pool_filter
  # .theme_label maps internal theme keys (e.g. "student_body") to
  # display labels ("Student body") for the search-summary block. Only
  # exists when global.R has been sourced; the Rmd has a title-case
  # fallback if it's missing.
  if (exists(".theme_label", mode = "function"))
    render_env$.theme_label <- .theme_label

  rmarkdown::render(
    input             = tpl_tmp,
    output_file       = "peer_report.pdf",
    output_dir        = tmp,
    intermediates_dir = tmp,
    envir             = render_env,
    quiet             = TRUE
  )

  pdf_path <- file.path(tmp, "peer_report.pdf")
  if (!file.exists(pdf_path))
    stop("build_peer_pdf: render produced no PDF.")
  file.copy(pdf_path, out_path, overwrite = TRUE)
  invisible(out_path)
}
