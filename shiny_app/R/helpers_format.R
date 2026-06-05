# =============================================================================
# Display formatters shared by multiple modules (sidebar, peer table,
# side-by-side). Functions are pure: input is a vector of raw codes from
# schools.csv, output is a vector of pretty display labels of the same
# length, NAs preserved.
# =============================================================================

# Convert usnews_classification raw codes like
# "regional-universities-north" to "Regional Universities (North)". When
# the trailing token is a region keyword (north/south/east/west/midwest),
# wrap it in parentheses; otherwise just title-case all tokens.
.prettify_classification <- function(codes) {
  region_kw <- c("north", "south", "east", "west", "midwest")
  vapply(codes, function(code) {
    if (is.na(code)) return(NA_character_)
    parts <- strsplit(code, "-", fixed = TRUE)[[1]]
    if (length(parts) >= 3 && tolower(parts[length(parts)]) %in% region_kw) {
      region <- stringr::str_to_title(parts[length(parts)])
      body   <- paste(stringr::str_to_title(parts[-length(parts)]),
                      collapse = " ")
      sprintf("%s (%s)", body, region)
    } else {
      paste(stringr::str_to_title(parts), collapse = " ")
    }
  }, character(1))
}

# control_grp raw codes → display labels. Unknown codes pass through.
.prettify_control <- function(codes) {
  map <- c("public" = "Public", "private_nfp" = "Private (nonprofit)")
  unname(ifelse(is.na(codes), NA_character_,
                ifelse(codes %in% names(map), map[codes], codes)))
}

# stabbr → full state name (US states, DC, territories). Unknown abbrs
# pass through unchanged.
.STATE_NAMES <- c(
  setNames(state.name, state.abb),
  "DC" = "District of Columbia",
  "AS" = "American Samoa",
  "GU" = "Guam",
  "MP" = "Northern Mariana Islands",
  "PR" = "Puerto Rico",
  "VI" = "U.S. Virgin Islands",
  "FM" = "Federated States of Micronesia",
  "PW" = "Palau",
  "MH" = "Marshall Islands"
)

.prettify_state <- function(abbrs) {
  unname(ifelse(is.na(abbrs), NA_character_,
                ifelse(abbrs %in% names(.STATE_NAMES),
                       .STATE_NAMES[abbrs], abbrs)))
}

# -----------------------------------------------------------------------------
# Comparable-distance metrics derived from compute_peers()'s pool_distances.
# Each peer-result row has a raw `distance`; these helpers wrap that with
# two cross-pool-comparable readings:
#
#   relative_distance  d / median(pool_distances)
#       A value of 0.30 means the peer is roughly 30% as far away from
#       the anchor as a typical pair in the pool is. Comparable across
#       pools because it normalizes by each pool's internal spread.
#
#   percentile_rank    100 * mean(pool_distances >= d)
#       The closest peer is in (close to) the 100th percentile. Comparable
#       across pools because it's a rank statistic, not a magnitude.
# -----------------------------------------------------------------------------
.compute_relative_distance <- function(distance, pool_median) {
  if (is.null(pool_median) || !is.finite(pool_median) || pool_median <= 0)
    return(NA_real_)
  distance / pool_median
}

.compute_percentile_rank <- function(distance, pool_distances) {
  if (is.null(pool_distances) || !length(pool_distances) ||
      !is.finite(distance)) return(NA_real_)
  100 * mean(pool_distances >= distance, na.rm = TRUE)
}

# -----------------------------------------------------------------------------
# Render a candidate-pool filter dict into a human-readable description.
# Used by the Side-by-Side distribution modal so users know which set of
# institutions is being plotted.
# -----------------------------------------------------------------------------
.describe_pool_filter <- function(filter_list) {
  if (is.null(filter_list) || !length(filter_list)) {
    return("entire universe (no filters applied)")
  }
  pretty <- list()
  if (isTRUE(filter_list$in_ranked_universe))
    pretty[["Universe"]] <- "Ranked universe"

  if (!is.null(filter_list$usnews_classification)) {
    pretty[["Classification"]] <- paste(
      .prettify_classification(filter_list$usnews_classification),
      collapse = ", ")
  }
  if (!is.null(filter_list$control_grp)) {
    pretty[["Sector"]] <- paste(
      .prettify_control(filter_list$control_grp), collapse = ", ")
  }
  if (!is.null(filter_list$stabbr)) {
    vals <- filter_list$stabbr
    pretty[["State"]] <- if (length(vals) > 8) sprintf("%d states", length(vals))
                          else paste(vals, collapse = ", ")
  }
  if (!is.null(filter_list$religious_tradition)) {
    pretty[["Religious tradition"]] <- paste(filter_list$religious_tradition,
                                              collapse = ", ")
  }
  paste(sprintf("%s: %s", names(pretty), unlist(pretty)), collapse = " · ")
}

# -----------------------------------------------------------------------------
# Value formatters for side-by-side display. The `format` argument matches
# the format column in *_variables.csv: currency, percentage, count, ratio.
# Anything else (or NA) falls back to general numeric formatting.
# -----------------------------------------------------------------------------
.NA_PLACEHOLDER <- "(n/a)"

# Treat NULL, zero-length, NaN, and NA all as "missing" so callers never
# have to think about which kind of missingness they're holding.
.is_missing_scalar <- function(x) {
  is.null(x) || length(x) != 1 || !is.finite(x)
}

.format_value <- function(value, format = NA_character_) {
  if (.is_missing_scalar(value)) return(.NA_PLACEHOLDER)
  if (is.na(format))
    return(formatC(value, format = "g", digits = 4))
  switch(
    as.character(format),
    currency   = sprintf("$%s", formatC(round(value), format = "d", big.mark = ",")),
    percentage = sprintf("%.1f%%", value),
    count      = formatC(round(value), format = "d", big.mark = ","),
    ratio      = sprintf("%.2f", value),
    formatC(value, format = "g", digits = 4)
  )
}

# Signed difference (peer minus anchor) rendered in the same units as the
# underlying values. Returns plain text; HTML coloring is left to CSS.
.format_diff <- function(peer_value, anchor_value, format = NA_character_) {
  if (.is_missing_scalar(peer_value) || .is_missing_scalar(anchor_value))
    return(.NA_PLACEHOLDER)
  diff <- peer_value - anchor_value
  sign_prefix <- if (diff > 0) "+" else if (diff < 0) "" else "±"
  switch(
    as.character(format),
    currency   = sprintf("%s$%s", sign_prefix,
                         formatC(abs(round(diff)), format = "d", big.mark = ",")),
    percentage = sprintf("%s%.1f pp", sign_prefix, diff),  # percentage points
    count      = sprintf("%s%s", sign_prefix,
                         formatC(round(diff), format = "d", big.mark = ",")),
    ratio      = sprintf("%s%.2f", sign_prefix, diff),
    sprintf("%s%s", sign_prefix, formatC(diff, format = "g", digits = 4))
  )
}

# -----------------------------------------------------------------------------
# Distribution-bar SVG. Shows where the anchor and peer sit within the
# pool's 5th-95th percentile range, with vertical tick marks at Q1,
# median, and Q3 to convey the spread of the bulk. Hovering surfaces a
# native browser tooltip with raw pool stats plus anchor/peer values
# and their percentiles. Anchor is brand purple, peer is taupe.
# -----------------------------------------------------------------------------
.compare_distribution_svg <- function(pool_values, anchor_value, peer_value,
                                       width = 140, height = 16,
                                       fmt = NA_character_) {
  pool_values <- pool_values[is.finite(pool_values)]
  if (length(pool_values) < 5) {
    return(HTML('<span class="dist-empty">(insufficient pool data)</span>'))
  }
  qs <- stats::quantile(pool_values, c(0.05, 0.25, 0.5, 0.75, 0.95),
                        na.rm = TRUE, names = FALSE)
  lo <- qs[1]; q1 <- qs[2]; md <- qs[3]; q3 <- qs[4]; hi <- qs[5]
  if (!is.finite(lo) || !is.finite(hi) || hi <= lo) {
    return(HTML('<span class="dist-empty">(no variation)</span>'))
  }

  # Reserve marker-radius worth of padding on each side so dots at the
  # 5th- or 95th-percentile extremes (or beyond, when clamped) stay
  # fully visible inside the SVG instead of being clipped at the edge.
  marker_r <- 4
  margin   <- marker_r + 1
  pos <- function(v) {
    if (is.null(v) || length(v) != 1 || !is.finite(v)) return(NA_real_)
    pmax(0, pmin(1, (v - lo) / (hi - lo))) * (width - 2 * margin) + margin
  }
  ax  <- pos(anchor_value); px  <- pos(peer_value)
  q1x <- pos(q1);           q3x <- pos(q3)
  mdx <- pos(md)

  tick <- function(x, y1, y2, stroke, sw = 1) {
    if (is.na(x)) return("")
    sprintf('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="%.1f"/>',
            x, y1, x, y2, stroke, sw)
  }
  marker <- function(x, fill, r = marker_r) {
    if (is.na(x)) return("")
    sprintf('<circle cx="%.1f" cy="%d" r="%d" fill="%s" stroke="#FFFFFF" stroke-width="0.75"/>',
            x, height %/% 2, r, fill)
  }

  # Native SVG <title> renders as a hover tooltip; newlines are honored
  # by most modern browsers, so a multi-line tooltip works inline.
  pct_for <- function(v) {
    if (is.null(v) || length(v) != 1 || !is.finite(v)) return(NA_real_)
    100 * mean(pool_values < v, na.rm = TRUE)
  }
  fv <- function(v) .format_value(v, fmt)
  ap <- pct_for(anchor_value); pp <- pct_for(peer_value)
  tooltip <- sprintf(
    paste0(
      "Pool (n=%d):\\n",
      "  min=%s, Q1=%s, median=%s, Q3=%s, max=%s\\n",
      "Anchor: %s%s\\n",
      "Peer:   %s%s"
    ),
    length(pool_values),
    fv(min(pool_values)), fv(q1), fv(md), fv(q3), fv(max(pool_values)),
    fv(anchor_value),
    if (is.na(ap)) "" else sprintf(" (%.0fth percentile)", ap),
    fv(peer_value),
    if (is.na(pp)) "" else sprintf(" (%.0fth percentile)", pp)
  )
  tooltip <- gsub("\\\\n", "\n", tooltip, fixed = TRUE)

  HTML(sprintf(
    paste0(
      '<svg width="%d" height="%d" class="dist-bar" ',
      'xmlns="http://www.w3.org/2000/svg" aria-label="distribution bar">',
      '<title>%s</title>',
      '<rect x="0" y="%d" width="%d" height="4" fill="#F4EDEC" rx="2"/>',
      '%s%s%s',          # Q1, Q3 (thin), median (taller, darker)
      '%s%s',             # anchor, peer
      '</svg>'
    ),
    width, height,
    htmltools::htmlEscape(tooltip),
    height %/% 2 - 2, width,
    tick(q1x, 4, height - 4, "#AC9E94", 1),
    tick(q3x, 4, height - 4, "#AC9E94", 1),
    tick(mdx, 2, height - 2, "#251230", 1.5),
    marker(ax, "#602D89", 4),
    marker(px, "#AC9E94", 4)
  ))
}
