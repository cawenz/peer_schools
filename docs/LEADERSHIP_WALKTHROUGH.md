# Peer Schools Explorer — Leadership Walkthrough
*Cheat sheet for the 45-minute senior leadership talk*

---

## 1. The one-minute frame

The Peer Schools Explorer is an internal IR tool that answers a
question we've historically had to negotiate one meeting at a time:
**"Who are Holy Cross's peers?"** Different constituencies on
campus — Athletics, Enrollment, Finance, Mission, Academic Affairs —
answer that question differently and have all had to be right at once.
This tool lets each constituency see the peer set that matches *their*
question, from the same data, with defensible methodology behind it.

**Two things to say explicitly up front:**
- The methodology is standard IR practice — weighted Euclidean distance
  on z-scored institutional variables, the same approach used in NECHE
  peer sets, IPEDS comparison groups, and Moody's peer benchmarks.
- The tool doesn't pick a "correct" peer set. It surfaces the peer set
  that follows from the criteria and weights the user chooses. Different
  choices produce different peer sets — and being able to *see* that is
  the point.

---

## 2. How it works (plain-English methodology)

### The core idea
Every institution becomes a point in a high-dimensional space, with
one dimension per variable (grad rate, endowment per FTE, admit rate,
athletics division, etc.). The "distance" between two schools in this
space is how different they are. Peers are the schools closest to the
anchor.

### The two mechanical steps that make it work
1. **Z-scoring within the candidate pool.** Dollars, percentages, and
   student counts are all on different scales. Before we can compute
   distance across them, each variable is standardized so a value of
   "1" always means "one standard deviation above the average." That
   way endowment size (millions of dollars) and acceptance rate (a
   percent) contribute comparably.
2. **Weighted distance.** Each variable's contribution to the distance
   is scaled by its theme's weight. Boost Athletics, and athletics
   variables count more; zero out Aid, and aid variables drop out
   entirely. This is how the preset dropdown works — it just packages
   common weight configurations.

### The two distance metrics

**Euclidean distance** (the default) — the standard IR peer-search
metric. It asks: *"Which schools are close to the anchor on each
variable separately, weighted by the themes I care about?"* This is
what NECHE peer sets and IPEDS comparison groups use. Your theme
weights have direct, predictable effects. **Use Euclidean when you're
producing a peer set for benchmarking, accreditation, board reports,
or IPEDS comparison work.**

**Mahalanobis distance** — a more sophisticated approach that
*de-correlates* variables before measuring distance. Instead of
treating each variable independently, it asks: *"Which schools share
the underlying institutional pattern the anchor fits into?"* It's
good at recognizing archetypes ("selective Catholic D-I Northeast
LACs," for example) and will find schools that share Holy Cross's
overall character even when specific numbers differ.

**One important caveat about Mahalanobis:** theme weights don't
actually affect Mahalanobis rankings — the math is *scale-invariant*.
Sliders let you include or exclude themes, but 2.5× doesn't change the
rank. If you want weight choices to drive the result, use Euclidean.

### Using them in tandem — the most valuable pattern
When Euclidean and Mahalanobis produce overlapping top-K lists, you
have **high-confidence peers** — they match both on individual
benchmarks *and* share the institutional pattern. When they disagree,
the overlap is your *robust peer set*. The **Compare Metrics** sub-tab
in the results shows both side by side. For Holy Cross at K=40, the
overlap is 18 schools — those 18 are the strongest defense for any
peer list we publish because two methodologically independent views
of similarity both endorse them.

---

## 3. What variables and data go in

### 47 clustering variables, 8 themes

| Theme | Count | What it captures |
|---|---|---|
| **Student body** | 9 | Race, first-gen, family income, part-time, residential, international, transfer-in |
| **Aid** | 8 | Net price, Pell, institutional discount rate, loans, need met |
| **Outcomes** | 7 | 6-yr grad rate, retention, transfer-out, earnings 10yr, loan repayment, Pell-grad gap |
| **Resources** | 7 | Faculty ratios/salary, instruction/academic support/student services spending per FTE |
| **Selectivity** | 6 | Acceptance rate, yield, application volume, SAT/ACT submission rates, top-10% HS |
| **Finance** | 5 | Endowment per FTE, operating margin, published tuition, tuition-share, core expenses |
| **Athletics** | 3 | Division (D-I/II/III/NAIA), athletes as % of UG, multi-sport ratio |
| **Size** | 2 | Undergraduate enrollment, UG share of total |

### 16-variable curated set for Mahalanobis
The Mahalanobis compact set is a smaller, orthogonally-chosen subset
that keeps the math numerically stable. If someone asks *"why fewer
variables?"*: Mahalanobis is mathematically sensitive to highly
correlated inputs (the condition number blows up), so we curate a set
that's carefully spread across all 8 themes without correlated
duplicates.

The 16: `undergraduate_enrollment`, `acceptance_rate`, `yield_rate`,
`pct_pell`, `avg_net_price_aided`, `student_faculty_ratio`,
`avg_ft_faculty_salary`, `endowment_per_fte`,
`published_tuition_fees`, `grad_rate_6yr`, `retention_rate`,
`median_earnings_10yr`, `pct_bipoc`, `pct_first_generation`,
`pct_part_time`, `athletics_division_numeric`.

### Data sources

| Source | What it provides |
|---|---|
| **IPEDS** (HD, ADM, EF, SFA, F, GR, OM tables) | The backbone — enrollment, admissions, finance, aid, graduation rates, classifications. 5-year panel through 2024-25 |
| **Common Data Set** (via US News Academic Insights) | CDS-specific detail we can't get from IPEDS: percent of need met, top-10% of HS class, residential share, class-size distribution |
| **College Scorecard** | Median earnings 10 years after entry, loan repayment rate |
| **Carnegie 2025** | Institutional classifications + HERD research expenditures |
| **US News, Washington Monthly, Forbes** | Published rankings (2025 releases) |
| **EADA + Wikipedia scraper** | Athletics: division, conference, varsity sport counts, athlete counts |

The tool restricts the universe to **~1,460 US News–ranked four-year
non-profits** across the four ranked categories. Specialty schools
(art/music/military academies), very small institutions, and for-profits
are excluded from the app entirely — they wouldn't be meaningful peers
for institutional benchmarking.

---

## 4. Suggested 45-minute walkthrough

Timing is a guide; adjust to the room. Total live-demo time is ~25 min;
the rest is framing + Q&A.

### Act 0 — Frame the problem (3 min, no app)
> "Every year we get asked for a peer list. What that list contains
> depends on who's asking. Athletics needs one thing, Enrollment
> another, the Advancement office a third. This tool doesn't try to
> settle that — it lets each of those conversations happen from the
> same data with defensible methodology behind whichever view."

Cover the two "up front" points from section 1.

### Act 1 — The default view (3 min)
Open the app. Anchor is Holy Cross by default; Balanced preset is on.
Click **Run search**.

**Talking points:**
- 20 peers returned, sorted by similarity
- The top of the list should be recognizable (Lafayette, Bucknell,
  Trinity, F&M, Union) — that's the "standard IR peer set" from
  weighted Euclidean over all 47 variables at equal theme weights
- Point at the **map** tab — closer peers are darker/larger; the
  geographic clustering in the Northeast is visible immediately
- Point at the **Diagnostics** sub-tab — this is where the
  methodology lives if anyone wants to audit

### Act 2 — Shifting the lens with presets (5-6 min)
Switch to **Athletics-active** preset. Re-run.

**Talking points:**
- 4 of 20 peers overlap with Balanced — this is a *transformative*
  shift, not a rearrangement
- New peers: Lafayette, Grove City, Colgate, Bucknell, Hillsdale,
  Davidson — mid-size institutions with similar DI-tier athletic profile
- Note that Villanova/Stonehill/Saint Anselm are also in the top 20
  (rank ~15-19), which sets up Act 3

Switch to **Outcomes** preset. Re-run.
- Now it's Wellesley, Williams, Bowdoin, Bates, Wesleyan — the elite
  grad-rate LACs. Same anchor, same universe, completely different lens.

Switch to **Aid** preset. Re-run.
- Harvey Mudd, Mount Holyoke, Smith, Reed — access/affordability-focused
  schools

> *"Each preset packages a different question about what 'peer' means.
> You can also move sliders individually or click Customize variables
> for full manual control."*

### Act 3 — Combining weights and filters (4 min)
Go back to **Athletics-active** preset. Now in the sidebar, set the
Religious Tradition filter to Roman Catholic. Re-run.

**Talking points:**
- Villanova, Boston College, Providence, Stonehill, Saint Anselm now
  dominate the top of the list
- **This is the key mental model:** *weights answer "who's similar on
  the dimension I care about?"* while *filters answer "who's similar
  AND matches this specific attribute?"* Combining them is how you
  answer complex questions like "who are our Catholic athletic peers?"
- Any classification-style attribute can be a filter: US News class,
  sector, state/region, religious tradition

### Act 4 — The robust peer set: Compare Metrics (5-6 min)
Switch back to Balanced, K=40, re-run. Open the **Compare Metrics**
sub-tab (it's in the results tab strip, between Refine: Stratified
and Diagnostics).

**Talking points:**
- Left column: Euclidean top-40. Right column: Mahalanobis top-40.
- 18 schools appear in **both** lists — those are the schools we can
  most defend as peers. Two methodologically independent views of
  similarity converge on them.
- The 22 unique to each side tell you something too:
  - **Euclidean-only** peers (Middlebury, Reed, Scripps, Colby,
    Wesleyan…) — highly selective LACs Holy Cross benchmarks against
    on individual metrics
  - **Mahalanobis-only** peers (Villanova, BC, Notre Dame, Providence,
    Stonehill…) — schools that share Holy Cross's *overall
    institutional pattern* — mid-size, DI athletics, Catholic identity,
    professional-program orientation
- The Mahalanobis-only list is the answer to *"who competes with us
  for students, hires from the same markets, shares our DNA?"*

### Act 5 — Deep dive (4-5 min)
Click any peer row (e.g., **Bucknell**) to open **Side-by-Side**.

**Talking points:**
- Every variable in the app, head to head, with distribution bars
  showing where each school sits in the pool
- Match count at top ("classifications & groupings") — a shorthand for
  structural comparability
- Click a variable for a full distribution chart + definition +
  source

Switch to **Trends** tab. Anchor on Holy Cross, pick a variable
(*% Pell* or *acceptance rate*), comparison = *Peer Search results*.
- Time series against the peer set's IQR band
- Where the pill above the chart names the comparison
- Where a trend can matter more than a single-year value

### Act 6 — Wrap (2-3 min)
Point out:
- **Variables tab** — searchable browser of every variable with
  definitions and sources
- **Saved Searches** — every search anyone runs can be saved,
  persists across sessions, shared across the deployment
- **Help tab** — plain-English guide, refreshed for this rollout

---

## 5. Anticipated Q&A prep

**Q: "Why isn't Georgetown / Notre Dame / [famous Catholic university]
a peer under the default view?"**
A: Under Balanced they're not, because they're much larger and more
research-heavy than Holy Cross. Under Mahalanobis (which recognizes
institutional pattern rather than variable-by-variable similarity)
they *do* appear — Notre Dame is in the Mahalanobis top-40. That's a
strong example of why the two-metric view is more informative than
either alone.

**Q: "Why does Grove City / Hillsdale / [conservative Christian
college] surface under Athletics-active?"**
A: They match Holy Cross on mid-size, similar athletic-program breadth,
and similar demographic composition (which is what the Athletics-active
preset's context themes measure). They aren't Catholic, but the
preset isn't filtering for religion — it's finding athletic-tier
peers. Adding the Religious Tradition filter re-focuses on Catholic
institutions, which shifts Villanova/BC/Providence to the top.

**Q: "How often is the data updated?"**
A: IPEDS follows a fall cohort cycle — 2024-25 is the most recent
vintage, containing admissions for the fall 2024 entering class.
Cost/finance data lags by ~12 months. The rankings (USN, WaMo,
Forbes) are the 2025 releases. We refresh annually.

**Q: "Is this the official Holy Cross peer set?"**
A: No — and that's deliberate. The point of the tool is that different
questions produce different peer sets, all defensibly. When we need
*one* peer set for a specific external purpose (NECHE report, an IPEDS
comparison, an aspirant list for an initiative), we build it here with
the appropriate lens and save it. Saved Searches is where those live.

**Q: "How is this different from just using the US News peer set?"**
A: US News assigns each school to a classification (National LAC,
National University, Regional…). Within a classification, all schools
look identical to US News. This tool measures actual similarity across
50+ variables — so within the "National LAC" bucket, we can distinguish
who's genuinely closest to Holy Cross on selectivity, on finance, on
outcomes.

**Q: "Can non-IR people use this?"**
A: Yes — that's the design goal. The preset dropdown lets anyone try
different lenses without needing to understand what any individual
variable does. The Diagnostics sub-tab is there for anyone who wants
to audit, but no one has to look at it to get a usable peer set.

**Q: "What about aspirant peers — schools we want to *become* like?"**
A: The **Refine: Aspirant** sub-tab in the results. After a search,
pick metrics you want to grow on (endowment per FTE, grad rate, etc.),
and the tool filters your peer set to just the schools that beat Holy
Cross on those chosen dimensions. Two levels: strict aspirants (beat
us on *all* chosen metrics) and near-miss (all-but-one).

**Q: "Who else can use this?"**
A: It's deployed on our internal server; access is by URL. Every user
sees the same data and can save searches under their own name. Saved
searches show who saved them so we can track how the tool is being
used across offices.

---

## 6. If the demo goes off the rails

**The app is slow to load:** first search after app restart takes a few
seconds. Subsequent searches are near-instant. Have a backup screenshot
of a completed search ready.

**A preset produces an "unexpected" peer:** Grove City, Hillsdale,
service academies, RISD — these can surface under specific lenses and
they're not wrong, they're just surprising. The honest answer is
*"the preset is finding schools that share these specific dimensions;
if that surprises us, it's telling us something about which schools
have surprisingly similar numeric profiles."*

**Someone asks about a metric that's dropped:** the coverage threshold
is 70% within the candidate pool. If a variable doesn't cover enough
schools in the pool, it drops out to keep the distance calculation
comparable. The Diagnostics sub-tab lists exactly what dropped and why.

**Someone asks "who built this and why should we trust the math?"**
It's built on standard IR methodology (weighted Euclidean, z-scoring
within pool) — the same approach in Moody's peer benchmarks, IPEDS
comparison groups, and NECHE peer selection. The variable choice was
audited for redundancy (correlations checked within themes, algebraic
identities removed). The two-metric view (Euclidean + Mahalanobis) is
a further check — a peer that appears in both is one two independent
methods endorse.
