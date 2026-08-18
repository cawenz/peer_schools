# Peer Schools Explorer — User Guide

A tool for finding, comparing, and curating institutional peers for
Holy Cross (or any U.S. college or university).

---

## What this app does

You give the app an **anchor** institution — Holy Cross by default — and
it returns the schools most similar to it, using the criteria you care
about. Different constituencies on campus care about different things,
so the app lets you shift the lens: peers for athletics, for
affordability, for outcomes, for institutional research profile.

The core question the app answers is: **"Who are our peers, depending
on what we mean by 'peer'?"**

---

## Quick start

1. Open the **Peer Search** tab and click **Run search**. You'll see
   the 20 schools most similar to Holy Cross under the default
   (Balanced) settings.
2. Change the **Theme weight preset** dropdown — try "Athletics-active"
   or "Aid-heavy". The peer list re-ranks around the new emphasis.
3. Click any peer row to open **Side-by-Side**, or switch to **Trends**
   to see how one variable has moved over time.

Everything else is refinements on those three actions.

---

## Choosing a lens: the theme weight presets

Different constituencies on campus see Holy Cross differently. The
preset dropdown packages several common lenses:

| Preset | Best for | Peers surface |
|---|---|---|
| **Balanced** | Default IR/benchmarking view | Small selective LACs |
| **Selectivity** | Enrollment strategy | Schools we compete with for applicants |
| **Outcomes** | Academic leadership | Elite grad-rate LACs |
| **Aid** | Financial aid office | Access/affordability-focused schools |
| **Athletics-active** | Athletics department | Similar athletic-tier institutions |
| **Research-focused** | Research strategy | Well-endowed peer institutions |
| **Student body** | Enrollment management | Similar demographic composition |
| **Affordability** | Finance office | Cost + fiscal capacity peers |

Each preset shifts a handful of the eight theme sliders. You can also
adjust the sliders directly or click **Customize variables** to weight
individual metrics.

**Filters vs. weights** — filters (Religious Tradition, US News class,
state, sector) narrow *who's in the pool*. Weights control *how they're
ranked* within that pool. To find "Catholic peers with similar
athletics," combine the Athletics-active preset with the Roman Catholic
filter — Villanova, Boston College, Providence, and Stonehill jump to
the top.

---

## The tabs

### Peer Search
Set an anchor, choose a lens (via preset or sliders), narrow the pool
if you want, click **Run search**. The main panel shows:
- **Top peers table** — rank, name, US News/WaMo/Forbes ranks,
  distance. Click any row to load it into Side-by-Side.
- **Map** — anchor and peers plotted on a US map. Color and size scale
  with rank: darkest/largest at the top, lightest at the bottom.
- **Diagnostics** — which variables drove the result, what got dropped.
- **Refine (Aspirant peers)** — narrow the found peers to schools that
  beat the anchor on chosen growth metrics (grad rate, endowment, etc.).
- **Expand (Stratified search)** — re-run the search within each US News
  classification or Carnegie category to see the closest peer in each.

### Side-by-Side
Pick an anchor and one peer. See every variable in the app compared
head-to-head, with a small distribution bar showing where each school
sits in the pool. Click any variable for a fuller chart and its
definition.

### Trends
Pick a school, a variable, and a comparison group. See the school's
year-over-year line against the comparison group's interquartile band.
The pill above the chart names the exact comparison group and its size.

### Variables
A searchable browser of every variable in the app. Filter by category
or source; click any variable for its definition, format, source, and
coverage.

### Saved Searches
Every search you saved with **Save this search**. Persists across
sessions, shared across everyone using this deployment. View, rename,
download, or delete any saved search.

---

## Methodology (short version)

- Each school becomes a point in a many-dimensional space (one
  dimension per variable).
- Each variable is z-scored within the candidate pool so dollars,
  percentages, and counts are comparable.
- A handful of skewed variables (endowments, enrollment counts) are
  log-transformed first.
- The distance from the anchor to each candidate is computed dimension
  by dimension, with weights driven by your theme choices.
- Variables with less than 70% coverage in the pool, or where the
  anchor has no value, are dropped from that search.

**Distance metric.** Default is weighted Euclidean — the standard IR
peer-search metric. Mahalanobis is available in the sidebar Advanced
panel for a "second opinion" pattern-based view; see the sidebar
callout for when to use each. To see both metrics side by side, use
the **Compare Metrics** sub-tab in the results tab strip after running
a search.

---

## Data sources

| Source | What it provides |
|---|---|
| **IPEDS** | Enrollment, admissions, finance, graduation rates, aid, classifications (5-year panel through 2024-25) |
| **Carnegie 2025** | Institutional classifications and HERD research expenditures |
| **College Scorecard** | Median earnings, loan repayment rate |
| **Common Data Set** (via US News Academic Insights) | Need met, top-10% of HS class, residential share, class-size shares |
| **US News, Washington Monthly, Forbes** | Rankings (2025 releases) |
| **EADA + Wikipedia** | Athletics division, conference, varsity sports, athlete counts |

For per-variable detail — exact source, format, and coverage — see the
**Variables** tab.

---

## Glossary

- **Anchor** — the school you're searching from. Defaults to Holy Cross.
- **Peer** — an institution similar to the anchor on the dimensions
  chosen for a particular search.
- **Aspirant peer** — an institution similar to the anchor in context
  but better than the anchor on chosen growth metrics.
- **Ranked universe** — the app's fixed population: ~1,460 four-year
  non-profits that US News publishes a numeric rank for. Specialty
  schools (art, music, military academies), very small institutions,
  and unranked schools are excluded.
- **Theme** — a grouping of related variables (Size, Outcomes, Aid,
  etc.). Theme weights control how much each grouping contributes.
- **Coverage** — the share of the candidate pool that has a value for
  a given variable. Variables below 70% coverage drop out of the
  distance calculation.
