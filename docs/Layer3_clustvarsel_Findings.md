# Layer 3: clustvarsel Variable Selection Findings

A research pass using `clustvarsel` (forward-backward variable selection for Gaussian mixture models) over the project's 53 clustering variables. The goal was to test whether the universe's natural cluster structure aligns with the variables the methodology currently emphasizes, and to inform Shiny app defaults where appropriate. This is a research finding, not a replacement for `compute_peers()`. The locked methodology remains weighted Euclidean from anchor. See `Clustering_Methods_Reference.md` §7a for background on the method and its known limitations.

---

## Setup

### First attempt: headlong forward on all 53 variables

The initial pass used clustvarsel's default headlong-forward search on the full 53-variable matrix (ranked universe, 1,233 schools, 0.85 within-pool coverage threshold, median imputation on residual NAs, log transforms matching `compute_peers()`).

The search selected only two variables before terminating: `pct_nhpi` and `pct_black`. Both are detail race variables with heavily right-skewed, near-zero-inflated distributions. Many institutions report values near zero, with a small tail of institutions reporting much higher values. Gaussian mixture models treat that shape as two distinct populations and award it large BIC improvements, which causes headlong search to accept it quickly and stop.

This is a known limitation of the method on data with zero-inflated features. The result is technically valid but says nothing useful about peer comparison.

### Decision: trim detail race and rerun with greedy search

We made two adjustments for the substantive analysis.

First, we excluded the six detail race variables (`pct_black`, `pct_hispanic`, `pct_asian`, `pct_nhpi`, `pct_aian`, `pct_two_or_more`) from the variable selection pass. These remain in `compute_peers()` at half-weight in the Composition theme, where weighted Euclidean handles their distribution reasonably. They were causing artifacts in clustvarsel specifically, not in the production methodology.

Second, we switched from headlong to greedy search. Headlong accepts the first variable that improves BIC at each step. Greedy evaluates all remaining candidates and picks the best at each step. Greedy is more exhaustive and avoids early termination on borderline-improving variables.

The substantive pass used the following settings:

| Setting | Value |
|---|---|
| Universe | Ranked universe (`in_ranked_universe = TRUE`), 1,233 schools |
| Variables submitted | 47 (53 clustering vars minus the 6 detail race) |
| Coverage threshold | 0.85 within-pool |
| Missing data | Median imputation on residual gaps (2% of cells) |
| Log transforms | Same 23 variables as `compute_peers()` |
| Search | Greedy forward |
| Cluster count range | G = 2 to 6 |
| Runtime | 21.9 minutes with parallelization across 7 cores |

### Variables dropped by the 0.85 coverage threshold

Nine variables fell below 85% within-pool coverage and were excluded structurally before the selection algorithm ran.

| Variable | Coverage | Theme | Reason |
|---|---|---|---|
| `pct_need_fully_met` | 83.8% | aid | CDS response rate |
| `pct_need_met` | 83.3% | aid | CDS response rate |
| `pct_top10_hs` | 75.6% | selectivity | CDS response rate |
| `transfer_out_rate` | 74.5% | outcomes | IPEDS reporting gap |
| `first_gen_grad_rate_6yr` | 46.2% | outcomes | Cohort-anchored AI metric |
| `avg_net_price_aided` | 38.8% | aid | Subset of need-aided cohorts |
| `avg_net_price_income_0_30k` | 38.8% | aid | Income-band reporting gap |
| `ed_acceptance_rate` | 16.5% | selectivity | ED programs are minority practice |
| `ed_share_of_applications` | 15.9% | selectivity | Same |

These exclusions align with the CDS-coverage and ED-program caveats already documented in `project_handoff.md` under "Known limitations." Their absence here is structural, not a finding about variable quality.

---

## Results

The pass selected 15 of the 47 variables submitted, with best G = 6.

### By theme

| Theme | Selected | Total in pass | Selection rate |
|---|---|---|---|
| Finance | 7 | 7 | 100% |
| Aid | 3 | 3 | 100% (themed) |
| Resources | 2 | 7 | 29% |
| Selectivity | 1 | 5 | 20% |
| Composition | 1 | 10 | 10% |
| Outcomes | 0 | 8 | 0% |
| Scale | 0 | 4 | 0% |

The Finance and Aid themes survived intact. Resources lost most of its variables. Selectivity and Composition each contributed one variable. Outcomes and Scale contributed nothing.

### Selected variables

**Finance (7):** `published_tuition_fees`, `core_expenses_per_fte`, `operating_margin_ex_inv_return_per_fte`, `tuition_share_of_expenses`, `net_assets_per_fte`, `endowment_coverage_years`, `endowment_per_fte`.

**Aid (3):** `pct_pell`, `avg_inst_grant`, `inst_discount_rate`. Plus `pct_any_grant`, which is tagged as a clustering variable in `aid_variables.csv` but does not appear in `peer_pipeline.R`'s aid theme list because of a variable-naming mismatch (the theme list still references `pct_grant_aid`, an older name no longer used in the data). This is tracked separately as a bug in `peer_pipeline.R`.

**Resources (2):** `instruction_per_fte`, `instructional_share`.

**Selectivity (1):** `yield_rate`.

**Composition (1):** `pct_age_25plus`.

### Rejected variables

**Outcomes (all 8):** `grad_rate_4yr`, `grad_rate_6yr`, `retention_rate`, `pell_grad_gap`, `median_earnings_6yr`, `median_earnings_10yr`, `loan_repayment_rate`, `earnings_ratio`.

**Scale (all 4):** `total_enrollment`, `undergraduate_enrollment`, `first_time_enrollment`, `full_time_enrollment`.

**Composition (9):** `median_family_income`, `pct_bipoc`, `pct_first_generation`, `pct_international`, `pct_part_time`, `pct_undergrad`, `pct_white`, `residential_share`, `transfer_in_enrollment`.

**Resources (5):** `academic_support_per_fte`, `avg_ft_faculty_salary`, `student_faculty_ratio`, `student_services_per_fte`, `tenure_track_share`.

**Selectivity (4):** `acceptance_rate`, `application_volume`, `pct_submitting_act`, `pct_submitting_sat`.

### Holy Cross's component assignment

The mclust fit on the 15 selected variables placed Holy Cross in component 3 (one of six components), with 114 co-members. A sample of those co-members:

> Birmingham-Southern College, California Institute of Technology, University of California-Berkeley, University of California-Los Angeles, Claremont McKenna College, Harvey Mudd College, Occidental College, Pitzer College, Pomona College, University of San Diego, Santa Clara University, Scripps College.

This group is best described as selective private institutions with strong financial profiles, plus a few large public research universities with comparable per-FTE finance metrics. It is not the peer set `compute_peers()` produces for Holy Cross, which is dominated by selective small LACs (Lafayette, Trinity CT, Colgate, Hamilton, Davidson, and so on).

---

## Interpretation

### The IPEDS 4-year universe is structurally a finance landscape

Once Finance and Aid variables are in the mixture model, the rest of the variables we submitted contribute no additional cluster-distinguishing signal. Outcomes variables (graduation rates, retention, earnings, loan repayment) are entirely rejected. Enrollment scale variables are entirely rejected. Race composition variables are almost entirely rejected.

This is not because those variables are uninformative about individual institutions. Each one carries real institutional meaning. What the selection result tells us is that they correlate strongly enough with Finance and Aid at the universe level that their cluster-distinguishing power is already absorbed by the variables already in the model.

Put differently: in the ranked universe, knowing an institution's endowment-per-FTE, net assets, Pell share, and discount rate is enough to predict its graduation rate, enrollment size, and racial composition with enough accuracy that the Gaussian mixture model gains nothing by adding those variables explicitly. The unsupervised structure of the universe is finance-dominated. Outcomes and scale come along for the ride.

### Why this matters for the project's methodology

The project's peer methodology assigns equal-by-default theme weight to Outcomes, Scale, Composition, and Selectivity precisely because those dimensions carry institutional character we want reflected in the peer set even when they correlate with finance. Outcomes is a 12-variable theme that the methodology weights as a full theme (one-seventh of total signal), not as a redundant proxy for finance.

That choice is what produces the peer set Holy Cross actually uses: Lafayette, Trinity CT, Colgate, Hamilton, Davidson, Vassar, Carleton, Middlebury, and the rest of the selective LAC cohort. These institutions share graduation rate, retention, residential character, and enrollment scale with Holy Cross. They do not all share its finance profile.

If we used clustvarsel's selected variable set as default weights, the peer list would shift away from this cohort toward "selective privates with strong finances" more broadly, which is essentially the component-3 group above. That set includes Caltech and the Claremont consortium because those institutions share Holy Cross's finance profile, even though they differ substantially in mission and scale.

This finding validates the warning in `Clustering_Methods_Reference.md` §7: variables that distinguish universal clusters are not necessarily the variables that define a given institution's peer space. The methodology's value comes from theme-weighted equal treatment, not from data-driven variable selection.

### What this analysis does and does not establish

Two implications worth being careful about, given the natural temptation to read them in.

The 32 rejected variables are not redundant in `compute_peers()`. Theme-weighted Euclidean uses each variable as an independent dimension. The methodology is not asking which variables uniquely partition the universe; it is asking how similar each candidate is to the anchor across all dimensions. A variable can fail to add cluster-distinguishing power and still carry meaningful peer-similarity signal.

The 15 selected variables are not a "better" default. They are the variables that distinguish universal clusters. Defaulting `compute_peers()` to that subset would change what the methodology answers, not improve how well it answers the current question.

---

## Use in the Shiny app

The project does not include a "Lean default" variable preset in the Shiny app. The methodology stays as designed.

The findings do inform two specific Shiny app features:

1. A variable-importance panel in the diagnostics section of the Peer Search tab. It surfaces the BIC trajectory from this pass: which variable entered the model at each step, with what BIC improvement. The panel provides context for advanced users about which variables carry universe-level cluster signal, without altering the default weights.

2. A note in the methodology snapshot included with download bundles. The note records that variable selection was tested and that the equal-theme default was retained based on the empirical finding above.

---

## Other operational use

Two places this output is useful outside the Shiny app.

**Methodology defense.** When stakeholders ask why we use equal-weight themes rather than letting the data pick weights, we now have an empirical answer. Data-driven selection over the ranked universe produces a peer set dominated by finance similarity, not the institutional-character similarity that drives benchmarking work.

**Validation of the FASB-volatility fix.** All seven selected Finance variables are the stable replacements brought in during the FASB volatility audit (`endowment_coverage_years`, `tuition_share_of_expenses`, `core_expenses_per_fte`, and so on). None of the originally-planned-but-dropped volatile finance metrics would have surfaced here. The replacement set is internally coherent and captures the finance signal cleanly.

---

## Caveats

Three things worth remembering when citing these results.

Median imputation is not model-based. The pass imputed about 2% of cells, with the heaviest imputation on `residential_share` (174 institutions, 14%) and `tenure_track_share` (157 institutions, 13%). The per-variable imputation counts are stored in `output/clustvarsel_full_prep.rds$imputation$na_counts_before` for anyone who wants to inspect. A future pass using multiple imputation (e.g., `mice`) would be more defensible for publication, though the qualitative finding is unlikely to change.

G = 6 is BIC-best within the 2 to 6 range tested. Extending to G = 1 through 9 would take roughly three times longer to run. We did not test the wider range, on the assumption that the qualitative finding (which themes survive selection) is robust to reasonable G choice. Worth verifying if anyone reuses the output.

clustvarsel assumes Gaussian mixtures. Log transforms helped with the most heavily skewed variables (endowments, enrollment counts), but residual skew remains. BIC values from this pass are useful for relative comparison across runs on the same data. Absolute BIC magnitudes should not be read on their own.

---

## Reproducibility

The full setup, including the `prepare_clustvarsel_data()` and `run_clustvarsel_analysis()` functions, lives in `R/explore_clustvarsel.R`. To reproduce:

```r
source("R/explore_clustvarsel.R")
suppressMessages({ library(doParallel); library(foreach) })

prep <- prepare_clustvarsel_data(coverage_threshold = 0.85)
detail_race <- c("pct_black","pct_hispanic","pct_asian",
                 "pct_nhpi","pct_aian","pct_two_or_more")
prep$X <- prep$X[, !colnames(prep$X) %in% detail_race]
prep$vars_used <- colnames(prep$X)

cl <- makeCluster(max(1, detectCores() - 1))
registerDoParallel(cl)
fit <- run_clustvarsel_analysis(prep, G = 2:6, search = "greedy",
                                direction = "forward", parallel = TRUE,
                                verbose = TRUE)
stopCluster(cl)

summarize_clustvarsel(fit, prep)
```

Persisted artifacts from this pass live in:

- `output/clustvarsel_full_prep.rds` (the standardized matrix and metadata)
- `output/clustvarsel_passD.rds` (the fitted clustvarsel object)
- `output/clustvarsel_passD.log` (the verbose run log with step-by-step BIC progression)
