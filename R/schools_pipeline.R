# =============================================================================
# Shared Schools Pipeline   (repo version)
# Holy Cross peer-comparison project
#
# REPO LAYOUT ASSUMPTION
#   This script expects to be sourced from the repo root, with:
#     data/IPEDS{year-range}.Rda          IPEDS collection bundles
#     data/2025-Public-Data-File.xlsx     Carnegie 2025 public data file
#     output/                              destination for produced CSVs
#
# Loads IPEDS collections directly via load() rather than ipeds::load_ipeds()
# so the repo is portable across machines without needing the ipeds package
# to be configured to find a specific download directory.
#
# OUTPUTS  (written to output/)
#   schools.csv       one row per institution; institutional attributes,
#                     classifications (IPEDS + US News + Carnegie), value
#                     labels for coded fields.
#   value_labels.csv  canonical (table_name, variable, code) -> label table.
#
# REQUIRED PACKAGES
#   install.packages(c("dplyr","tidyr","purrr","stringr","httr2","jsonlite","readxl"))
#   (the ipeds package is NO LONGER required for this pipeline)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr)
  library(httr2); library(jsonlite); library(readxl)
})

# ---- repo paths (resolve relative to wherever this is sourced from) -------
.repo_root  <- function() getwd()
.data_path  <- function(...) file.path(.repo_root(), "data", ...)
.out_path   <- function(...) file.path(.repo_root(), "output", ...)
dir.create(.out_path(), showWarnings = FALSE, recursive = TRUE)

# ---- CONFIG ---------------------------------------------------------------
SCHOOLS_CONFIG <- list(
  collection_years = 2020:2024,
  keep_sectors     = c(1, 2),
  ai_base    = "https://ai.usnews.com/api/v1/client_api",
  ai_dataset = "undergraduate",
  ai_key     = Sys.getenv("ACADEMIC_INSIGHTS_API_KEY"),
  scorecard_key = Sys.getenv("SCORECARD_API_KEY"),
  ranked_classes = c("national-universities", "national-liberal-arts-colleges"),
  labels_year = 2024,
  carnegie_file = .data_path("2025-Public-Data-File.xlsx"),
  # US News overall (within-category) rank — Academic Insights metric_id 24
  # ("Overall Rank"). Confirmed via
  #   search_ai_metrics(SCHOOLS_CONFIG, contains = "rank")
  # Pulled for the latest AI-equivalent year. Rank is a per-institution
  # snapshot, not a longitudinal facts series, so we keep only the latest
  # year and store as usnews_rank.
  usnews_rank_metric_id = 24L,
  labeled_fields = c(
    "sector", "control", "iclevel",
    "hbcu", "hospital", "medical", "tribal",
    "instcat", "locale", "instsize",
    "basic2021", "setting2025", "highest_degree_2025",
    "ic2025size", "ic2025alf", "apm", "gpm"
  )
)

# =============================================================================
# 1. IPEDS retrieval helpers - direct .Rda load, no ipeds package required
# =============================================================================
.IPEDS_CACHE <- if (exists(".IPEDS_CACHE")) .IPEDS_CACHE else new.env()

# IPEDS .Rda files are named IPEDS{prev_year}-{yy}.Rda for a collection year.
# load_ipeds(Y+1) returns the collection-year-Y tables. So the file holding
# collection year 2023 is IPEDS2023-24.Rda; collection year 2024 -> IPEDS2024-25.Rda.
.rda_path_for_collection <- function(collection_year) {
  yy <- sprintf("%02d", (collection_year + 1) %% 100)
  .data_path(sprintf("IPEDS%d-%s.Rda", collection_year, yy))
}

load_collection <- function(collection_year) {
  key <- as.character(collection_year)
  if (is.null(.IPEDS_CACHE[[key]])) {
    rda <- .rda_path_for_collection(collection_year)
    if (!file.exists(rda)) {
      warning(sprintf("Missing IPEDS file for collection %d: %s",
                      collection_year, rda))
      .IPEDS_CACHE[[key]] <- NULL
    } else {
      message(sprintf("  load(%s)  ->  collection year %d",
                      basename(rda), collection_year))
      env <- new.env()
      load(rda, envir = env)
      # the package convention is that the loaded object is named `db`
      if (!"db" %in% ls(env)) {
        warning(sprintf("Expected object 'db' in %s, found: %s",
                        rda, paste(ls(env), collapse = ", ")))
        .IPEDS_CACHE[[key]] <- NULL
      } else {
        .IPEDS_CACHE[[key]] <- env$db
      }
    }
  }
  .IPEDS_CACHE[[key]]
}

# Generic table fetch (used for valueSets, varTable, etc.)
get_raw_table <- function(collection_year, table_name) {
  lst <- load_collection(collection_year)
  if (is.null(lst)) return(NULL)
  hit <- names(lst)[toupper(names(lst)) == toupper(table_name)]
  if (!length(hit)) return(NULL)
  as_tibble(lst[[hit[1]]])
}

# Table fetch with UNITID normalisation (used by module pipelines)
get_table <- function(collection_year, table_name) {
  df <- get_raw_table(collection_year, table_name)
  if (is.null(df)) return(NULL)
  names(df) <- toupper(gsub("[.]", "_", names(df)))
  if (!"UNITID" %in% names(df)) return(NULL)
  df %>% rename(unitid = UNITID) %>% mutate(unitid = as.integer(unitid))
}

# =============================================================================
# 2. Academic Insights helper
# =============================================================================
ai_get <- function(cfg, path, query = list()) {
  if (cfg$ai_key == "") stop("ACADEMIC_INSIGHTS_API_KEY not set.")
  request(cfg$ai_base) %>% req_url_path_append(path) %>%
    req_url_query(!!!query) %>%
    req_headers(Authorization = cfg$ai_key, Accept = "application/json") %>%
    req_user_agent("hc-peer-pipeline") %>%
    req_throttle(rate = 30 / 60) %>%
    req_retry(max_tries = 5) %>%
    req_perform() %>%
    resp_body_json(simplifyVector = TRUE)
}

# Discovery helper — query the AI metrics catalog and (optionally) filter
# by a substring of the description. Use this to find metric_ids before
# wiring them into any *_CONFIG$ai_metric_ids list. Example:
#   search_ai_metrics(SCHOOLS_CONFIG, contains = "rank")
# Also defined in R/aid_module_pipeline.R for the same purpose; kept here
# so schools_pipeline.R is self-contained.
search_ai_metrics <- function(cfg, contains = NULL) {
  q <- list(); if (!is.null(contains)) q$description_contains <- contains
  as_tibble(ai_get(cfg, paste0("metrics/", cfg$ai_dataset), query = q))
}

# Year-naming conventions:
#   IPEDS uses fall-year (HD2024 = fall 2024 collection = academic year 2024-25)
#   Academic Insights publishes data with a 2-year lag relative to IPEDS year.
#   Empirical verification (Holy Cross applicants, metric_id 1, across 7 years):
#     AI year 2022 = IPEDS year 2020 (both = 2020-21 academic year)
#     AI year 2024 = IPEDS year 2022 (both = 2022-23 academic year)
#     AI year 2026 = IPEDS year 2024 (both = 2024-25 academic year)
#   So AI year Y refers to the same academic year as IPEDS year Y - 2.
# Our facts tables use IPEDS-naming throughout. These two helpers translate
# between the conventions when we read from or write to AI:
#   ipeds_to_ai_year(2024) -> 2026  (ask AI for the right year when our IPEDS code says 2024)
#   ai_to_ipeds_year(2026) -> 2024  (convert an AI-returned year to facts-table year)
ipeds_to_ai_year <- function(y) as.integer(y) + 2L
ai_to_ipeds_year <- function(y) as.integer(y) - 2L

# =============================================================================
# 2b. College Scorecard helper - paged fetch
# =============================================================================
# Scorecard API:
#   base:   https://api.data.gov/ed/collegescorecard/v1/schools
#   key:    SCORECARD_API_KEY (api_key query parameter)
#   paging: per_page up to 100; iterate page index 0, 1, ...
#   fields: comma-separated list of dotted field paths, e.g.
#           "id,school.name,school.accreditor"
# Returns the concatenated "results" arrays as a tibble.
scorecard_get <- function(cfg, fields, query = list(), per_page = 100) {
  if (cfg$scorecard_key == "")
    stop("SCORECARD_API_KEY not set in environment.")
  
  base <- "https://api.data.gov/ed/collegescorecard/v1/schools"
  out  <- list()
  page <- 0L
  repeat {
    q <- c(list(api_key = cfg$scorecard_key,
                fields  = paste(fields, collapse = ","),
                per_page = per_page,
                page = page),
           query)
    resp <- request(base) %>%
      req_url_query(!!!q) %>%
      req_user_agent("hc-peer-pipeline") %>%
      req_throttle(rate = 60 / 60) %>%
      req_retry(max_tries = 5) %>%
      req_perform() %>%
      resp_body_json(simplifyVector = TRUE)
    res <- resp$results
    if (is.null(res) || length(res) == 0) break
    out[[length(out) + 1]] <- as_tibble(res)
    total <- resp$metadata$total %||% 0
    page  <- page + 1L
    if (page * per_page >= total) break
  }
  if (!length(out)) return(tibble())
  bind_rows(out)
}

# small null-coalesce
`%||%` <- function(a, b) if (is.null(a)) b else a

# =============================================================================
# 3. US News classification (Academic Insights, by state)
# =============================================================================
build_classification <- function(cfg) {
  message("Pulling US News classification (schools, by state) ...")
  states <- c(state.abb, "DC", "PR")
  raw <- map_dfr(states, function(st) {
    df <- tryCatch(
      as_tibble(ai_get(cfg, paste0("schools/", cfg$ai_dataset),
                       query = list(state = st))),
      error = function(e) { warning(sprintf("state %s failed: %s",
                                            st, conditionMessage(e))); tibble() })
    message(sprintf("  %s: %d schools", st, nrow(df)))
    df
  })
  if (!nrow(raw) || !"ipeds_id" %in% names(raw)) {
    warning("classification pull returned nothing usable"); return(tibble())
  }
  raw %>%
    filter(!is.na(ipeds_id)) %>%
    transmute(unitid = as.integer(ipeds_id), usnews_classification = classification) %>%
    distinct(unitid, .keep_all = TRUE) %>%
    mutate(in_ranked_universe =
             usnews_classification %in% cfg$ranked_classes |
             grepl("^regional-universities-", usnews_classification))
}

# =============================================================================
# 3a. US News overall rank (Academic Insights, single metric, latest year)
# =============================================================================
# Returns tibble(unitid, usnews_rank). NA for unranked schools.
# Helper to discover the right metric_id, run once when wiring this up:
#   search_ai_metrics(SCHOOLS_CONFIG, contains = "rank")
# then set SCHOOLS_CONFIG$usnews_rank_metric_id.
build_usnews_rank <- function(cfg) {
  mid <- cfg$usnews_rank_metric_id
  if (is.null(mid) || is.na(mid)) {
    message("SCHOOLS_CONFIG$usnews_rank_metric_id not set; skipping rank pull. ",
            "Discover the metric_id via search_ai_metrics(SCHOOLS_CONFIG, contains = \"rank\").")
    return(tibble(unitid = integer(), usnews_rank = integer()))
  }
  # Latest AI year corresponds to our latest collection year.
  ai_year <- ipeds_to_ai_year(max(cfg$collection_years))
  message(sprintf("Pulling US News rank (metric_id %d, AI year %d) ...",
                  mid, ai_year))
  res <- tryCatch(
    ai_get(cfg, paste0("facts/", cfg$ai_dataset),
           query = list(metric_ids = mid, years = ai_year, all_data = "true")),
    error = function(e) {
      warning(sprintf("rank facts pull failed: %s", conditionMessage(e)))
      NULL
    })
  df <- as_tibble(res)
  if (!nrow(df) || !"ipeds_id" %in% names(df) || !"value" %in% names(df)) {
    warning("rank facts pull returned nothing usable")
    return(tibble(unitid = integer(), usnews_rank = integer()))
  }
  out <- df %>%
    filter(!is.na(ipeds_id)) %>%
    transmute(unitid     = as.integer(ipeds_id),
              usnews_rank = suppressWarnings(as.integer(value))) %>%
    distinct(unitid, .keep_all = TRUE)
  message(sprintf("  pulled rank for %d institutions", nrow(out)))
  out
}

# =============================================================================
# 3b. College Scorecard - accreditor (institutional attribute)
# =============================================================================
# Pulls each school's accreditor name from the latest Scorecard release.
# Used as a filter/scope field on schools.csv, not as a clustering variable.
# Returns tibble(unitid, accreditor) or tibble() on failure.
build_accreditor <- function(cfg) {
  if (cfg$scorecard_key == "") {
    warning("SCORECARD_API_KEY not set; skipping accreditor pull.")
    return(tibble(unitid = integer(), accreditor = character()))
  }
  message("Pulling accreditor from College Scorecard ...")
  fields <- c("id", "school.accreditor")
  # Filter to Title-IV-participating SECTOR 1/2 (public/private NFP 4-year)
  # to stay within the universe and avoid pulling the entire Scorecard catalog.
  raw <- tryCatch(
    scorecard_get(cfg, fields, query = list(
      `school.degrees_awarded.predominant__range` = "3..4",
      `school.ownership` = "1,2"
    )),
    error = function(e) {
      warning(sprintf("Scorecard pull failed: %s", conditionMessage(e)))
      tibble()
    })
  if (!nrow(raw) || !"id" %in% names(raw)) {
    warning("Scorecard accreditor pull returned nothing usable")
    return(tibble(unitid = integer(), accreditor = character()))
  }
  acc_col <- if ("school.accreditor" %in% names(raw)) "school.accreditor" else
    grep("accreditor", names(raw), value = TRUE)[1]
  if (is.na(acc_col)) {
    warning("Scorecard response missing accreditor field")
    return(tibble(unitid = integer(), accreditor = character()))
  }
  out <- raw %>%
    transmute(unitid = as.integer(id),
              accreditor = as.character(.data[[acc_col]])) %>%
    filter(!is.na(unitid)) %>%
    distinct(unitid, .keep_all = TRUE)
  message(sprintf("  pulled accreditor for %d institutions", nrow(out)))
  out
}

# =============================================================================
# 4. Carnegie 2025 Public Data File - data + value labels
# =============================================================================
build_carnegie <- function(cfg) {
  if (!file.exists(cfg$carnegie_file)) {
    warning(sprintf("Carnegie file not found at '%s'. Schools will be built ",
                    "without Carnegie classifications.", cfg$carnegie_file))
    return(list(data = tibble(unitid = integer()), labels = tibble()))
  }
  message(sprintf("Loading Carnegie 2025 data file: %s ...",
                  basename(cfg$carnegie_file)))
  
  wanted <- c(
    "unitid",
    "ic2025", "ic2025name",
    "saec2025", "saec2025name",
    "research2025", "research2025name",
    "setting2025", "highest_degree_2025", "basic2021",
    "ic2025size", "ic2025alf", "apm", "gpm",
    # academic concentration (one-time Carnegie snapshot; documented as an
    # admissions-relevant institutional attribute)
    "apm_max_cip2percent", "apm_max_cip2_name",
    # earnings_ratio: CCIHE's SAEC computation of earnings vs expected
    # earnings given demographics. Outcomes-relevant; kept here as a
    # one-time snapshot. source = ccihe in outcomes_variables.csv.
    "earnings_ratio",
    "pbi", "annhsi", "aanapisi", "hsi", "nasnti", "womenonly",
    "rpu", "cce", "lpp"
  )
  d <- readxl::read_excel(cfg$carnegie_file, sheet = "data", na = c("", "NA")) %>%
    select(any_of(wanted)) %>%
    mutate(unitid = suppressWarnings(as.integer(unitid))) %>%
    filter(!is.na(unitid))
  
  rn <- c(ic2025name = "ic2025_label",
          saec2025name = "saec2025_label",
          research2025name = "research2025_label")
  for (old in names(rn)) {
    if (old %in% names(d)) d <- rename(d, !!rn[[old]] := !!sym(old))
  }
  message(sprintf("  loaded Carnegie data: %d institutions, %d columns",
                  nrow(d), ncol(d)))
  
  vraw <- readxl::read_excel(cfg$carnegie_file, sheet = "values",
                             col_names = c("variable", "code", "label"),
                             skip = 1, na = c("", "NA"))
  v <- vraw %>%
    fill(variable, .direction = "down") %>%
    filter(!is.na(code), !is.na(label)) %>%
    mutate(variable = toupper(trimws(as.character(variable))),
           code     = as.character(code),
           label    = as.character(label))
  shared <- v %>% filter(grepl("^APM AND GPM$", variable))
  if (nrow(shared)) {
    v <- v %>% filter(!grepl("^APM AND GPM$", variable)) %>%
      bind_rows(shared %>% mutate(variable = "APM"),
                shared %>% mutate(variable = "GPM"))
  }
  v <- v %>% mutate(variable = ifelse(variable == "SAEC25", "SAEC2025", variable))
  v <- v %>%
    transmute(table_name = "Carnegie2025", variable, code, label) %>%
    distinct(table_name, variable, code, .keep_all = TRUE)
  
  message(sprintf("  loaded Carnegie value labels: %d rows across %d variables",
                  nrow(v), n_distinct(v$variable)))
  
  list(data = d, labels = v)
}

# =============================================================================
# 5. IPEDS value labels (returns tibble; combined with Carnegie before writing)
# =============================================================================
build_ipeds_value_labels <- function(cfg) {
  yr <- cfg$labels_year
  vs_name <- paste0("valueSets", sprintf("%02d", yr %% 100))
  message(sprintf("Building IPEDS value labels from %s ...", vs_name))
  vs <- get_raw_table(yr, vs_name)
  if (is.null(vs)) {
    warning(sprintf("%s not found in collection %d", vs_name, yr))
    return(tibble(table_name=character(), variable=character(),
                  code=character(), label=character()))
  }
  names(vs) <- tolower(names(vs))
  pick <- function(...) { hits <- intersect(c(...), names(vs)); if (length(hits)) hits[1] else NA_character_ }
  tcol <- pick("tablename", "table_name", "table")
  vcol <- pick("varname", "variable", "varnme")
  ccol <- pick("codevalue", "code", "value")
  lcol <- pick("valuelabel", "label", "labelvalue")
  if (any(is.na(c(tcol, vcol, ccol, lcol)))) {
    warning("valueSets has unexpected columns: ",
            paste(names(vs), collapse = ", "))
    return(tibble(table_name=character(), variable=character(),
                  code=character(), label=character()))
  }
  out <- tibble(
    table_name = as.character(vs[[tcol]]),
    variable   = toupper(as.character(vs[[vcol]])),
    code       = as.character(vs[[ccol]]),
    label      = as.character(vs[[lcol]])
  ) %>% distinct(table_name, variable, code, .keep_all = TRUE)
  message(sprintf("  IPEDS: %d rows across %d variables",
                  nrow(out), n_distinct(out$variable)))
  out
}

attach_label <- function(df, code_col, variable, labels,
                         label_col = paste0(code_col, "_label")) {
  if (!code_col %in% names(df) || !nrow(labels)) return(df)
  lk <- labels %>% filter(toupper(.data$variable) == toupper(!!variable)) %>%
    distinct(code, label)
  if (!nrow(lk)) return(df)
  df %>%
    mutate(.code_lookup = as.character(.data[[code_col]])) %>%
    left_join(lk, by = c(".code_lookup" = "code")) %>%
    rename(!!label_col := label) %>%
    select(-.code_lookup)
}

# =============================================================================
# 5b. RELIGIOUS AFFILIATION DECODE
# =============================================================================
# IPEDS IC table's RELAFFIL field uses a numeric code. Codes verified against
# the official IPEDS IC2023 codebook (RELAFFIL data dictionary).
#
# We return three columns:
#   religious_affiliation_code  : raw IPEDS integer code
#   religious_affiliation       : human-readable denomination label
#   religious_tradition         : broader tradition rollup (Catholic /
#                                 Protestant / Other Christian / Jewish /
#                                 Other / NA)
#
# The tradition rollup is useful for clustering because the specific
# denomination granularity (50+ codes) is rarely meaningful for institutional
# comparison, while "Catholic vs Mainline Protestant vs Other Christian vs
# Jewish vs Other" captures most of the variation institutions actually care
# about.
#
# Tradition assignments follow standard categorical conventions:
#   Catholic         : Roman Catholic only
#   Protestant       : denominationally-specific Protestant traditions
#                      (Lutheran, Methodist, Presbyterian, Baptist, etc.)
#   Other Christian  : Eastern Orthodox, LDS, nondenominational/ecumenical,
#                      multi-denominational
#   Jewish           : Jewish
#   Other            : Muslim, Buddhist, Unitarian Universalist, and the
#                      catch-all "Other (none of the above)"
#
# Codes -1 ("Not reported") and -2 ("Not applicable") map to NA tradition.
# Any code we don't recognize is labeled "Other religious" rather than NA,
# so downstream filters don't silently drop rows.
.RELAFFIL_LOOKUP <- tribble(
  ~code, ~label,                                              ~tradition,
  -1L,   "Not reported",                                      NA_character_,
  -2L,   "Not applicable",                                    NA_character_,
  22L,   "American Evangelical Lutheran Church",              "Protestant",
  24L,   "African Methodist Episcopal Zion Church",           "Protestant",
  27L,   "Assemblies of God Church",                          "Protestant",
  28L,   "Brethren Church",                                   "Protestant",
  30L,   "Roman Catholic",                                    "Catholic",
  33L,   "Wisconsin Evangelical Lutheran Synod",              "Protestant",
  34L,   "Christ and Missionary Alliance Church",             "Protestant",
  35L,   "Christian Reformed Church",                         "Protestant",
  36L,   "Evangelical Congregational Church",                 "Protestant",
  37L,   "Evangelical Covenant Church of America",            "Protestant",
  38L,   "Evangelical Free Church of America",                "Protestant",
  39L,   "Evangelical Lutheran Church",                       "Protestant",
  40L,   "International United Pentecostal Church",           "Protestant",
  41L,   "Free Will Baptist Church",                          "Protestant",
  42L,   "Interdenominational",                               "Other Christian",
  43L,   "Mennonite Brethren Church",                         "Protestant",
  44L,   "Moravian Church",                                   "Protestant",
  45L,   "North American Baptist",                            "Protestant",
  47L,   "Pentecostal Holiness Church",                       "Protestant",
  48L,   "Christian Churches and Churches of Christ",         "Protestant",
  49L,   "Reformed Church in America",                        "Protestant",
  50L,   "Episcopal Church, Reformed",                        "Protestant",
  51L,   "African Methodist Episcopal",                       "Protestant",
  52L,   "American Baptist",                                  "Protestant",
  53L,   "American Lutheran",                                 "Protestant",
  54L,   "Baptist",                                           "Protestant",
  55L,   "Christian Methodist Episcopal",                     "Protestant",
  57L,   "Church of God",                                     "Protestant",
  58L,   "Church of Brethren",                                "Protestant",
  59L,   "Church of the Nazarene",                            "Protestant",
  60L,   "Cumberland Presbyterian",                           "Protestant",
  61L,   "Christian Church (Disciples of Christ)",            "Protestant",
  64L,   "Free Methodist",                                    "Protestant",
  65L,   "Friends",                                           "Protestant",
  66L,   "Presbyterian Church (USA)",                         "Protestant",
  67L,   "Lutheran Church in America",                        "Protestant",
  68L,   "Lutheran Church - Missouri Synod",                  "Protestant",
  69L,   "Mennonite Church",                                  "Protestant",
  71L,   "United Methodist",                                  "Protestant",
  73L,   "Protestant Episcopal",                              "Protestant",
  74L,   "Churches of Christ",                                "Protestant",
  75L,   "Southern Baptist",                                  "Protestant",
  76L,   "United Church of Christ",                           "Protestant",
  77L,   "Protestant, not specified",                         "Protestant",
  78L,   "Multiple Protestant Denomination",                  "Protestant",
  79L,   "Other Protestant",                                  "Protestant",
  80L,   "Jewish",                                            "Jewish",
  81L,   "Reformed Presbyterian Church",                      "Protestant",
  84L,   "United Brethren Church",                            "Protestant",
  87L,   "Missionary Church Inc",                             "Protestant",
  88L,   "Undenominational",                                  "Other Christian",
  89L,   "Wesleyan",                                          "Protestant",
  91L,   "Greek Orthodox",                                    "Other Christian",
  92L,   "Russian Orthodox",                                  "Other Christian",
  93L,   "Unitarian Universalist",                            "Other",
  94L,   "The Church of Jesus Christ of Latter-day Saints",   "Other Christian",
  95L,   "Seventh Day Adventist",                             "Protestant",
  97L,   "The Presbyterian Church in America",                "Protestant",
  99L,   "Other (none of the above)",                         "Other",
  100L,  "Original Free Will Baptist",                        "Protestant",
  101L,  "Ecumenical Christian",                              "Other Christian",
  102L,  "Evangelical Christian",                             "Other Christian",
  103L,  "Presbyterian",                                      "Protestant",
  104L,  "Virginia Baptist General Association",              "Protestant",
  105L,  "General Baptist",                                   "Protestant",
  106L,  "Muslim",                                            "Other",
  107L,  "Plymouth Brethren",                                 "Protestant",
  108L,  "Non-Denominational",                                "Other Christian",
  109L,  "Buddhist/Buddhism",                                 "Other",
  110L,  "Orthodox Christian",                                "Other Christian"
)

.relaffil_label <- function(code) {
  out <- .RELAFFIL_LOOKUP$label[match(code, .RELAFFIL_LOOKUP$code)]
  # Recognized but unmapped codes (e.g., new denomination in a future IPEDS
  # release) become "Other religious" rather than NA, so they remain
  # filterable instead of silently dropping.
  ifelse(is.na(code), NA_character_,
         ifelse(is.na(out) & code > 0, "Other religious", out))
}

.relaffil_tradition <- function(code) {
  out <- .RELAFFIL_LOOKUP$tradition[match(code, .RELAFFIL_LOOKUP$code)]
  # Codes that map to NA tradition stay NA. Both -1 ("Not reported") and
  # -2 ("Not applicable") get NA tradition; the absence of a tradition is
  # the correct semantic for those institutions.
  out
}

# =============================================================================
# 6. BUILD schools.csv
# =============================================================================
build_schools <- function(cfg = SCHOOLS_CONFIG) {
  message("== Building schools.csv ==")
  
  all_hd <- map_dfr(cfg$collection_years, function(yr) {
    hd <- get_table(yr, paste0("HD", yr))
    if (is.null(hd)) return(tibble())
    grab <- function(col) if (col %in% names(hd)) hd[[col]] else NA
    
    tibble(
      unitid     = hd$unitid,
      year       = yr,
      instnm     = grab("INSTNM"),
      sector     = suppressWarnings(as.integer(grab("SECTOR"))),
      control    = suppressWarnings(as.integer(grab("CONTROL"))),
      iclevel    = suppressWarnings(as.integer(grab("ICLEVEL"))),
      stabbr     = grab("STABBR"),
      longitud   = suppressWarnings(as.numeric(grab("LONGITUD"))),
      latitude   = suppressWarnings(as.numeric(grab("LATITUDE"))),
      hbcu       = suppressWarnings(as.integer(grab("HBCU"))),
      hospital   = suppressWarnings(as.integer(grab("HOSPITAL"))),
      medical    = suppressWarnings(as.integer(grab("MEDICAL"))),
      tribal     = suppressWarnings(as.integer(grab("TRIBAL"))),
      instcat    = suppressWarnings(as.integer(grab("INSTCAT"))),
      locale     = suppressWarnings(as.integer(grab("LOCALE"))),
      instsize   = suppressWarnings(as.integer(grab("INSTSIZE")))
    ) %>%
      filter(sector %in% cfg$keep_sectors)
  })
  
  # Religious affiliation pulled once from IC2023 (the field changes very
  # slowly for institutions; using a single year and applying uniformly is
  # a documented simplification, similar to how Carnegie classifications
  # are applied). RELAFFIL lives in IC (Institutional Characteristics),
  # not HD (Header). If IC2023 isn't loadable for any reason, religious
  # affiliation columns will be all NA and the rest of the pipeline still
  # runs.
  relaffil_lookup <- {
    ic23 <- tryCatch(get_table(2023, "IC2023"), error = function(e) NULL)
    if (is.null(ic23) || !"RELAFFIL" %in% names(ic23)) {
      message("  Note: IC2023 not available or missing RELAFFIL; religious affiliation will be NA")
      tibble(unitid = integer(), relaffil = integer())
    } else {
      tibble(unitid = ic23$unitid,
             relaffil = suppressWarnings(as.integer(ic23$RELAFFIL)))
    }
  }
  
  schools <- all_hd %>%
    arrange(unitid, desc(year)) %>%
    group_by(unitid) %>%
    summarise(
      latest_year = first(year),
      instnm      = first(instnm),
      sector      = first(sector),
      control     = first(control),
      iclevel     = first(iclevel),
      stabbr      = first(stabbr),
      longitud    = first(longitud),
      latitude    = first(latitude),
      hbcu        = first(hbcu),
      hospital    = first(hospital),
      medical     = first(medical),
      tribal      = first(tribal),
      instcat     = first(instcat),
      locale      = first(locale),
      instsize    = first(instsize),
      .groups     = "drop"
    ) %>%
    mutate(control_grp = case_when(
      sector == 1 ~ "public",
      sector == 2 ~ "private_nfp",
      TRUE        ~ "other"
    )) %>%
    left_join(relaffil_lookup, by = "unitid") %>%
    mutate(
      religious_affiliation_code = relaffil,
      religious_affiliation      = .relaffil_label(relaffil),
      religious_tradition        = .relaffil_tradition(relaffil)
    )
  
  classn <- build_classification(cfg)
  schools <- schools %>%
    left_join(classn, by = "unitid") %>%
    mutate(in_ranked_universe = ifelse(is.na(in_ranked_universe),
                                       FALSE, in_ranked_universe))

  # US News overall rank — separate AI pull because rank is a metric
  # (facts/) not an institutional attribute (schools/). Returns an empty
  # tibble when the metric_id is unset, so the join is a no-op until
  # SCHOOLS_CONFIG$usnews_rank_metric_id is filled in.
  usn_rank <- build_usnews_rank(cfg)
  if (nrow(usn_rank)) {
    schools <- schools %>% left_join(usn_rank, by = "unitid")
  }
  
  carnegie <- build_carnegie(cfg)
  if (nrow(carnegie$data)) {
    schools <- schools %>% left_join(carnegie$data, by = "unitid")
  }
  
  accreditor <- build_accreditor(cfg)
  if (nrow(accreditor)) {
    schools <- schools %>% left_join(accreditor, by = "unitid")
  }
  
  ipeds_labels <- build_ipeds_value_labels(cfg)
  all_labels <- bind_rows(ipeds_labels, carnegie$labels) %>%
    distinct(table_name, variable, code, .keep_all = TRUE)
  write.csv(all_labels, .out_path("value_labels.csv"), row.names = FALSE)
  message(sprintf("Wrote %s: %d rows", .out_path("value_labels.csv"),
                  nrow(all_labels)))
  
  for (f in cfg$labeled_fields) {
    schools <- attach_label(schools, f, toupper(f), all_labels)
  }
  
  message(sprintf("  %d distinct schools; %d in ranked universe; %d with Carnegie ic2025; %d with accreditor; %d with religious affiliation",
                  nrow(schools),
                  sum(schools$in_ranked_universe, na.rm = TRUE),
                  if ("ic2025" %in% names(schools)) sum(!is.na(schools$ic2025)) else 0,
                  if ("accreditor" %in% names(schools)) sum(!is.na(schools$accreditor)) else 0,
                  sum(!is.na(schools$religious_tradition) &
                        schools$religious_affiliation != "Not applicable", na.rm = TRUE)))
  
  write.csv(schools, .out_path("schools.csv"), row.names = FALSE)
  message(sprintf("Wrote %s", .out_path("schools.csv")))
  invisible(schools)
}

# -----------------------------------------------------------------------------
# Usage:
#   setwd("path/to/hc-peer")
#   Sys.setenv(ACADEMIC_INSIGHTS_API_KEY = "...")
   schools <- build_schools()
# Produces output/schools.csv and output/value_labels.csv.
# -----------------------------------------------------------------------------