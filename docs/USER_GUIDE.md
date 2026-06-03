# Peer Schools Explorer — User Guide

A tool for finding, comparing, and curating institutional peers for the
College of the Holy Cross. Built for the Institutional Research office
and the colleagues, accreditors, and stakeholders who consume our peer
analyses.

---

## What this app does, in one paragraph

You give the app a "home" institution (the **anchor**), and it returns
the institutions most similar to that anchor on the dimensions you
choose — size, selectivity, outcomes, finance, faculty resources, and
student composition. Beyond that core peer search, the app helps you
compare two schools side by side, inspect a single school's trajectory
over time, curate a hand-picked cohort (for accreditation work, for
example), and identify "aspirant" peers — schools you'd like to grow
toward on specific metrics. The default anchor is Holy Cross; you can
change it on every tab.

---

## Quick start (about three clicks)

1. Open the **Peer Search** tab. Click **Run search**. You'll see the top
   20 institutions most similar to Holy Cross under the default
   methodology.
2. Click any row in the results table. The app remembers your selection.
   Switch to **Side-by-Side**. The chosen peer is already loaded — you'll
   see Holy Cross next to that institution across every available variable.
3. Switch to **Trends**. Pick a variable like *6-year graduation rate*.
   You'll see Holy Cross's year-over-year line plotted against the peer
   set's interquartile band.

That's the loop. Everything else is variations on those three actions
for different questions.

---

## The tabs

### Peer Search

> **What it answers:** "Which institutions, in our judgment of what
> matters, look most like the anchor — and of those, which ones beat us
> on growth metrics, and how do they break down across institutional
> categories?"

The headline tab. You set an **anchor school**, define a **candidate
pool** (the universe to search within), and adjust **theme weights** that
control how much each dimension matters. The app ranks every candidate
by similarity to the anchor, then offers two follow-up refinements right
below the result.

**What's on screen.** The left sidebar holds all the controls. Anchor
at the top, then pool filters (ranked universe, US News classification,
sector, state/region, religious affiliation), then theme weight sliders,
then output settings (number of peers to return). Click **Run search**.
The main panel shows:

1. **Summary header + top peers table.** The closest K peers, sorted by
   similarity. Click any row to load that institution into Side-by-Side.
2. **Diagnostics accordion.** Which variables drove the result, what
   got dropped by coverage, what got dropped because the anchor had no
   value.
3. **Refine: aspirant peers.** Pick one or more metrics from the
   *Aspire higher on* dropdown (acceptance rate, grad rate, endowment
   per FTE, etc., with direction baked in). The app filters the top K
   peers to schools that beat the anchor on every chosen metric
   (**strict aspirants**) and schools that beat it on all but one
   (**near-miss**). Click any row to open the per-metric **Aspirational
   gap** modal. The filter runs on the just-found peer set — fast and
   tied to the search you're already looking at.
4. **Expand search into other groups.** Pick a stratification
   dimension (US News classification, Carnegie Research Activity,
   Region, Sector, etc.) and the app runs a separate peer search per
   value of that dimension, using the same anchor + theme weights. Get
   "who's HC's closest LAC, closest R1, closest regional university"
   in one view without reconfiguring anything.

**Quick tips.** The pool filters do most of the work — if you want to
compare only against private liberal arts colleges, narrow the pool
before adjusting weights. The theme weights all default to 1.0 (equal
across themes); Athletics defaults to 0. Click any peer row to load
that school into the Side-by-Side tab. The refine and expand sections
appear only after you've run a search.

### Side-by-Side

> **What it answers:** "How does the anchor compare to *one specific*
> peer across every variable we have?"

Pick an anchor and a peer. The main panel shows every variable in our
data, grouped by theme, with both schools' values, the difference, and a
small position bar showing where each school sits in the pool's
distribution. Click any variable for a richer distribution chart, the
variable's definition, and its source.

**What's on screen.** Header with both school names, an
"Institutional classifications & groupings" card with a match count
(how many classification dimensions the two schools share — US News,
Carnegie, sector, region, locale, athletics, and so on), then
theme-by-theme variable comparisons. Each variable row has the anchor's
value, the peer's value, the signed difference, and a small chart
placing both in the pool's range.

**Quick tips.** The classification card up top tells you whether two
schools are structurally comparable. If a Side-by-Side row shows a big
difference but the bar shows both schools in roughly the same percentile
of the pool, the difference may not be meaningful in context. Click any
variable to open the distribution modal — that's where the variable's
full definition and source live.

### Trends

> **What it answers:** "How has *this variable* moved over time for
> *this school*, and how does that trajectory compare to a chosen
> group?"

Pick a school, pick a variable, pick a comparison group. The chart
shows the school's line in bold purple, with a faint purple band
representing the comparison group's 25th–75th percentile range and a
dashed gray line for the group's median. Most variables in the app are
a five-year panel (2020–2024).

**Comparison groups.** Five choices:

- **Peer Search results** — the most recent peer search from the Peer
  Search tab. The dropdown shows the live count, with a clear fallback
  when no search has been run.
- **Cohort Builder cohort** — the schools currently in the cohort on
  the Cohort Builder tab. Live count included in the label.
- **Ranked universe — same US News class as anchor** — all schools in
  the ranked universe that share the anchor's US News classification.
  The default.
- **Ranked universe — same Carnegie IC** — all schools sharing the
  anchor's Carnegie 2025 institutional classification.
- **Ranked universe (all)** — every ranked four-year non-profit school.

The pill above the chart spells out exactly what comparison is active
and how many schools it contains.

**Year-by-year detail table.** Below the chart, a row per year with the
school's value, the comparison median, the comparison min/max range,
the IQR (Q1–Q3), and the school's percentile within the comparison set.

**Quick tips.** This is where you spot trends that the 5-year-mean
collapse obscures. Try *% Pell* or *% BIPOC* over time for Holy Cross
against National Liberal Arts Colleges; the trajectory of each is more
interesting than any single year's value.

### Cohort Builder

> **What it answers:** "Given an accreditor-supplied (or hand-built)
> peer cohort, how does it actually look, and what would I change?"

Pre-loaded with the NECHE-recommended peer set for Holy Cross. The main
view is a two-column table: **In Cohort** on the left (Anchor + Keep +
Maybe + Proposed), **Out / Considering** on the right (Remove +
Possible). Each row has a status badge (color-coded) and a one-click
arrow to move the school between sides.

**Below the table:** a dashboard of eleven stat cards showing the
cohort's distribution on key metrics against the ranked universe (click
a card for a description and per-school detail), a variable inspector
for deep dives on any single variable, and an export button (in the
sidebar) that downloads the cohort plus a codebook plus a README as a
single zip.

**Status vocabulary.**

- **Anchor** — the home institution. Read-only.
- **Keep** — recommended peer that we'd keep.
- **Maybe** — recommended peer we're undecided on.
- **Remove** — recommended peer we're flagging for replacement.
- **Proposed** — additional school we want to add to the cohort.
- **Possible** — brainstormed candidate, not yet committed.

Use the **→** arrow to send a school from In to Out, **←** to bring one
back. The × on additions deletes the row entirely.

### When to use which tab

- Use **Peer Search** when the question is "who are our peers?" Drop
  into the Refine section right below the result to ask "of those, who
  are we trying to become?" The Expand section answers "what about
  peers in other categories?"
- Use **Side-by-Side** when you have two specific institutions and want
  the full variable-by-variable comparison.
- Use **Trends** when the question is "how are *we* doing on a specific
  metric, over time?"
- Use **Cohort Builder** when an external party (NECHE, a board, an
  accreditor) has handed you a list and you need to assess it.

### Variables

A native, searchable browser of every variable the app exposes. Filter
by category or by source. Click any variable for its full definition,
the format, the source, and methodological notes. Useful when reading a
Side-by-Side or a Trends chart and wondering "what exactly does this
measure?"

### Saved Searches

Every search you saved with the *Save this search* button. Each record
includes the anchor, the candidate pool, the theme weights, the distance
metric, who saved it, when, and the resulting peer list as it was when
saved. Per-card actions: **View** (loads the saved configuration into
Peer Search), **Rename**, **Download** (zip bundle), **Delete** (asks
for confirmation).

**Saved searches persist across sessions.** They live in a shared store
on the server, so closing the browser or restarting the app doesn't
lose them. Everyone using this deployment sees the same list, with
*saved by* attribution on each card.

### Help

You're reading it. The Help tab renders this guide in the app so it's
always one click away.

---

## Methodology, in plain language

The peer ranking uses **weighted Euclidean distance**: each school
becomes a point in a multi-dimensional space (one dimension per
variable), each variable is z-scored within the candidate pool so
dollars and percentages and counts are on the same scale, a handful of
heavily-skewed variables (endowments, enrollment counts) are
log-transformed first so the heavy tails don't dominate, and the
distance from the anchor to each candidate is computed dimension by
dimension. Per-variable weights are derived from the **theme weights**
you set in the sidebar.

**Themes.** Variables are grouped into themes you can re-weight:
**Scale** (enrollment counts), **Selectivity** (admit and yield rates),
**Resources** (faculty, instruction spending), **Finance** (endowment,
expenses, research), **Outcomes** (graduation rates, earnings,
repayment), **Aid** (Pell, institutional grants, net price),
**Composition** (Pell, first-generation, racial composition), and
**Athletics** (intensity, breadth, multi-sport culture). Athletics
defaults to weight 0 (opt-in).

**Coverage and missingness.** Variables with less than 70% coverage
within the candidate pool are dropped from the distance calculation for
that search. Variables for which the anchor has no value are also
dropped. The diagnostics panel under the peer table shows what was
used, what was dropped, and why.

**What this methodology doesn't do.** It doesn't pick variables for you
based on what "clusters" in the data. We tested that approach and found
it produces a finance-dominated peer set that doesn't reflect the
institutional-character similarity the IR office actually wants. The
equal-by-default theme weights are a deliberate methodological choice,
not a missing optimization.

---

## Data sources

| Source | What it provides | Vintage |
|---|---|---|
| **IPEDS** (HD, ADM, EF, SFA, OUT, FIN tables) | Most of the data: enrollment, admissions, finance, graduation rates, aid, classifications | 5-year panel, 2020–2024 |
| **Carnegie 2025 Public Data File** | Institutional classifications and HERD research expenditures | 2025 release |
| **College Scorecard** | 6- and 10-year median earnings, loan repayment rate | Most recent release |
| **Common Data Set** | Percent of need met, percent of need fully met | Most recent academic year reported |
| **EADA** (Equity in Athletics Disclosure Act) | Athletics: sponsoring body, division, conference, varsity sports, athlete counts | 2024–25 |
| **Wikipedia** (institution lists) | Conference assignments (matched to EADA UnitIDs) | Refreshed annually |

For per-variable detail — exact source, format, methodological notes,
and coverage — see the **Variables** tab.

---

## Glossary

- **Anchor** — the school you're searching from. Defaults to Holy Cross.
  Every tab has its own anchor picker.
- **Peer** — an institution similar to the anchor on the dimensions
  chosen for a particular search.
- **Cohort** — a curated set of peers, typically an accreditor's
  recommended set plus your own adjustments. Lives on the Cohort
  Builder tab.
- **Aspirant peer** — an institution similar to the anchor in context
  (size, sector, classification) but better than the anchor on chosen
  growth metrics.
- **Ranked universe** — the app's default population of ~1,233
  four-year non-profit institutions that meet IPEDS reporting and
  Carnegie classification thresholds. Excludes very small,
  non-degree-granting, or data-thin institutions.
- **In-cohort** — the schools in the Cohort Builder's left column:
  Anchor + Keep + Maybe + Proposed. Used by the variable inspector and
  the dashboard cards.
- **IQR ribbon** — the faint purple band on the Trends chart.
  Represents the 25th–75th percentile of the comparison group at each
  year.
- **Coverage** — the share of the candidate pool that has a value for a
  given variable. Variables below 70% coverage drop out of the distance.
- **Theme** — a grouping of variables (Scale, Outcomes, Aid, and so
  on). Theme weights control how much each grouping contributes to the
  distance calculation.
- **Strict aspirant** — a school that beats the anchor on every
  aspirational metric chosen.
- **Near-miss aspirant** — a school that beats the anchor on all but
  one aspirational metric.
