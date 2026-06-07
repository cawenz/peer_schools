# Project Handoff

For future Claude.ai sessions, Claude Code sessions, or human collaborators picking up this project. Read this before doing anything — it captures decisions that aren't visible in the code.

---

## What this project is

A peer-comparison data layer for the College of the Holy Cross, designed to generalize to any anchor institution. Two layers:

1. **Data layer** (5 modules): Pulls and normalizes institutional data from IPEDS, Academic Insights (CDS), College Scorecard, and Carnegie. Produces tagged facts tables that downstream applications consume.

2. **Peer-selection layer** (`peers_pipeline.R`): A configurable function that computes anchored peer rankings using weighted Euclidean (or Mahalanobis) distance over standardized, theme-normalized variables.

The data layer doesn't score, weight, or rank — it just acquires and tags. The peer-selection layer is where the analytical methodology lives.

---

## Current state

**All five modules built and producing values:**

| Module | Pipeline | Output | Vars |
|---|---|---|---|
| Aid | `aid_module_pipeline.R` | `aid_facts.csv`, `aid_variables.csv` | 11 |
| Admissions | `admissions_module_pipeline.R` | `adm_facts.csv`, `adm_variables.csv` | 11 |
| Enrollment | `enrollment_module_pipeline.R` | `enr_facts.csv`, `enr_variables.csv` | 21 |
| Outcomes | `outcomes_module_pipeline.R` | `out_facts.csv`, `out_variables.csv` | 12 |
| Finance & Resources | `finance_resources_module_pipeline.R` | `fin_facts.csv`, `fin_variables.csv` | 17 |

**Plus shared infrastructure:**
- `schools_pipeline.R` — produces `schools.csv` with one row per institution (instnm, sector, control, classification, accreditor, Carnegie attributes, religious affiliation)
- `peers_pipeline.R` — `compute_peers()` function for anchored peer ranking
- `accdb_to_rda.R` — utility for converting IPEDS .accdb files to .Rda
- `build_neche_comparison.R` — generates the NECHE peer-set comparison spreadsheet

**72 total variables** across the project: 53 tagged for clustering, 13 descriptive, 6 detail race vars (used at half weight in clustering).

**7 NECHE peer-set variables, 29 NECHE dashboard variables** distributed across the modules.

---

## Architecture conventions (locked)

**Two-table architecture per module + one shared schools table:**

- `<module>_facts.csv` — long format, one row per `unitid × year × metric × value`. Columns: `unitid, year, metric, value, var_type`. `var_type` is `raw` (direct from a source field), `computed` (derived in the pipeline), or `external` (non-IPEDS API).

- `<module>_variables.csv` — one row per metric. Columns: `metric, category, display_name, source, ipeds_table_or_formula, use_type, comparison_scope, format, neche_peer_set, neche_dashboard, coverage_note, notes`.

- `schools.csv` — one row per institution. Stable attributes used by every module.

**Variable tags:**
- `use_type`: clustering / descriptive / exploratory
- `comparison_scope`: cross_category / within_category
- `neche_peer_set`: TRUE/FALSE (the 7 NECHE algorithm variables)
- `neche_dashboard`: TRUE/FALSE (variables sharing source data with NECHE dashboard metrics; broadly interpreted)
- `format`: currency / percentage / count / ratio
- `coverage_note`: free-text caveats

**Long format is canonical.** Wide tables are constructed via `pivot_wider()` when needed; the project does not commit to any particular wide shape.

---

## Universe definition

**Universe**: IPEDS SECTOR 1 (public 4-year) + SECTOR 2 (private NFP 4-year). For-profits and 2-year institutions excluded by design. ~2,598 distinct institutions across panel years 2020-2024.

**Ranked-universe flag**: `schools.csv` carries `in_ranked_universe` (TRUE for ~1,235 schools classified by US News as National Universities, National Liberal Arts Colleges, or Regional Universities). This is the default candidate pool for peer comparison.

**Schools.csv classification simplifications:**
- Schools that changed sector/classification during the panel get the most recent value; `latest_year` records when that snapshot was taken.
- US News classification is pulled current and applied uniformly to all panel years. Documented simplification.
- Carnegie 2025 classifications are based on 2020-2023 data; applied uniformly to all panel years. Same convention.

---

## Year handling

Three different year conventions interact in this project. The pipeline reconciles them as follows:

| Source | Convention | Translation |
|---|---|---|
| IPEDS table names | Fall-year (HD2024 = 2024-25 academic year) | Canonical project year |
| IPEDS finance tables | FY-ending suffix (F2324_F1A = FY2023-24, reported in 2024-25 collection) | Pipeline computes suffix as `f_2digit(yr-1) + f_2digit(yr)` |
| Academic Insights | Spring-year +2 lead (AI year 2026 = 2025-26 academic year) | `ai_to_ipeds_year(y) = y - 2L`; `ipeds_to_ai_year(y) = y + 2L` |
| College Scorecard "latest" | Single snapshot, ~2-3 year publication lag | Written under panel year 2024 |
| Carnegie 2025 | One-time snapshot from 2020-2023 data | Written under panel year 2024 |

**The +2 AI offset was discovered mid-project** by spot-checking Holy Cross applicant counts. AI year 2022 (= 7,087) matched IPEDS year 2020 exactly, etc. All AI pulls now translate years on the way in.

**Single-snapshot variables** in the project (write under panel year 2024 only):
- Outcomes: `median_earnings_10yr`, `median_earnings_6yr`, `loan_repayment_rate`, `earnings_ratio`, `first_gen_grad_rate_6yr` (cohort-anchored, lands here in practice)
- Enrollment: `pct_first_generation`, `median_family_income`
- Finance & Resources: `herd_avg`

**Coverage reports correctly handle single-snapshot variables** — each metric is evaluated against its actual year set, not a uniform 5-year denominator. An `n_years` column makes this transparent.

---

## Rate normalization convention

**All percentage variables are stored on a 0-100 scale.** IPEDS and Academic Insights return rates as 0-100 natively. Scorecard returns rates as 0-1 decimals — build functions multiply by 100 to align.

Each Scorecard-using module's config has a `scorecard_rate_metrics` list naming which fields need the ×100 transformation. Currency and count fields are excluded.

**Currently normalized:**
- `pct_first_generation` (Enrollment, Scorecard)
- `loan_repayment_rate` (Outcomes, Scorecard)

---

## Data sources

**IPEDS** (load_ipeds via the `ipeds` R package, via the project's own `get_table()` helper that reads from `.Rda` files in `data/`). All 5 modules.

**Academic Insights** (US News CDS data via API). Used by all 5 modules for CDS-unique metrics that IPEDS doesn't collect.
- Requires `ACADEMIC_INSIGHTS_API_KEY` env variable.
- Catalog search: `search_ai_metrics(MODULE_CONFIG, contains = "keyword")` to find metric IDs.

**College Scorecard** (US Department of Education, public API). Used by Outcomes (earnings, repayment) and Enrollment (first-gen, family income).
- Requires `SCORECARD_API_KEY` env variable (get from data.gov).
- Scorecard exposes year-prefixed paths for *some* fields but not others. The project found empirically: earnings/repayment work year-versioned in principle but are framed as latest-cohort snapshots; first-gen and family income are latest-only.
- Universe is ~2,047 institutions (smaller than IPEDS's 2,598). Schools outside Scorecard return NA for Scorecard variables.

**Carnegie 2025 Public Data File** (Excel download). Used by Admissions (academic concentration), Outcomes (earnings ratio), Finance & Resources (HERD R&D average). One-time snapshot applied uniformly to all panel years.

---

## Module summaries

### Aid Module (11 variables)

IPEDS-sourced aid metrics + 2 CDS metrics. Heavy reliance on IPEDS SFA (Student Financial Aid) and DRVIC tables. Net price by income band, Pell participation, institutional grant generosity, loan exposure, need-meeting.

**One NECHE peer-set variable**: `pell_count`. Two NECHE dashboard flagged.

**Key design decisions:**
- `inst_discount_rate` uses in-state published tuition for public institutions (documented simplification).
- IPEDS aid variables describe full-time, first-time, degree-seeking undergraduates. ~16% of private NFP institutions have no entering cohort and therefore no IPEDS aid data — structural, not missing.

### Admissions Module (11 variables)

IPEDS DRVADM/ADM + 3 CDS metrics. Acceptance and yield rates, test submission rates, ED program characteristics.

**No NECHE flagged variables.** Column exists for schema consistency.

**Key design decisions:**
- **SAT/ACT mid-50% scores tagged descriptive only**, not clustering. Test-optional submission bias makes them unreliable for peer comparison. The submission rates (`pct_submitting_sat`, `pct_submitting_act`) are promoted to clustering variables in their own right.
- **Two ED variables** (`ed_acceptance_rate` + `ed_share_of_applications`) rather than one — they capture different aspects of ED programs (demand-side vs strategy-side).
- **No test-policy variable** — Academic Insights doesn't expose it; dropped rather than carried as a placeholder.
- **Year-aware ADM handling**: IPEDS ADM table reorganized during panel period (gender-only breakouts starting 2024); pipeline tries direct totals first, falls back to summing gender components.

### Enrollment Module (21 variables)

IPEDS DRVEF + 1 AI metric + 2 Scorecard metrics. Scale, composition (race/ethnicity, age, residential, first-gen), transfer-in.

**Four NECHE peer-set variables**: `total_enrollment`, `undergraduate_enrollment`, `first_time_enrollment`, `full_time_enrollment`. 14 NECHE dashboard flagged.

**Key design decisions:**
- **Three-level race/ethnicity trio** for clustering: `pct_white`, `pct_international`, `pct_bipoc`. The trio deliberately excludes "race/ethnicity unknown" from BIPOC (so high-unknown institutions aren't misclassified as BIPOC-heavy). Doesn't always sum to 100%; `pct_race_unknown` carries the remainder.
- **Detail race variables** (`pct_black`, `pct_hispanic`, `pct_asian`, `pct_nhpi`, `pct_aian`, `pct_two_or_more`) tagged descriptive but used at half weight in clustering math (in the Composition theme).
- **`pct_first_generation` pivoted from AI to Scorecard mid-project**. Diagnostic testing ruled out four AI candidates (metric 731 was out-of-panel; metric 1014 used OM cohort; metrics 1027-1029 had unclear units). Scorecard's `latest.student.share_firstgeneration` returns 16.6% for HC, which is plausible (slightly elevated vs HC's published rate due to FAFSA-filer denominator).
- **`median_family_income` added** from Scorecard alongside first-gen. Same FAFSA-filer caveat documented in coverage_note.

### Outcomes Module (12 variables)

IPEDS DRVGR/DRVOM/DRVC + 3 Scorecard metrics + 1 AI metric + 1 Carnegie.

**One NECHE peer-set variable**: `doctoral_degrees_awarded` (DOCDEGRS — research doctorates only, excludes professional-practice). Four NECHE dashboard flagged.

**Key design decisions:**
- **Pell graduation gap** computed as Pell minus non-Pell 6-year award rate from DRVOM. Negative values indicate Pell students underperform.
- **First-gen graduation rate stored as a level**, not a gap. AI exposes a first-gen rate (metric 1116) but no continuing-gen rate to subtract from. Downstream apps construct comparisons as needed.
- **Scorecard earnings and repayment are single-snapshot** under panel year 2024. The "10 years after entry" data reflects cohorts that entered ~2012. Year-to-year changes in Scorecard metrics should NOT be interpreted as recent shifts.
- **`loan_repayment_rate` field path bug**: Initial implementation used `latest.repayment.3_yr_repayment.completers` which returns a count, not a rate (HC value: 668 completers). Fixed to `latest.repayment.3_yr_repayment.completers_rate` (HC value: 0.889 → 88.9 after normalization). Documented in case future Scorecard fields need similar `.completers_rate` vs `.completers` distinction checking.
- **`earnings_ratio`** from Carnegie SAEC: actual earnings ÷ expected earnings given demographic profile. HC value 1.98 (graduates earn ~2× demographic expectation).

### Finance & Resources Module (17 variables)

IPEDS DRVF + raw F1A/F2 + S_IS + SAL_IS + 1 Carnegie + 2 CDS. Form-aware FASB/GASB handling is the central engineering challenge.

**One NECHE peer-set variable**: `herd_avg`. Nine NECHE dashboard flagged.

**Key design decisions:**
- **Form-awareness via DRVF**: Where possible, uses DRVF (derived finance) with F1*/F2* prefix selection by SECTOR. Variables without DRVF equivalent (notably net assets) fall back to raw F1A/F2 reads.
- **FASB volatility fix**: Four originally-planned variables (`tuition_dependence`, `endowment_dependence`, `total_core_revenue_per_fte`, `operating_margin_per_fte`) were dropped and replaced with stable alternatives. Pre-fix HC values swung wildly with market years (e.g., `operating_margin_per_fte` ranged +$94K to -$20K across 5 years). Replaced with expense-denominated metrics and an INVRPC-corrected operating margin.
- **`pct_faculty_full_time` dropped**: S_IS table is FT-only by IPEDS design; reconstructing FT/PT requires data not currently pulled.
- **FACSTAT codes for tenure_track_share**: Verified empirically on HC (FACSTAT 20 + 30 + 40 = 173 + 59 + 101 = 333 = FACSTAT 0).

---

## Peer-selection methodology (`peers_pipeline.R`)

The analytical heart of the project. A configurable `compute_peers()` function that produces anchored peer rankings.

### Algorithm

1. Load schools.csv and all 5 facts/variables
2. Filter to clustering variables (+ 6 detail race vars at half weight)
3. Compute 5-year average for multi-year variables; single value for snapshots
4. Apply candidate_pool filter (default: `in_ranked_universe = TRUE` → ~1,235 schools)
5. Compute per-variable coverage within the candidate pool
6. Drop variables below `coverage_threshold` (default 0.70)
7. Apply log transforms to right-skewed variables (default: 23 currency/count/scale variables)
8. Auto-normalize weights by theme (theme_weight ÷ n_vars_in_theme)
9. Standardize all variables to z-scores using candidate-pool statistics
10. Compute weighted distance (Euclidean default, Mahalanobis optional)
11. Return top-K with diagnostics

### Themes (7)

| Theme | Variables (count) | Default weight |
|---|---|---|
| Scale | 4 NECHE enrollment counts | 1.0 |
| Selectivity | 9 admissions metrics | 1.0 |
| Resources | 9 faculty/instruction metrics | 1.0 |
| Finance | 8 endowment/cost metrics | 1.0 |
| Outcomes | 12 graduation/earnings/retention metrics | 1.0 |
| Aid | 11 net price/Pell/loan metrics | 1.0 |
| Composition | 11+6 demographic/access metrics | 1.0 |

Mission attributes (sector, classification, accreditor, religious affiliation, state) are NOT in any theme. They serve as filters via `candidate_pool`, not as similarity dimensions.

### Key design decisions

- **Anchored similarity, not unsupervised clustering.** Different question — "schools like HC" vs "natural groupings in the universe."
- **Weighted Euclidean as default**, Mahalanobis as optional comparison. Empirically the two converge after pruning redundant variables (~9 variables: 3 enrollment-scale duplicates + 6 race detail). Mahalanobis often falls back to Euclidean due to covariance singularity on the full variable set; that fallback is correct behavior, not a failure mode.
- **Auto-normalize by theme** so theme weights are independent of variable count. Without this, the 4-variable Scale theme would have 1/3 the influence per variable as the 12-variable Outcomes theme.
- **70% coverage threshold within candidate pool** (not universe-wide). CDS-sourced AI variables hit ~45% universe-wide but typically clear 70% in the ranked pool because ranked schools respond to CDS at higher rates.
- **5-year averaging** for multi-year variables. Smooths year-to-year noise (especially post-COVID selectivity fluctuation).
- **Log-transform 23 right-skewed variables** before z-scoring (enrollment counts, currency, endowment, application volume). Excluded: percentages, rates, signed gaps, already-normalized ratios.
- **Pairwise NA handling**: candidates with NA for a variable that the anchor has are pairwise-dropped on that dimension. Different candidates may use slightly different variable sets.

### Empirical findings on the HC anchor

When run with default settings (Euclidean, in_ranked_universe = TRUE, all themes weight 1.0):
- **Top 20 are all selective private LACs** — mostly the institutions HC has historically benchmarked against (Lafayette, Trinity CT, Colgate, Hamilton, Davidson, Vassar, Carleton, Middlebury, Skidmore, Colby, etc.).
- **First non-LAC is Lehigh at rank 21** (small National U with strong outcomes, residential character).
- **Catholic peers (Boston College, Fairfield, Providence) appear in ranks 35-50** — notable that the methodology surfaces them via shared composition/outcomes profiles without religious affiliation as an explicit variable.
- Distance from Lafayette (rank 1) is 0.77; Colby (rank 20) is 1.48; the gradient is gradual rather than categorical.

### Religious affiliation (active)

Implemented end-to-end:
- `schools_pipeline.R` pulls RELAFFIL from IC2023 via `get_table(2023, "IC2023")`. The field is applied uniformly to all panel years (religious affiliation changes very slowly).
- `.RELAFFIL_LOOKUP` table in `schools_pipeline.R` provides the authoritative code-to-label mapping from the IPEDS IC2023 codebook (70 active denomination codes + -1 "Not reported" and -2 "Not applicable"). The lookup was verified against the official codebook after an initial reconstruction-from-memory was found to have systematic label errors.
- `schools.csv` carries three columns: `religious_affiliation_code` (raw integer), `religious_affiliation` (denomination label), `religious_tradition` (broader rollup: Catholic / Protestant / Other Christian / Jewish / Other).
- `peers_pipeline.R` computes a `same_religious_tradition` binary variable per call based on the anchor's affiliation. Variable participates in the Composition theme with auto-normalized weight (~1.2% of total clustering signal by default).
- Holy Cross spot-check: `religious_affiliation_code = 30`, `religious_affiliation = "Roman Catholic"`, `religious_tradition = "Catholic"`.

**Tradition assignments:**
- Catholic: Roman Catholic only
- Protestant: denominationally-specific Protestant traditions (Lutheran, Methodist, Presbyterian, Baptist, etc.)
- Other Christian: Eastern Orthodox, LDS, nondenominational/ecumenical/multi-denominational
- Jewish: Jewish
- Other: Muslim, Buddhist, Unitarian Universalist, and the catch-all "Other (none of the above)"

These categorical choices are visible in `.RELAFFIL_LOOKUP` in `schools_pipeline.R` and can be revised if a different rollup serves a downstream use case better.

---

## Methodology choices documented in detail

| Decision | Documented in |
|---|---|
| Two-table architecture | Methodology Part I |
| Year conventions (IPEDS, AI offset, Scorecard, Carnegie) | Methodology Part I |
| Rate normalization (0-100 across sources) | Methodology Part I |
| Test scores as descriptive only | Admissions module section |
| Three-level race trio + detail race at half weight | Enrollment module section |
| Scorecard pivot for pct_first_generation | Enrollment module section |
| FASB volatility fix (4 variables replaced) | Finance & Resources module section |
| `loan_repayment_rate` field path correction | Outcomes module section |
| Auto-normalize peer weights by theme | Peer methodology section |
| 70% coverage threshold | Peer methodology section |
| Log transforms (which variables, why) | Peer methodology section |
| Euclidean vs Mahalanobis (empirical convergence) | Peer methodology section |

**Methodology document**: `output/Peer_Schools_Methodology.docx` (587 paragraphs across 3 parts).

**Crosswalk**: `output/Peer_Schools_Crosswalk.xlsx` (6 tabs: Overview + 5 modules).

---

## Known limitations

1. **CDS layer has ~45% universe coverage** (Academic Insights survey respondents only). In the ranked universe the rate is higher (~60-75%), so most CDS variables survive the 70% peer-coverage threshold — but coverage is sector-dependent.

2. **Scorecard universe is ~79% of our IPEDS universe** (2,047 vs 2,598). Institutions not in Scorecard return NA for `median_earnings_*`, `loan_repayment_rate`, `pct_first_generation`, `median_family_income`. Mostly Title IV non-participants.

3. **Carnegie attributes are single-year snapshots** applied uniformly to all panel years. `earnings_ratio`, `herd_avg`, `apm_max_cip2*` reflect 2020-2023 source data.

4. **HERD R&D coverage is naturally low** (4% private NFP, 12% public). Voluntary reporting; primarily relevant for research-active institutions. Will fail the 70% peer-coverage threshold in most candidate pools.

5. **FASB net assets vs GASB net position** are similar but not identical accounting concepts. Cross-sector comparison of `net_assets_per_fte` is approximate.

6. **`pct_faculty_full_time` is not in the project** (S_IS table is FT-only by IPEDS design). Could be reconstructed if part-time data is later pulled.

7. **Mahalanobis distance fails to invert on the default variable set** due to covariance rank deficiency from highly correlated variables. Falls back to weighted Euclidean automatically with a warning. Real finding, not a bug — the theme-normalization already handles most correlation-related issues.

8. **`first_gen_grad_rate_6yr` coverage is ~25%** project-wide (cohort-anchored AI metric, depends on which schools report first-gen status). Likely falls below the 70% peer-coverage threshold and is excluded from clustering math.

9. **Religious affiliation is applied uniformly across panel years** from a single IC2023 pull, similar to Carnegie classifications. Affiliations change very rarely, so this is a documented simplification rather than a real limitation.

---

## Open items deferred to future work

### Layer 3: Variable selection for clustering
**Status**: Designed, not implemented. Discussion noted: `clustvarsel` (continuous data version of LCAvarsel) for Gaussian mixture model variable selection, or `sparcl::KMeansSparseCluster` for sparse K-means. Output would inform Shiny app's default variable set.

**Honest caveats**: Computationally expensive on 50+ variables × 1,235 schools. Sensitive to assumed number of clusters and covariance structure. Output requires careful interpretation — the "variables that distinguish the universe's clusters" aren't necessarily the variables that define HC's peer space. Best used as input to analyst judgment, not as a definitive variable set.

### Shiny app for interactive exploration
**Status**: Designed in two layers (existing-method dashboard + PCA/UMAP visualization tab), deferred to a dedicated future session. Estimated 800-1200 lines. Should be built on top of `compute_peers()` after Layer 3 informs the default variable set.

### Stratified peer sets
**Status**: Designed (wrap `compute_peers()` with multiple per-category calls), deferred. Would produce results like "top 10 LAC peers, top 5 National University peers, top 5 Regional University-North peers" as a single combined output. Requires no changes to `compute_peers()` itself.

### NECHE comparison spreadsheet rebuild
**Status**: `build_neche_comparison.R` exists but predates several of this session's fixes (rate normalization, coverage report repair, loan_repayment_rate path correction). Needs a rerun against the corrected facts files.

### Separator-screening pass
**Status**: Originally planned as a formal exercise to verify clustering variables actually separate institutions. Largely superseded by the peer methodology's auto-normalization (which handles correlation-related inflation) and the empirical findings from running `compute_peers()`. Could still be done as a one-off correlation analysis but not blocking.

### Schools.csv attribute additions (planned but not implemented)
- Religious affiliation (infrastructure present, data path broken — see Known Limitations #1)
- Possibly: state-level peer regions (currently using `stabbr` directly), enrollment size bands (could derive from `instsize` already in schools.csv)

---

## File map

```
peer_schools/
├── R/
│   ├── schools_pipeline.R              # Shared infrastructure + schools.csv builder
│   ├── peers_pipeline.R                # compute_peers() function
│   ├── aid_module_pipeline.R           # Aid (11 vars)
│   ├── admissions_module_pipeline.R    # Admissions (11 vars)
│   ├── enrollment_module_pipeline.R    # Enrollment (21 vars)
│   ├── outcomes_module_pipeline.R      # Outcomes (12 vars)
│   ├── finance_resources_module_pipeline.R  # Finance & Resources (17 vars)
│   ├── accdb_to_rda.R                  # IPEDS .accdb → .Rda conversion
│   └── build_neche_comparison.R        # NECHE peer-set spreadsheet builder
├── data/
│   ├── IPEDS2019-20.Rda                # through IPEDS2024-25.Rda
│   └── ...                             # Carnegie 2025 Public Data File
├── output/
│   ├── schools.csv                     # Shared institutional attributes
│   ├── value_labels.csv                # IPEDS code-to-label lookups
│   ├── aid_facts.csv / aid_variables.csv
│   ├── adm_facts.csv / adm_variables.csv
│   ├── enr_facts.csv / enr_variables.csv
│   ├── out_facts.csv / out_variables.csv
│   ├── fin_facts.csv / fin_variables.csv
│   ├── Peer_Schools_Methodology.docx   # Consolidated methodology (587 paragraphs)
│   └── Peer_Schools_Crosswalk.xlsx     # 6-tab crosswalk (Overview + 5 modules)
├── .Renviron                           # ACADEMIC_INSIGHTS_API_KEY, SCORECARD_API_KEY
└── Project_Handoff.md                  # This document
```

---

## Working principles

These shaped many decisions and should continue to:

1. **Acquire data, don't score it.** The data layer tags variables with metadata; scoring/weighting/comparison is for downstream applications.

2. **Store cleanly-measured components, derive comparisons.** Better to store `pct_pell` and `pct_first_generation` separately than a single "equity composite." Better to store `grad_rate_6yr` and `first_gen_grad_rate_6yr` separately than a precomputed first-gen-vs-overall gap.

3. **Honest tagging over selective reporting.** When a variable has known issues (test score submission bias, single-snapshot from Carnegie, FASB volatility), tag it honestly in `coverage_note` and `use_type` rather than dropping it entirely or burying the caveat.

4. **The methodology is configurable, not fixed.** Different theme weights, different anchor schools, different candidate pools produce different peer sets. That's a feature, not a flaw — peer comparison is inherently purpose-dependent.

5. **Empirical sanity checks beat theoretical guarantees.** Methodology choices should be validated by spot-checking outputs (does HC's peer set look like HC?). When math and intuition disagree, look at the data before changing the math.

6. **Honest documentation of what didn't work.** Variables we tried and dropped (4 FASB-volatile finance metrics, AI first-gen candidates 731/1014/1027-1029, test-policy variable) are documented as much as variables we kept. This saves future maintainers from re-investigating dead ends.

7. **Graceful degradation when data sources fail.** Missing API keys, broken table access, schools outside Scorecard's universe — none of these should crash a module. Log a clear message, write what we have, move on.

---

## Conventions for new modules (if extending)

If adding a 6th module or significantly expanding an existing one:

- Follow the two-table pattern. One `<module>_facts.csv`, one `<module>_variables.csv`.
- Read schools.csv at the top of `run_<module>_module()`. Don't duplicate institutional attributes inside the module.
- Use `var_type` consistently: `raw` for direct IPEDS reads, `computed` for derived values, `external` for non-IPEDS sources.
- Use the project's year helpers (`ipeds_to_ai_year`, `ai_to_ipeds_year`) for any AI pulls. Don't recompute the +2 offset locally.
- Use `scorecard_get()` for Scorecard pulls. Add a `scorecard_rate_metrics` list to the module's config if any pulled fields are decimal rates.
- Run a coverage report at the end of the module using the `<module>_coverage_report()` pattern. Use the corrected version (with `n_years` column) — every module has it now.
- Update both `Peer_Schools_Methodology.docx` and `Peer_Schools_Crosswalk.xlsx` when adding variables.
- Update this handoff doc with the new module's key decisions and known limitations.

---

## Quick-start for a new session

```r
# 1. Set up
setwd("path/to/peer_schools")
# Set API keys in .Renviron or via Sys.setenv()

# 2. Build the data layer (if facts files are stale or missing)
source("R/schools_pipeline.R");                  build_schools()
source("R/aid_module_pipeline.R");               run_aid_module()
source("R/admissions_module_pipeline.R");        run_admissions_module()
source("R/enrollment_module_pipeline.R");        run_enrollment_module()
source("R/outcomes_module_pipeline.R");          run_outcomes_module()
source("R/finance_resources_module_pipeline.R"); run_finance_resources_module()

# 3. Use the peer-selection layer
source("R/peers_pipeline.R")
res <- compute_peers()
print_peers(res)

# 4. Examples — Holy Cross is the default anchor
# Outcomes-weighted
compute_peers(theme_weights = list(outcomes = 2.5, size = 0.5))
# New England regional
compute_peers(candidate_pool = list(
  in_ranked_universe = TRUE,
  stabbr = c("MA","CT","RI","NH","VT","ME")
))
# Catholic-only (once religious affiliation pipeline is fixed)
compute_peers(candidate_pool = list(
  in_ranked_universe = TRUE,
  religious_tradition = "Catholic"
))
```

Anything not covered here should be in `Peer_Schools_Methodology.docx`. Anything not covered there is genuinely undocumented and you'll need to read the code.
