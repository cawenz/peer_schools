# =============================================================================
# Cohc-branded plotly theme helpers
#
# Shared styling for every plotly chart in the app. Keeps fonts, hover
# labels, mode bar, and color choices consistent across:
#   - Side-by-Side distribution modal
#   - Cohort variable inspector
#   - Trends multi-year ribbon chart
#   - Trends single-year boxplot
#
# Usage pattern in any module:
#   plot_ly() %>% add_*(...) %>% cohc_plotly_theme() %>% cohc_modebar()
#
# Individual axis configuration still happens per-plot, since y-axes
# differ (log vs linear, percentage vs currency, etc.). The theme covers
# everything ELSE: font, hover style, plot background, default margins.
# =============================================================================

# Common font (matches the bslib body font for the rest of the app).
.COHC_FONT <- list(
  family = "'Manrope', 'Helvetica Neue', Arial, sans-serif",
  size   = 13,
  color  = "#251230"
)

# Dark slate hover label with crisp white text. Plotly's default colors
# hover labels by trace, which gives white-on-light-purple etc. — the
# branded version is always dark + white so contrast is consistent.
.COHC_HOVERLABEL <- list(
  bgcolor     = "#251230",
  bordercolor = "#251230",
  font        = list(
    family = "'Manrope', 'Helvetica Neue', Arial, sans-serif",
    color  = "#FFFFFF",
    size   = 12
  ),
  align       = "left"
)

# Default chart margins (single source of truth).
.COHC_MARGIN <- list(t = 20, r = 30, b = 100, l = 80)

# Default centered legend below the chart.
.COHC_LEGEND <- list(
  orientation = "h",
  x = 0.5, xanchor = "center",
  y = -0.22, yanchor = "top",
  bgcolor     = "rgba(255, 255, 255, 0.85)",
  bordercolor = "rgba(0, 0, 0, 0)",
  font        = list(family = "'Manrope', sans-serif", size = 12)
)

#' Apply cohc-branded styling to a plotly chart.
#'
#' Sets font, hover label, plot/paper backgrounds, margins, and legend.
#' Pass `hovermode = "x unified"` for line/ribbon time-series so the
#' hovering tooltip shows every trace's value at a single x-position
#' (much cleaner than plotly's default "closest" mode for those charts).
#'
#' @param p A plotly object.
#' @param hovermode "closest" (default), "x unified", "x", or "y".
#' @param ... Extra layout arguments forwarded to plotly::layout().
cohc_plotly_theme <- function(p, hovermode = "closest", ...) {
  plotly::layout(
    p,
    font          = .COHC_FONT,
    hoverlabel    = .COHC_HOVERLABEL,
    plot_bgcolor  = "#FFFFFF",
    paper_bgcolor = "#FFFFFF",
    margin        = .COHC_MARGIN,
    legend        = .COHC_LEGEND,
    hovermode     = hovermode,
    ...
  )
}

#' Trim the plotly mode bar to the essentials.
#'
#' Hides the mode bar until the user hovers (so it doesn't clutter the
#' chart), removes the lasso / select / pan / zoom-in-out controls
#' (rarely useful for these read-only charts), and customizes the
#' download-as-PNG button to ship a high-res file with a sensible name.
cohc_modebar <- function(p, filename_root = "peer_schools_chart") {
  plotly::config(
    p,
    displayModeBar = "hover",
    displaylogo    = FALSE,
    modeBarButtonsToRemove = c(
      "lasso2d", "select2d", "autoScale2d",
      "zoomIn2d", "zoomOut2d", "pan2d",
      "hoverCompareCartesian", "hoverClosestCartesian",
      "toggleSpikelines"
    ),
    toImageButtonOptions = list(
      filename = filename_root,
      format   = "png",
      width    = 1000,
      height   = 600,
      scale    = 2
    )
  )
}

#' Build a clean hovertemplate fragment for a value formatted in our
#' standard units. Returns the plotly hovertemplate token for the y
#' axis (use %{x} for x, %{y} for y by default).
#'
#' @param fmt One of the .VARIABLES$format values: currency, percentage,
#'   count, ratio, score. Anything else falls back to a 4-sig-fig number.
#' @param axis Which axis the value is on ("y" or "x").
cohc_value_token <- function(fmt, axis = "y") {
  ax <- sprintf("%%{%s", axis)
  ax_close <- "}"
  switch(
    as.character(fmt) %||% "",
    currency   = sprintf("$%s:,.0f%s", ax, ax_close),
    # sprintf %% -> literal %; produces "%{y:.1f}%" in the plotly token.
    # plotly hovertemplate is NOT d3-escaped — `%%` would render two
    # literal percent signs, not one. Single % is correct.
    percentage = sprintf("%s:.1f%s%%", ax, ax_close),
    count      = sprintf("%s:,.0f%s", ax, ax_close),
    ratio      = sprintf("%s:.2f%s", ax, ax_close),
    score      = sprintf("%s:,.0f%s", ax, ax_close),
    sprintf("%s:.4g%s", ax, ax_close)
  )
}
