# Presence of this file (in the app's R/ directory) tells Shiny NOT to
# auto-source the R/ directory at app startup. Shiny looks for it HERE, in
# R/ — NOT at the app root (see shiny:::loadSupport: the disable check is
# `list.files(file.path(appDir, "R"), pattern = "^_disable_autoload\\.r$")`).
# A copy placed at the app root is silently ignored.
#
# Why it matters: for app.R apps, Shiny calls loadSupport(globalrenv = NULL),
# which auto-sources R/*.R BEFORE global.R has run. Any R/ file that
# references constants defined in global.R (e.g. .THEMES, .VARIABLES,
# .SCHOOLS_WIDE) or functions sourced by it (e.g. .load_wide_facts via
# peer_pipeline.R) then fails with "object not found".
#
# global.R explicitly sources R/*.R at the end of its execution, in the
# correct order, so disabling auto-load is the right call here.
