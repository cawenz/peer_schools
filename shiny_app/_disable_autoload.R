# Presence of this file tells Shiny NOT to auto-source the R/ directory
# at app startup. Without it, R/*.R files are loaded before global.R,
# and any file that references constants defined in global.R (e.g.,
# .THEMES, .VARIABLES, .SCHOOLS_WIDE) fails with "object not found".
#
# global.R explicitly sources R/*.R at the end of its execution, in the
# correct order, so disabling auto-load is the right call here.
