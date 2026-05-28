# cohc_bslib.R — Holy Cross bslib theme function for the Peer Schools app.
#
# Brand palette:
#   #602D89  primary purple
#   #251230  dark
#   #F4EDEC  light beige
#   #AC9E94  taupe / secondary
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
    primary   = "#602D89",
    secondary = "#AC9E94",
    success   = "#602D89",
    info      = "#602D89",
    warning   = "#AC9E94",
    danger    = "#602D89",
    light     = "#F4EDEC",
    dark      = "#251230",

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
