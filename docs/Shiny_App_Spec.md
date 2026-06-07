# Peer Schools Shiny App — Design Spec

A configurable explorer for the peer-selection methodology, built on top of `compute_peers()` in `R/peer_pipeline.R`. This document captures locked-in design decisions; it is a living doc, update as we build.

For background see `docs/project_handoff.md` (architecture), `docs/Clustering_Methods_Reference.md` (method choices), and `docs/Layer3_clustvarsel_Findings.md` (variable-selection findings that may inform Shiny defaults).

---

## Goals

Make `compute_peers()` accessible to non-R-coding stakeholders for institutional peer comparison work. Three primary user actions the app must support cleanly:

1. **Run a peer search** with configurable theme weights and candidate-pool filters.
2. **Compare peers head-to-head** with the anchor school across all variables.
3. **Save and download** searches with enough context (data + codebook + methodology snapshot) that the output is usable downstream and audit-defensible.

---

## Primary features (locked)

### 1. Theme-weight control

Eight sliders in the sidebar, one per theme (`size`, `selectivity`, `resources`, `finance`, `outcomes`, `aid`, `student_body`, `athletics`). Range 0 to 3, default 1.0, step 0.25 (athletics defaults to 0, opt-in).

A small "Presets" row above the sliders with quick buttons:
- **Balanced** (all 1.0) — default
- **Outcomes-heavy** (outcomes = 2.5, others = 1.0)
- **Resources-heavy** (resources = 2.0, finance = 1.5)
- **Mission-similar** (composition = 2.0)

Each preset just sets the sliders; user can then tweak. Map directly to `compute_peers(theme_weights = list(...))`.

### 2. Candidate-pool filters

Controls in the sidebar, all multi-select where applicable:

- **USNews classification** — multi-select with options: National Universities, National Liberal Arts Colleges, Regional Universities (with sub-options for region: North, South, Midwest, West). Default: same as anchor's classification (a checkbox above the multi-select toggles "Same as anchor"). When same-as-anchor is on, the multi-select is grayed out.
- **Sector / control** — multi-select: Public, Private NFP. Default: same as anchor (with the same toggle pattern).
- **State** — multi-select of 50 + DC + territories. Default: empty (no state filter). Useful for regional peer sets.
- **Religious affiliation** — multi-select of `religious_tradition` values (Catholic, Protestant, Other Christian, Jewish, Other, [None]). Default: empty (no filter). Important per stakeholder request — allows e.g. "Catholic-only" peer searches without methodology changes.
- **Ranked universe only** — single checkbox, default ON. Matches `compute_peers()`'s default `in_ranked_universe = TRUE`.

All controls map directly to `compute_peers(candidate_pool = list(...))`. Empty multi-select = no filter on that dimension.

### 3. Session memory + manual save

A "Save this search" button next to the Run button. Clicking save adds the current result to a "Saved Searches" tab with:
- Auto-generated label: `[anchor name] | [pool summary] | [theme summary]`
- Editable label field (user can rename)
- Timestamp
- Number of peers returned
- A "View" button (reloads the result into the active tabs)
- A "Delete" button

Session state lives in `reactiveVal()`. Persistence across sessions is **deferred to v2** (see Future: GCS persistence).

### 4. Click-to-compare side-by-side view

On the Peer Search tab, the results table uses `DT` with single-row selection. Clicking a row opens or focuses the Side-by-Side tab and populates it with:

- Header: Anchor name + selected peer name + distance
- Sections grouped by theme (collapsible)
- Per variable, a row showing:
  - Variable display name
  - Anchor value (formatted per `format` column: currency / percentage / count / ratio)
  - Peer value
  - A small horizontal bar showing each school's position in the candidate-pool distribution (z-scored)
  - Difference indicator (signed)
- All clustering + descriptive variables shown. Clustering variables visually emphasized (bold or background tint).

Source data: a wide matrix of all variables (not just the clustering ones) joined to schools.csv metadata. Built once at startup; reused for every comparison.

---

## Framework and architecture

- **UI framework**: `bslib` (Bootstrap 5). Clean look, dark-mode-capable, actively developed.
- **Table library**: `DT` for the peer results table (row selection, sorting, filtering).
- **Visualization**: `ggplot2` + `plotly` for the side-by-side distribution bars. Keep static where possible to limit complexity.
- **Reactivity model**: **On-demand**. A "Run search" button gates `compute_peers()`. Sliders and filters do not auto-trigger searches. This is honest about per-search compute cost (1-3 sec) and matches how users actually think about peer-search work (set knobs, run, examine, adjust).
- **Caching**: Memoize `compute_peers()` calls within a session by argument hash, so re-running with identical settings is instant.

## File structure

```
shiny_app/
├── app.R                  # entry point; just sources global.R, ui.R, server.R
├── global.R               # source peer_pipeline.R; load schools + facts once; build wide matrix
├── R/
│   ├── ui_sidebar.R       # left controls panel (anchor, pool filters, theme sliders, Run/Save buttons)
│   ├── ui_tabs.R          # main panel tabs (Peer Search / Side-by-Side / Saved Searches)
│   ├── mod_peer_table.R   # Tab 1 module
│   ├── mod_compare.R      # Tab 2 module
│   ├── mod_session.R      # Tab 3 module + download handler
│   ├── compute_peers_cached.R  # memoized wrapper
│   ├── build_codebook.R   # combines *_variables.csv into a single codebook tibble
│   └── bundle_download.R  # zip builder for a saved search bundle
└── www/
    └── styles.css
```

Target size: 600-900 lines all in. Modular so we can build one tab at a time.

---

## Download bundle

When the user clicks Download on a saved search, produce a zip containing:

| File | Content |
|---|---|
| `peers.csv` | The peer results table: rank, unitid, instnm, sector, classification, state, religious_affiliation, distance |
| `peers_wide.csv` | Wide matrix of all variables (clustering + descriptive) for anchor + the K returned peers, with school metadata columns. One row per institution. |
| `codebook.csv` | Combined `*_variables.csv` across all 5 modules: metric, display_name, category, source, format, use_type, comparison_scope, neche_peer_set, neche_dashboard, coverage_note, notes. With a top-row methodology preamble row. |
| `methodology.txt` | Plain-text snapshot of the search settings: anchor, candidate-pool filters applied, theme weights, distance metric, coverage threshold, variables used, variables dropped (by coverage or anchor NA), date/time of search. Audit-defensible record. |

PNG/PDF rendering of the side-by-side comparison is **explicitly out of scope for v1** to limit complexity.

---

## Future: GCS persistence (v2+)

User has requested eventually backing saved searches with a Google Cloud Storage bucket so they persist across sessions and can be shared. Design implications for v2:

- Saved-search objects become JSON-serializable
- Auth via service account JSON in `.Renviron`
- A "Load from bucket" UI in the Saved Searches tab
- Bundles uploaded to a per-user prefix
- `googleCloudStorageR` is the main R client

Not blocking v1. Build the in-memory model first, swap the persistence backend later.

---

## Locked design decisions

1. **Anchor school selector** — typeahead search across all ~2,598 institutions via server-side `selectizeInput`. Holy Cross pre-selected on load. Users can search by partial name or unitid.
2. **K (number of peers)** — slider 5–50, default 20. Range fits realistic peer-comparison use cases; 5 supports a tight cohort view, 50 covers most "expanded peer set" needs without making the side-by-side view unmanageable.
3. **Diagnostics** — collapsible panel below the peer table on Tab 1, expanded by default. Shows variables used, variables dropped (by coverage / by anchor NA), per-variable weights. Same content also goes into `methodology.txt` in the download bundle.
4. **Mahalanobis toggle** — exposed in an "Advanced" expander in the sidebar, collapsed by default. When the user opts in, the result label and methodology snapshot record which metric was used (including the "Mahalanobis fallback" case when covariance is singular). Default remains Euclidean.

## Still open

5. **clustvarsel-informed "Lean default" variable preset** — whether to add a preset that restricts the variable set to clustvarsel's selected subset depends on the pass D results: which variables are selected, how stable they are across runs, and whether the resulting peer list looks materially different from the full-variable default. Decision deferred until pass D lands and we look at the findings together.

---

## Planned extensions (v1.5 and v2)

Three features are designed but not in the v1 scope. Each addresses a real institutional research need that came up during methodology discussion. They are documented here so that when we return to them the design conversation does not have to restart.

### Stratified peer sets (step 6)

**Goal.** Let a user see the closest peers in each of several institutional categories at once. Examples of the kinds of question this answers:

- "Closest LAC peer, closest National University peer, closest Regional University peer, all in one view."
- "Closest Catholic peer, closest Protestant peer, closest secular peer."
- "Closest in-state peer, closest out-of-state peer."

**Implementation.** A wrapper around `compute_peers()` that calls it once per value of a chosen category dimension. The category is user-selected: `usnews_classification`, `religious_tradition`, geographic region, or `control_grp`. For each value of that dimension that has at least one school in the universe, the wrapper runs a separate peer search with the rest of the sidebar controls (anchor, theme weights, base pool filter) held constant.

**UI sketch.** A new "Stratified Peers" tab. The sidebar's existing controls govern the underlying searches; an additional control in the tab body sets the stratification dimension and the per-stratum K. Output is a faceted view: one card per category value, each containing that stratum's top-K peers.

**Methodology note.** Distances within a stratum are directly comparable. Distances across strata are *not* directly comparable in their raw form, because each stratum is its own candidate pool with its own z-scoring. The stratified view will surface the comparable distance metrics described below alongside the raw distance so users can read cross-stratum closeness without mistaking different scales.

**Open questions deferred to build time.**

- Whether K should be the same for every stratum, proportional to stratum size, or user-set per stratum.
- How to handle strata with zero schools after filters apply (empty cards, or hide that stratum entirely).
- Whether to offer a "Top K overall with stratum labels" alternative view alongside the faceted one.

### Aspirant peer identification (step 7)

**Goal.** Distinguish "schools like the anchor" (current peers) from "schools the anchor wants to be like" (aspirant peers). Current weighted Euclidean cannot make this distinction on its own because the distance is symmetric. A candidate that exceeds the anchor on outcomes is treated identically to one that falls below it by the same amount.

**Implementation.** Post-hoc filtering on a regular `compute_peers()` result. The methodology is preserved; aspirant identification is a downstream interpretation layer.

1. Run a peer search with an enlarged K (say 50 to 100, configurable) so the post-hoc filter has room to work.
2. For each user-specified "aspirational variable," filter the result to schools that exceed the anchor by at least a tolerance (default 0.5 standard deviations).
3. For variables where lower is more aspirational (acceptance rate, default rate), the comparison inverts.

**UI sketch.** A new "Aspirant Peers" tab. The tab body offers a curated multi-select of aspirational variable candidates (endowment per FTE, six-year graduation rate, ten-year earnings, retention rate, acceptance rate inverted, and so on), plus a tolerance slider in standard deviations and a base-K slider. Output is the filtered peer list, with each row labeled by which aspirational thresholds it cleared.

**Methodology note.** This is filtering, not a different distance metric. The peer set is the intersection of "close on the methodology's terms" and "above anchor on user-specified aspirational dimensions." Empty results are a meaningful signal that the anchor is already at or near the top of its peer space on the selected aspirational variables.

**Open questions deferred to build time.**

- Curated list of which variables make sensible aspirational candidates. Probably 8 to 12 of the 53 clustering variables, not all of them.
- How to handle "lower is more aspirational" variables in the UI. Auto-invert based on a variable-level tag, or explicit per-variable direction control.
- Empty-state handling when no peers pass the filter. Hint to expand K or loosen tolerance.

### Distance comparability (cross-search and cross-stratum)

**Goal.** Make peer-search distances meaningful across searches with different candidate pools and weights. The stratified peer sets feature creates real demand for this. A user looking at "closest LAC peer at distance 0.7" alongside "closest National University peer at distance 1.4" should not be left guessing whether the second is genuinely less similar or just measured against a more spread-out pool.

**Implementation.** Add two derived metrics to the peer result, computed downstream from the same z-scored data the methodology already produces. The raw distance remains the primary output. The new metrics are supplementary columns surfaced in the diagnostics panel and the download bundle.

1. **Relative distance.** Raw distance divided by the median of all pairwise distances within the candidate pool. A value of 0.30 means the peer is roughly 30% as far from the anchor as a typical pair in the pool is from each other. Comparable across pools because it normalizes by each pool's internal spread.
2. **Percentile rank.** Where the (anchor, candidate) pair sits in the sorted distribution of all (anchor, pool-member) distances. The closest peer is at the 99.X percentile; a borderline match might be at the 95th. Comparable across pools because it is a rank statistic, not a magnitude.

Both metrics can be computed in O(n) over the existing per-candidate distances, which `compute_peers()` already calculates internally before truncating to top-K. A small refactor will expose the full pool-distance distribution to the meta block so the wrapper can compute these without recomputing distances.

**Methodology note.** Pool-specific z-scoring stays as the primary methodology. It is correct for the within-pool similarity question. The relative and percentile metrics are *derived* views, not alternatives. They let users compare across pools without changing what the distance itself answers.

**Where this lives.**

- Per-row columns in the peer results table, in the diagnostics section (so the main table stays uncluttered).
- Columns in the `peers.csv` and `peers_wide.csv` files in the download bundle.
- A line in the `methodology.txt` snapshot explaining that within-pool z-scoring drives the raw distance and that the derived metrics make the distance comparable across pools.

**Open questions deferred to build time.**

- Which metric to surface most prominently in the stratified-peers UI. Default recommendation is percentile, on grounds of intuitive readability.
- Whether to use median or another central-tendency anchor for relative distance. Median is more robust to outliers; mean is faster to explain.
- Whether to also compute a "pool spread" indicator (interquartile range of pool-pair distances) for users to read alongside raw distance.

---

## Build order

1. **Scaffold** (`app.R`, `global.R`, blank `ui.R` + `server.R`, modules as stubs). Confirm bslib loads and the data layer joins at startup.
2. **Sidebar** (controls only, no functionality yet). Confirm theme sliders, pool filters, presets all render and bind to inputs.
3. **Tab 1: Peer Search**. Wire Run button → `compute_peers()` → DT table. End-to-end "I can do a search."
4. **Tab 2: Side-by-Side**. DT row select → comparison view.
5. **Tab 3: Saved Searches + Download**. Manual save, list management, zip bundle.
6. **Stratified peer sets** (planned extension above).
7. **Aspirant peer identification** (planned extension above).
8. **Distance comparability metrics** (planned extension above). Likely overlaps with step 6, since stratified peers create the strongest demand for comparable distances; may end up shipping together.
9. **Polish**: caching, loading indicators, input validation, error messages on impossible filter combos.

Each step is a separate working app; each can be reviewed before moving on.
