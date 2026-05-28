# =============================================================================
# Saved Searches tab.
#
# Inputs from app.R:
#   saved_searches  reactiveVal holding a named list of saved-search records.
#                   Each record is a list with:
#                     - id              unique key (also used as map key)
#                     - label           user-visible name
#                     - saved_at        POSIXct
#                     - sidebar_state   isolated snapshot of sidebar settings
#                     - peer_result     the compute_peers() return value
#                                       (with $pool_unitids and $pool_filter)
#
#   restore_signal  reactiveVal that the sidebar module observes to restore
#                   a previously-saved sidebar_state. Setting this with a
#                   saved record's sidebar_state hydrates the sidebar.
#
# UI features:
#   - Empty state when nothing is saved yet
#   - One card per saved search, newest first
#   - Per-card actions: View, Rename, Delete, Download (zip)
#   - Notifications confirming each action
# =============================================================================

# -----------------------------------------------------------------------------
# Generate an auto-label from a peer_result + sidebar state. Output looks
# like "Holy Cross | Ranked + Nat. LACs + Catholic | outcomes x 2.0".
# -----------------------------------------------------------------------------
.auto_label <- function(peer_result, state) {
  anchor_name <- peer_result$meta$anchor_name %||% "Anchor"

  pool_compact <- .describe_pool_filter_compact(state$candidate_pool)

  weights     <- state$theme_weights %||% list()
  emphasized  <- names(weights)[
    !vapply(weights, function(w) isTRUE(all.equal(w, 1.0)), logical(1))
  ]
  weight_part <- if (length(emphasized)) {
    paste(vapply(emphasized, function(t)
      sprintf("%s x %.1f", t, weights[[t]]), character(1)),
      collapse = ", ")
  } else {
    "balanced"
  }

  sprintf("%s | %s | %s", anchor_name, pool_compact, weight_part)
}

# Compact one-liner of the candidate-pool filter (the full version lives in
# helpers_format.R as .describe_pool_filter; this one is short enough for a
# card title).
.describe_pool_filter_compact <- function(filter_list) {
  if (is.null(filter_list) || !length(filter_list)) return("All schools")
  parts <- character(0)
  if (isTRUE(filter_list$in_ranked_universe)) parts <- c(parts, "Ranked")

  if (!is.null(filter_list$usnews_classification)) {
    vals <- filter_list$usnews_classification
    parts <- c(parts, if (length(vals) == 1) {
      switch(vals,
             "national-liberal-arts-colleges" = "Nat. LACs",
             "national-universities"          = "Nat. Univ.",
             vals)
    } else sprintf("%d classes", length(vals)))
  }
  if (!is.null(filter_list$control_grp)) {
    vals <- filter_list$control_grp
    parts <- c(parts, if (length(vals) == 1) {
      switch(vals, "public" = "Public", "private_nfp" = "Private", vals)
    } else "Mixed sectors")
  }
  if (!is.null(filter_list$stabbr)) {
    parts <- c(parts, sprintf("%d states", length(filter_list$stabbr)))
  }
  if (!is.null(filter_list$religious_tradition)) {
    vals <- filter_list$religious_tradition
    parts <- c(parts, if (length(vals) == 1) vals
                       else sprintf("%d traditions", length(vals)))
  }
  paste(parts, collapse = " + ")
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
sessionUI <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Saved Searches"),
    p(class = "section-intro",
      "Searches you've saved with the ", tags$em("Save this search"),
      " button live here. Each entry can be reloaded into the sidebar, ",
      "renamed, downloaded as a zip bundle, or deleted. Saved searches ",
      "live in this session only; closing the browser clears them."),
    uiOutput(ns("saved_list"))
  )
}

# -----------------------------------------------------------------------------
# Per-card builder. Each action button uses a delegated onclick that posts
# {action, id, t} to a single namespaced input ("action"), letting one
# observer handle View / Rename / Delete uniformly. Download is a separate
# downloadButton bound to a per-search dynamic output id.
# -----------------------------------------------------------------------------
.saved_search_card <- function(s, ns) {
  action_btn <- function(action, label, btn_class = "btn-outline-secondary") {
    js <- sprintf(
      "Shiny.setInputValue('%s', {action: '%s', id: '%s', t: Date.now()}, {priority: 'event'}); return false;",
      ns("action"), action, s$id
    )
    tags$button(class = paste("btn btn-sm", btn_class),
                onclick = js, label)
  }

  n_peers <- nrow(s$peer_result$peers)
  weights <- s$sidebar_state$theme_weights %||% list()
  weight_summary <- {
    emph <- names(weights)[
      !vapply(weights, function(w) isTRUE(all.equal(w, 1.0)), logical(1))
    ]
    if (length(emph))
      paste(vapply(emph, function(t)
        sprintf("%s x %.1f", t, weights[[t]]), character(1)),
        collapse = ", ")
    else "balanced (all 1.0)"
  }

  div(class = "saved-search-card",
    div(class = "ssc-header",
      div(class = "ssc-label", s$label),
      div(class = "ssc-meta",
          tags$span(format(s$saved_at, "%b %d, %Y %H:%M")),
          tags$span(class = "ssc-sep", " | "),
          tags$span(sprintf("%d peers returned", n_peers)),
          tags$span(class = "ssc-sep", " | "),
          tags$span(sprintf("anchor: %s",
                            s$peer_result$meta$anchor_name)))
    ),
    div(class = "ssc-body",
      div(class = "ssc-row",
          tags$span(class = "ssc-label-tag", "Pool:"),
          tags$span(.describe_pool_filter(s$sidebar_state$candidate_pool))),
      div(class = "ssc-row",
          tags$span(class = "ssc-label-tag", "Themes:"),
          tags$span(weight_summary)),
      div(class = "ssc-row",
          tags$span(class = "ssc-label-tag", "Distance:"),
          tags$span(switch(s$sidebar_state$distance_metric,
                           euclidean   = "Euclidean",
                           mahalanobis = "Mahalanobis",
                           s$sidebar_state$distance_metric)))
    ),
    div(class = "ssc-actions",
      action_btn("view",   "View",   "btn-primary"),
      action_btn("rename", "Rename"),
      downloadButton(ns(paste0("download_", s$id)),
                     "Download",
                     class = "btn-sm btn-outline-secondary"),
      action_btn("delete", "Delete", "btn-outline-danger")
    )
  )
}

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
sessionServer <- function(id, saved_searches, restore_signal = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Render the list (newest first) ----
    output$saved_list <- renderUI({
      searches <- saved_searches()
      if (!length(searches)) {
        return(div(class = "note-box",
                   tags$strong("No saved searches yet. "),
                   "Run a search on the ", tags$em("Peer Search"), " tab and ",
                   "click ", tags$em("Save this search"), " in the sidebar."))
      }
      # Sort by saved_at descending so newest cards come first
      ord <- order(vapply(searches, function(s) as.numeric(s$saved_at),
                          numeric(1)),
                    decreasing = TRUE)
      tagList(lapply(searches[ord], function(s) .saved_search_card(s, ns)))
    })

    # ---- Generic action dispatcher (View / Delete / Rename) ----
    observeEvent(input$action, {
      payload <- input$action
      if (is.null(payload) || is.null(payload$action) || is.null(payload$id))
        return()
      sid <- payload$id
      searches <- saved_searches()
      if (!sid %in% names(searches)) return()
      s <- searches[[sid]]

      switch(payload$action,
        view = {
          if (!is.null(restore_signal)) {
            # Stamp the snapshot with a fresh timestamp so the sidebar's
            # observe fires even if the same state is restored twice.
            restore_signal(c(s$sidebar_state,
                             list(.restore_stamp = Sys.time())))
            showNotification(sprintf("Loaded: %s", s$label),
                             type = "default", duration = 4)
          }
        },
        rename = {
          showModal(modalDialog(
            title = "Rename saved search",
            size  = "m",
            easyClose = TRUE,
            textInput(ns("rename_text"),
                      label = "New label",
                      value = s$label, width = "100%"),
            footer = tagList(
              modalButton("Cancel"),
              tags$button(class = "btn btn-primary",
                onclick = sprintf(
                  "Shiny.setInputValue('%s', {id: '%s', t: Date.now()}, {priority: 'event'}); return false;",
                  ns("apply_rename"), sid),
                "Save")
            )
          ))
        },
        delete = {
          searches[[sid]] <- NULL
          saved_searches(searches)
          showNotification(sprintf("Deleted: %s", s$label),
                           type = "default", duration = 4)
        }
      )
    })

    # ---- Apply rename when the modal Save button is clicked ----
    observeEvent(input$apply_rename, {
      payload <- input$apply_rename
      if (is.null(payload) || is.null(payload$id)) return()
      sid <- payload$id
      searches <- saved_searches()
      if (!sid %in% names(searches)) return()
      new_label <- isolate(input$rename_text)
      if (is.null(new_label) || !nzchar(trimws(new_label))) {
        showNotification("Label cannot be empty", type = "warning")
        return()
      }
      searches[[sid]]$label <- trimws(new_label)
      saved_searches(searches)
      removeModal()
      showNotification("Renamed", type = "default", duration = 3)
    })

    # ---- Dynamic download handlers (one per saved search) ----
    # Re-registered whenever the saved-searches list changes. Shiny's
    # output registry tolerates re-assignment, so newer registrations
    # silently replace older ones.
    observe({
      searches <- saved_searches()
      for (sid in names(searches)) {
        local({
          .sid <- sid
          output[[paste0("download_", .sid)]] <- downloadHandler(
            filename = function() {
              s <- saved_searches()[[.sid]]
              if (is.null(s)) return(sprintf("peer_search_%s.zip", .sid))
              safe_label <- gsub("[^A-Za-z0-9]+", "_", s$label)
              safe_label <- substr(safe_label, 1, 60)
              sprintf("peer_search_%s_%s.zip",
                      safe_label,
                      format(s$saved_at, "%Y%m%d_%H%M%S"))
            },
            content = function(file) {
              s <- saved_searches()[[.sid]]
              if (is.null(s)) {
                writeLines("This search no longer exists.", file)
                return()
              }
              bundle_download(s, file)
            },
            contentType = "application/zip"
          )
        })
      }
    })
  })
}
