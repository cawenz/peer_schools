# Peer Schools Explorer — Maintenance Guide

Developer / sysadmin reference. Covers refreshing the underlying data,
regenerating the variable catalog, and deploying. Audience: whoever is
maintaining the pipeline and the app — not end users.

For the user-facing guide, see [`USER_GUIDE.md`](USER_GUIDE.md).

---

## Repo layout

```
data/                          raw inputs (IPEDS .Rda, Carnegie .xlsx,
                               EADA .xlsx, etc.)
output/                        pipeline outputs (schools.csv, *_facts.csv,
                               *_variables.csv) — committed so the app
                               can launch from a fresh clone
R/                             pipeline scripts + helpers
R/schools_pipeline.R           builds output/schools.csv
R/{aid,admissions,enrollment,outcomes,finance}_module_pipeline.R
                               build the five IPEDS-derived module pairs
R/athletics_module_pipeline.R  builds the athletics module
R/peer_pipeline.R              compute_peers() and ASPIRANT_DIRECTIONS
R/scrape_eada_conferences.py   Python — produces data/eada_conferences.csv
R/tools/generate_variable_catalog.R
                               writes docs/VARIABLE_CATALOG.md from
                               output/*_variables.csv
R/explore_clustvarsel.R        research script
R/explore_dbscan.R             research script
shiny_app/                     the Shiny app
docs/                          documentation (USER_GUIDE, MAINTENANCE,
                               VARIABLE_CATALOG, research findings)
```

---

## Annual data refresh

The app reads from `output/*.csv`. To refresh after a new IPEDS, Carnegie,
or EADA release:

### 1. IPEDS

Drop new `IPEDS{YYYY-YY}.Rda` files into `data/`. Update the
`collection_years` list in `R/schools_pipeline.R` and the relevant
module pipelines if the panel window shifts.

### 2. Carnegie 2025 Public Data File

Replace `data/2025-Public-Data-File.xlsx` with the new year's release.
Update the `carnegie_file` path in `R/schools_pipeline.R$SCHOOLS_CONFIG`
if the filename changes.

### 3. EADA

Download the new bulk file from <https://ope.ed.gov/athletics/#/datafile/list>
and unzip into `data/eada_2024_25/` (or rename the directory to the new
year and update `R/athletics_module_pipeline.R$ATH_CONFIG$eada_dir`).

### 4. Conferences

Run the scraper to regenerate `data/eada_conferences.csv` from
Wikipedia's institution-list pages:

```bash
python R/scrape_eada_conferences.py
```

The scraper writes a clean two-column CSV (`unitid`, `conference`,
`match_method`) plus `data/eada_conferences_unmatched.csv` as an audit
trail. Add overrides to the `OVERRIDES` dict in the script for any
Wikipedia → EADA name mismatches you want to fix.

### 5. Rebuild the outputs

From the repo root:

```bash
# Foundation: builds output/schools.csv
Rscript R/schools_pipeline.R

# Five IPEDS-derived modules (each writes output/{m}_facts.csv +
# output/{m}_variables.csv). Order doesn't matter; they're independent.
Rscript -e 'source("R/aid_module_pipeline.R")'
Rscript -e 'source("R/admissions_module_pipeline.R")'
Rscript -e 'source("R/enrollment_module_pipeline.R")'
Rscript -e 'source("R/outcomes_module_pipeline.R")'
Rscript -e 'source("R/finance_module_pipeline.R")'

# EADA module (depends on data/eada_2024_25/ + data/eada_conferences.csv)
Rscript -e 'source("R/athletics_module_pipeline.R")'

# Regenerate the variable catalog docs
Rscript R/tools/generate_variable_catalog.R
```

The Shiny app picks up the new files on next launch.

---

## Adding a new variable

1. Pick the module the variable belongs to (`aid`, `adm`, `enr`, `out`,
   `fin`, or `ath`).
2. Edit that module's pipeline (`R/{module}_module_pipeline.R`):
   - Add the extraction / derivation logic.
   - Add a row to the variables tibble describing the new metric:
     `metric`, `category`, `display_name`, `source`,
     `ipeds_table_or_formula`, `use_type` (clustering / descriptive /
     exploratory), `comparison_scope`, `format`, `neche_peer_set`,
     `neche_dashboard`, `coverage_note`, `notes`.
3. Re-run the module pipeline: `Rscript -e 'source(...)'`.
4. If the variable is `use_type = "clustering"` and belongs in a theme,
   add it to the relevant entry in `THEME_VARS` in `R/peer_pipeline.R`.
5. Regenerate the variable catalog: `Rscript R/tools/generate_variable_catalog.R`.
6. Restart the Shiny app. The variable auto-appears in the Variables
   tab, the Side-by-Side, the cohort dashboard's variable inspector,
   the Trends picker, and the codebook export.

---

## Deployment

### Local

From the repo root:

```r
shiny::runApp("shiny_app", launch.browser = TRUE)
```

### Shiny Server

The app expects the working directory to be `shiny_app/` and the
sibling `output/` and `R/peer_pipeline.R` to exist one level up. The
simplest production layout:

```
/srv/shiny-server/peer_schools/
├── shiny_app/                 # served as the app
├── output/                    # data the app reads at startup
├── R/peer_pipeline.R          # sourced by shiny_app/global.R
└── data/                      # only needed if you re-run the pipeline
                               # on the server (usually not)
```

In `/etc/shiny-server/shiny-server.conf`:

```
location /peer-schools {
  app_dir /srv/shiny-server/peer_schools/shiny_app;
}
```

Make sure the `shiny` user can read everything in
`/srv/shiny-server/peer_schools/`.

### .Renviron (optional)

`shiny_app/.Renviron` can pin paths and locale settings. Currently the
app uses hardcoded relative paths so this isn't required, but a useful
template:

```sh
R_LIBS_USER=/srv/shiny-server/peer_schools/.Rlib
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
READR_SHOW_COL_TYPES=FALSE
```

---

## Methodology defense

For "why does the app rank peers this way" questions, the locked
methodology is documented in:

- `docs/Layer3_clustvarsel_Findings.md` — research finding establishing
  why we don't use data-driven variable selection
- `docs/Shiny_App_Spec.md` — design spec for the app itself

---

## Known limitations and caveats

- **Service academies, single-sex institutions** are missing from EADA
  (they don't have to file). Their athletics columns are NA.
- **Pell coverage from CDS** is via the Academic Insights API, which
  has its own coverage gaps; the variable catalog notes which.
- **Conference matching** is fuzzy. The audit trail
  (`data/eada_conferences_unmatched.csv`) lists every Wikipedia row
  that didn't match an EADA institution. Add overrides as needed.
- **`earnings_ratio` column collision** in `output/schools.csv` and the
  facts-derived wide matrix produces `.x` / `.y` suffixed columns in
  `.SCHOOLS_WIDE`. Worked around in the cohort export handler; a proper
  fix in `global.R` is on the to-do list.
