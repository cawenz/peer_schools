# Peer Schools Explorer — User Guide

A tool for finding, comparing, and curating institutional peers for the
any US College or University. 
---

## What this app does

You give the app an "anchor" institution, and it returns
the schools most similar on the dimensions you
choose: size, selectivity, outcomes, finance, faculty resources,
student body and athletics. Beyond that core peer search, the app helps you
compare two schools side by side, inspect a single school's trajectory
over time and identify "aspirant" peers: schools you'd like to grow
toward on specific metrics. The default anchor is Holy Cross; you can
change it on every tab.

---

## Quick start (about three clicks)

1. Open the **Peer Search** tab. Click **Run search** at the bottom of the sidebar. You'll see the top
   20 institutions most similar to your Anchor institution under the default
   methodology.
2. Click any row in the results table. The app remembers your selection.
   Switch to **Side-by-Side**. The chosen peer is already loaded and you'll
   see your anchor school next to that institution across every available variable. Click the graph icon to view the data for a variable in depth.
3. Switch to **Trends**. Pick a variable like *6-year graduation rate*.
   You'll see Holy Cross's year-over-year line plotted against the peer
   set's interquartile band.

That's the core functionality; everything else is variations on those three actions
for different questions.

---

## The tabs

### Peer Search

> **What questions the app answers:** "Which institutions, in our judgment of what
> matters, look most like the anchor. Of those institutions, which ones beat us
> across various metrics, and how do they break down across institutional
> categories?"

You set an **anchor school**, define a **candidate
pool** (the universe to search within), and adjust **theme weights** that
control how much each dimension matters. The app ranks every candidate
by similarity to the anchor, then offers two follow-up refinements right
below the result.

**What's on screen.** The left sidebar holds all the controls. Anchor
at the top, then comparison pool filters (ranked universe, US News classification,
sector, state/region, religious affiliation), then theme weight sliders,
then output settings (number of peers to return). You also have the option to individually
weight every possible clustering variable by clicking "Customize variables" below the weight sliders.

Click **Run search**.
The main panel shows:

1. **Summary header + top peers table.** The closest K peers (set by the user), sorted by
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
   gap** modal. The filter runs on the just-found peer set so it is fast and
   tied to the search you're already looking at.
4. **Expand search into other groups.** Pick a stratification
   dimension (US News classification, Carnegie Research Activity,
   Region, Public/Private, etc.) and the app runs a separate peer search per
   value of that dimension, using the same anchor and theme weights. Get
   "who's the anchor's closest LAC, closest R1, closest regional university"
   in one view without re-configuring anything.

**Quick tips.** The pool filters do most of the work: if you want to
compare only against private liberal arts colleges, narrow the pool
before adjusting weights. The theme weights all default to 1.0 (equal
across themes). Click any peer row to load that school into the Side-by-Side tab. The refine and expand sections
appear only after you've run a search.

### Side-by-Side

> **What it answers:** "How does the anchor compare to *one specific*
> peer across every variable we can use to find peers?"

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
variable to open the distribution modal: that's where the variable's
full definition and source live.

### Trends

> **What it answers:** "How has *this variable* moved over time for
> *this school*, and how does that trajectory compare to a chosen
> group?"

Pick a school, pick a variable, pick a comparison group. The chart
shows the school's line in bold purple, with a faint purple band
representing the comparison group's 25th–75th percentile range and a
dashed gray line for the group's median. Most variables in the app are
a five-year panel (2020-21 to 2024-25).

**Comparison groups.** Four choices:

- **Peer Search results** — the most recent peer search from the Peer
  Search tab. The dropdown shows the live count, with a clear fallback
  when no search has been run.
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
collapse obscures. Try *% Pell* or *% BIPOC* or *Acceptance rate* over time for Holy Cross
against National Liberal Arts Colleges; the trajectory of each is more
interesting than any single year's value.

### When to use which tab

- Use **Peer Search** when the question is "who are our peers?" Drop
  into the Refine section right below the result to ask "of those, who
  are we trying to become more like?" The Expand section answers "what about
  peers in other categories?"
- Use **Side-by-Side** when you have two specific institutions and want
  the full variable-by-variable comparison.
- Use **Trends** when the question is "how are *we* doing on a specific
  metric, over time?"

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
---

## Methodology

The peer ranking uses **weighted Euclidean distance**: each school
becomes a point in a multi-dimensional space (one dimension per
variable), each variable is z-scored within the candidate pool so
dollars and percentages and counts are on the same scale, a handful of
heavily-skewed variables (endowments, enrollment counts) are
log-transformed first so the heavy tails in the data don't dominate the distance calculations, and the
distance from the anchor to each candidate is computed dimension by
dimension. Per-variable weights are derived from the **theme weights**
you set in the sidebar.

**Themes.** Variables are grouped into themes you can re-weight:
**Size** (enrollment counts), **Selectivity** (admit and yield rates),
**Resources** (faculty, instruction spending), **Finance** (endowment,
expenses, research), **Outcomes** (graduation rates, earnings,
repayment), **Aid** (Pell, institutional grants, net price),
**Student body** (race, age, first-gen, family income, undergrad share,
residential share, religious-tradition match), and **Athletics**
(intensity, breadth, multi-sport culture).

**Coverage and missingness.** Variables with less than 70% coverage
within the candidate pool are dropped from the distance calculation for
that search. Variables for which the anchor has no value are also
dropped. The diagnostics panel under the peer table shows what was
used, what was dropped, and why.

**What this methodology doesn't do.** It doesn't pick variables for you
based on what variables result in natural "clusters" in the data. We tested that approach and found
it produces a finance-dominated peer set that doesn't reflect the
institutional-character similarity we would want. 

---

## Which distance metric should I use?

The app offers two distance metrics. They answer different questions
about "similar." Most users should default to **Euclidean**.

### Euclidean distance — the standard IR peer-search metric

Euclidean is what almost every IPEDS comparison group, accreditation
peer set, and budget benchmarking analysis uses. It treats each
variable as an independent dimension and asks:

> Which schools are close to the anchor on each variable separately,
> weighted by the importance I've assigned each theme?

If you boost the **Outcomes** slider, Euclidean will draw schools with
similar grad rates, retention, and earnings closer. Your theme weights
have real, predictable effects on the ranking.

**Use Euclidean when:**

- You want the peer set for benchmarking specific operational metrics
  (cost per FTE, faculty salaries, ratios)
- You're producing a peer group for accreditation, NECHE, board
  presentations, IPEDS comparison reports
- You want your theme-weight choices to drive the ranking

### Mahalanobis distance — the "institutional pattern" metric

Mahalanobis is more sophisticated mathematically. It de-correlates the
variables before measuring distance, so instead of treating each
variable independently, it asks:

> Which schools share the underlying institutional pattern that the
> anchor fits into?

It's good at recognising archetypes: "selective Catholic D-I Northeast
LACs," "large urban research universities," "small rural Master's
institutions." Schools that share the anchor's archetype cluster
together even when individual variables differ.

**Important caveat — theme weights don't actually affect Mahalanobis
rankings.** This is a property of how the metric works mathematically
(it's *scale-invariant*: the math cancels out any pre-scaling you apply
to the variables). The theme-weight sliders still let you *include* or
*exclude* themes (zero excludes), but moving a slider from 1.0 to 2.5
doesn't change what Mahalanobis ranks first. If you want your weight
choices to matter, use Euclidean.

**Use Mahalanobis when:**

- You want a "second opinion" on whether a peer set you've already
  built (with Euclidean) holds up under a different lens
- You're exploring institutional archetype — "schools that share our
  *character* in some intuitive sense"
- You're deliberately looking for schools that share the anchor's
  *correlated* patterns across variable bundles

### What if the two metrics disagree?

That's the most informative result. When Euclidean and Mahalanobis
produce overlapping top-K lists, you have high-confidence peers — they
match on individual benchmarks AND share the institutional pattern.
When the two disagree, the overlap is your **robust peer set**, and
the schools that appear in only one list tell you something:

- In Euclidean only → similar on the specific dimensions you weighted,
  even if not pattern-matched
- In Mahalanobis only → archetypal peers (share your overall
  institutional character) that happen to differ on some specific
  measures

The "Compare Metrics" tab below the peer table (when results exist)
runs both metrics with your current settings and shows the top-K under
each side by side.

### Practical tips

- **Start with Euclidean.** It's the standard, your theme weights work
  the way you'd expect, and the result is interpretable.
- **If Euclidean's results feel off**, before switching to Mahalanobis,
  try **narrowing the candidate pool**. Pool filters (US News class,
  religious tradition, region) often shift the ranking more than weight
  sliders do.
- **Use the Diagnostics tab** to see which variables were dropped from
  the calculation and why. If a variable you care about isn't in the
  "Variables used" list, the coverage threshold (default 70%) may have
  excluded it for this pool.

---

## Data sources

| Source | What it provides | Vintage |
|---|---|---|
| **IPEDS** (HD, ADM, EF, SFA, OUT, FIN tables) | Most of the data: enrollment, admissions, finance, graduation rates, aid, classifications | 5-year panel, 2020–2024 |
| **Carnegie 2025 Public Data File** | Institutional classifications and HERD research expenditures | 2025 release |
| **College Scorecard** | 6- and 10-year median earnings, loan repayment rate | Most recent release |
| **Common Data Set** (via US News Academic Insights) | CDS-reported metrics such as percent of need met, percent of need fully met, top-10% of high-school class, early-decision detail, residential share, and class-size shares | 2025–2026 academic year |
| **Washington Monthly College Guide** | Washington Monthly rankings within the Liberal Arts, Bachelor's, Master's, and National categories (plus the Best Bang for the Buck regional lists) | 2025 release |
| **Forbes America's Top Colleges** | Forbes overall rank | 2025 release |
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
- **Aspirant peer** — an institution similar to the anchor in context
  (size, sector, classification) but better than the anchor on chosen
  growth metrics.
- **Ranked universe** — the app's fixed population: ~1,460 four-year
  non-profit institutions for which US News publishes a numeric overall
  rank. Covers National Universities, National Liberal Arts Colleges,
  Regional Universities, and Regional Colleges. Specialty schools (art,
  music, military), very small institutions, and any IPEDS institution
  US News doesn't rank are excluded from the app entirely — they
  wouldn't be meaningful peers for institutional benchmarking. Every
  search runs over this universe; sidebar filters narrow within it.
- **IQR ribbon** — the faint purple band on the Trends chart.
  Represents the 25th–75th percentile of the comparison group at each
  year.
- **Coverage** — the share of the candidate pool that has a value for a
  given variable. Variables below 70% coverage drop out of the distance calculations.
- **Theme** — a grouping of variables (Size, Outcomes, Aid, Student
  body, and so on). Theme weights control how much each grouping
  contributes to the distance calculation.
- **Strict aspirant** — a school that beats the anchor on every
  aspirational metric chosen.
- **Near-miss aspirant** — a school that beats the anchor on all but
  one aspirational metric.
