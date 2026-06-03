# cohc_bslib.R — Holy Cross bslib theme function for the Peer Schools app.
#
# Brand palette:
#   #1d3557  primary purple
#   #0d1b2a  dark
#   #e2e8f0  light beige
#   #94a3b8  taupe / secondary
#   #FFFFFF  white
#   #000000  black
#
# Fonts: Manrope (body), Gelasio (headings), JetBrains Mono (code).
#
# Usage in app.R:
#   source("R/cohc_bslib.R")   # sourced via global.R already
#   page_sidebar(theme = cohc_bslib(), ...)

suppressMessages({
  library(bslib); library(sass)
})

cohc_bslib <- function(scss_path = "www/cohc_styles.scss") {
  theme <- bs_theme(
    version = 5,

    # Primary palette
    primary   = "#1d3557",
    secondary = "#94a3b8",
    success   = "#1d3557",
    info      = "#1d3557",
    warning   = "#94a3b8",
    danger    = "#1d3557",
    light     = "#e2e8f0",
    dark      = "#0d1b2a",

    bg = "#FFFFFF",
    fg = "#000000",

    base_font    = font_google("Manrope"),
    heading_font = font_google("Gelasio", wght = c(400, 500, 600, 700)),
    code_font    = font_google("JetBrains Mono")
  )

  if (file.exists(scss_path)) {
    theme <- bs_add_rules(theme, sass::sass_file(scss_path))
  }
  theme
}
