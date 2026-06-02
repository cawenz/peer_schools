# Variable Catalog

Every numeric variable the Peer Schools Explorer surfaces, grouped by category.

Generated from `output/*_variables.csv` on June 01, 2026.  Re-run `Rscript R/tools/generate_variable_catalog.R` after adding variables.

**Reading the columns:**

- **Variable** — the display name shown throughout the app.
- **Metric ID** — internal column name used in `.SCHOOLS_WIDE` and the facts CSVs. The Side-by-Side inspector, the cohort dashboard, and the codebook export all key off this.
- **Format** — how the value is rendered: `percentage`, `count`, `currency`, `ratio`, `score`.
- **Source** — where the value comes from.
- **Role** — whether the variable is included in peer-distance computation (clustering) or shown for reference only (descriptive).
- **Notes** — coverage caveats and methodological notes worth knowing.

---

## Athletics (EADA)  (10 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| Athletes as % of full-time UG enrollment | `pct_athletes_overall` | percentage | EADA (computed) | Used in peer distance | Ranges from ~1% at large D-I publics to >40% at small D-III LACs. HC (D-I, Patriot League) has unusually high participation for a D-I school: ~23% of UG enrollment. |
| Female athletes (unduplicated) | `female_athletes_undup` | count | EADA (Equity in Athletics Disclosure Act) | Descriptive only | Unduplicated headcount: multi-sport athletes counted once. |
| Female athletes as % of female full-time UG | `pct_female_athletes` | percentage | EADA (computed) | Descriptive only | EADA's gender-specific UG denominator. |
| Male athletes (unduplicated) | `male_athletes_undup` | count | EADA (Equity in Athletics Disclosure Act) | Descriptive only | Unduplicated headcount: multi-sport athletes counted once. |
| Male athletes as % of male full-time UG | `pct_male_athletes` | percentage | EADA (computed) | Descriptive only | EADA's gender-specific UG denominator. |
| Men's varsity sports | `mens_varsity_sports` | count | EADA (computed) | Descriptive only | EADA 2024-25; ~2,037 schools filed. Single-sex institutions, service academies, and schools without intercollegiate athletics are missing. |
| Multi-sport athlete ratio | `multi_sport_ratio` | ratio | EADA (computed) | Used in peer distance | Average sports per athlete. LACs run 1.20-1.35 (lots of two-sport athletes); D-I near 1.00. |
| Total athletes (unduplicated) | `total_athletes_undup` | count | EADA (computed) | Descriptive only | Use this in any 'athletes / enrollment' calculation. |
| Total varsity sports | `total_varsity_sports` | count | EADA (computed) | Used in peer distance | Breadth of program. |
| Women's varsity sports | `womens_varsity_sports` | count | EADA (computed) | Descriptive only | Same as above. |

## Enrollment & Composition  (22 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| First-time degree-seeking UG enrollment | `first_time_enrollment` | count | IPEDS | Used in peer distance |  |
| Full-time fall enrollment | `full_time_enrollment` | count | IPEDS | Used in peer distance |  |
| Graduate share of total enrollment | `pct_graduate` | percentage | IPEDS (computed) | Descriptive only | Algebraic complement of pct_undergrad; tagged descriptive to avoid double-counting in clustering. |
| Median family income (FAFSA filers) | `median_family_income` | currency | College Scorecard | Used in peer distance | Single 2024 snapshot; FAFSA-filer denominator only - higher-income non-filers are excluded, so value typically understates true student-body family income. Useful for clustering but not as an absolute income measure. |
| Part-time share of total enrollment | `pct_part_time` | percentage | IPEDS (computed) | Used in peer distance |  |
| Percent American Indian or Alaska Native | `pct_aian` | percentage | IPEDS | Descriptive only | Detailed breakdown; trio is clustering version |
| Percent Asian | `pct_asian` | percentage | IPEDS | Descriptive only | Detailed breakdown; trio is clustering version |
| Percent Black or African American | `pct_black` | percentage | IPEDS | Descriptive only | Detailed breakdown; trio is clustering version |
| Percent Hispanic or Latino | `pct_hispanic` | percentage | IPEDS | Descriptive only | Detailed breakdown; trio is clustering version |
| Percent Native Hawaiian or Pacific Islander | `pct_nhpi` | percentage | IPEDS | Descriptive only | Detailed breakdown; trio is clustering version |
| Percent first-generation undergraduates | `pct_first_generation` | percentage | College Scorecard | Used in peer distance | Single 2024 snapshot; FAFSA-filer denominator (not all UG); ~58% project coverage. First-gen share is structurally stable enough for clustering but not for year-over-year trends. |
| Percent of enrollment that is BIPOC | `pct_bipoc` | percentage | IPEDS (computed) | Used in peer distance | 3-level trio component; excludes race/ethnicity unknown |
| Percent of enrollment that is U.S. nonresident | `pct_international` | percentage | IPEDS | Used in peer distance | 3-level trio component; visa status, not race |
| Percent of enrollment that is White | `pct_white` | percentage | IPEDS | Used in peer distance | 3-level trio component |
| Percent of undergraduates age 25-64 | `pct_age_25plus` | percentage | IPEDS | Used in peer distance |  |
| Percent race/ethnicity unknown | `pct_race_unknown` | percentage | IPEDS | Descriptive only | Transparency variable; excluded from BIPOC computation |
| Percent two or more races | `pct_two_or_more` | percentage | IPEDS | Descriptive only | Detailed breakdown; trio is clustering version |
| Share of undergraduates living on campus | `residential_share` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%) |
| Total fall enrollment | `total_enrollment` | count | IPEDS | Used in peer distance |  |
| Transfer-in undergraduate enrollment | `transfer_in_enrollment` | count | IPEDS | Used in peer distance |  |
| Undergraduate fall enrollment | `undergraduate_enrollment` | count | IPEDS | Used in peer distance |  |
| Undergraduate share of total enrollment | `pct_undergrad` | percentage | IPEDS (computed) | Used in peer distance |  |

## Finance  (8 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| Endowment assets per FTE | `endowment_per_fte` | currency | IPEDS | Used in peer distance |  |
| Endowment value as years of operating expenses | `endowment_coverage_years` | ratio | IPEDS (computed) | Used in peer distance | Higher = financially stronger. Most LACs 1-5; wealthiest research 10+ |
| HERD R&D expenditures, 3-year average (Carnegie) | `herd_avg` | currency | Carnegie 2025 Data File | Descriptive only | NECHE peer-set member. One-time Carnegie snapshot (FY2020-2023 avg) under 2024. |
| Net tuition revenue as % of core expenses | `tuition_share_of_expenses` | percentage | IPEDS (computed) | Used in peer distance | Stable analog of tuition_dependence; uses expenses (no investment-return distortion) |
| Operating margin per FTE, excluding investment return | `operating_margin_ex_inv_return_per_fte` | currency | IPEDS (computed) | Used in peer distance | Negative values common for endowment-rich schools that fund operations from endowment income |
| Published tuition + required fees (in-state, UG, AY) | `published_tuition_fees` | currency | IPEDS | Used in peer distance | Combined tuition + fees. In-state used for public institutions. |
| Total core operating expenses per FTE | `core_expenses_per_fte` | currency | IPEDS (computed) | Used in peer distance |  |
| Total net assets per FTE (year end) | `net_assets_per_fte` | currency | IPEDS (computed) | Used in peer distance | FASB net assets vs GASB net position - documented in methodology |

## Financial Aid  (11 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| Average federal loan per borrower | `avg_federal_loan` | currency | IPEDS | Used in peer distance |  |
| Average institutional grant per recipient | `avg_inst_grant` | currency | IPEDS | Used in peer distance |  |
| Average net price - all aided students | `avg_net_price_aided` | currency | IPEDS | Used in peer distance | Public institutions report under NPIST (in-state Title IV recipients); private nonprofits report under NPGRN (grant recipients). Definitions are very similar but not identical. |
| Average net price - lowest income band ($0-30k) | `avg_net_price_income_0_30k` | currency | IPEDS | Used in peer distance | Public institutions report under NPIS41 (in-state); private nonprofits report under NPT41. Income band 1 (0-30k) in both. |
| Average percent of need met (freshmen) | `pct_need_met` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%) |
| Institutional discount rate | `inst_discount_rate` | ratio | IPEDS (computed) | Used in peer distance | In-state tuition used for public institutions |
| Number of all undergraduates awarded Pell grants | `pell_count` | count | IPEDS | Descriptive only | All-UG population; pct_pell measures first-time full-time only |
| Percent borrowing federal loans | `pct_federal_loan` | percentage | IPEDS | Used in peer distance |  |
| Percent of students whose need was fully met (freshmen) | `pct_need_fully_met` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%) |
| Percent receiving Pell grants (first-time full-time UG) | `pct_pell` | percentage | IPEDS | Used in peer distance |  |
| Percent receiving any grant or scholarship aid | `pct_any_grant` | percentage | IPEDS | Used in peer distance |  |

## Outcomes & Programs  (16 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| 3-year loan repayment rate (completers) | `loan_repayment_rate` | percentage | College Scorecard | Used in peer distance | Latest available Scorecard cohort |
| 4-year bachelor's graduation rate | `grad_rate_4yr` | percentage | IPEDS | Used in peer distance |  |
| 6-year bachelor's graduation rate | `grad_rate_6yr` | percentage | IPEDS | Used in peer distance |  |
| Actual vs expected earnings (CCIHE SAEC) | `earnings_ratio` | ratio | Carnegie 2025 Data File | Used in peer distance | One-time CCIHE snapshot; written under latest panel year |
| First-gen 6-year graduation rate | `first_gen_grad_rate_6yr` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%); rate, not gap. Construct comparisons downstream. |
| Full-time first-year retention rate | `retention_rate` | percentage | IPEDS | Used in peer distance |  |
| Grad rate gap, women minus men (6-year), pp | `grad_rate_men_vs_women` | percentage | IPEDS (computed) | Exploratory | Exploratory only |
| Median earnings 10 yrs after entry | `median_earnings_10yr` | currency | College Scorecard | Used in peer distance | Latest available Scorecard cohort; long lag from current year |
| Median earnings 6 yrs after entry | `median_earnings_6yr` | currency | College Scorecard | Used in peer distance | Latest available Scorecard cohort |
| Number of distinct graduate CIP2 families | `n_grad_cip2_families` | count | IPEDS (computed) | Descriptive only | Broader grouping than n_grad_programs. |
| Number of distinct graduate programs (CIP6, primary major) | `n_grad_programs` | count | IPEDS (computed) | Descriptive only | Includes Master's, research doctorates, professional-practice doctorates, and other doctorates. Counts programs that produced at least one graduate in the latest panel year. |
| Number of distinct undergraduate CIP2 families | `n_undergrad_cip2_families` | count | IPEDS (computed) | Descriptive only | Broader grouping than n_undergrad_programs; each CIP2 is a major academic family (e.g., 11 = Computer Science, 14 = Engineering, 26 = Biology). |
| Number of distinct undergraduate programs (CIP6, primary major) | `n_undergrad_programs` | count | IPEDS (computed) | Descriptive only | Counts CIP codes that produced at least one bachelor's graduate in the latest panel year. Slightly under-counts programs that exist but had zero completions. |
| Pell minus non-Pell 6-year award rate, pp | `pell_grad_gap` | percentage | IPEDS (computed) | Used in peer distance | Negative values mean Pell students do worse |
| Research/scholarship doctorates awarded | `doctoral_degrees_awarded` | count | IPEDS | Descriptive only | NECHE peer-set member. Excludes professional-practice doctorates (DOCDEGPP). |
| Transfer-out rate from entering cohort | `transfer_out_rate` | percentage | IPEDS | Used in peer distance |  |

## Resources  (9 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| % of instructional staff tenured or on tenure track | `tenure_track_share` | percentage | IPEDS (computed) | Used in peer distance | NA if institution has no tenure system (FACSTAT 40 populated, 20+30 empty) |
| % of undergrad classes with 50 or more students | `pct_classes_50plus` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%) |
| % of undergrad classes with fewer than 20 students | `pct_classes_under_20` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%) |
| Academic support expenses per FTE | `academic_support_per_fte` | currency | IPEDS | Used in peer distance |  |
| Average full-time instructional salary | `avg_ft_faculty_salary` | currency | IPEDS (computed) | Used in peer distance |  |
| Instruction as % of total core expenses | `instructional_share` | percentage | IPEDS | Used in peer distance |  |
| Instruction expenses per FTE | `instruction_per_fte` | currency | IPEDS | Used in peer distance |  |
| Student services expenses per FTE | `student_services_per_fte` | currency | IPEDS | Used in peer distance |  |
| Student-to-faculty ratio (computed) | `student_faculty_ratio` | ratio | IPEDS (computed) | Used in peer distance | Computed (STUFACR not in IPEDS); matches NSC's published S-F ratio formula |

## Selectivity & Admissions  (11 variables)

| Variable | Metric ID | Format | Source | Role | Notes |
|---|---|---|---|---|---|
| ACT mid-50% composite score | `act_mid50` | score | IPEDS (computed) | Descriptive only | Kept separate from SAT (no concordance); not for clustering |
| Acceptance rate | `acceptance_rate` | percentage | IPEDS (computed) | Used in peer distance |  |
| Early decision acceptance rate | `ed_acceptance_rate` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%); NA distinct from 'no ED program' |
| Early decision applicants as % of total applications | `ed_share_of_applications` | percentage | Common Data Set (computed) | Used in peer distance | Numerator covers ~45% of universe; denominator near-universal |
| Number of applications | `application_volume` | count | IPEDS | Used in peer distance |  |
| Percent of enrolled in top 10% of HS class | `pct_top10_hs` | percentage | Common Data Set (via Academic Insights) | Used in peer distance | Survey respondents only (~45%) |
| Percent of first-time students submitting ACT scores | `pct_submitting_act` | percentage | IPEDS | Used in peer distance | Companion to act_mid50 |
| Percent of first-time students submitting SAT scores | `pct_submitting_sat` | percentage | IPEDS | Used in peer distance | Companion to sat_mid50 |
| SAT mid-50% composite score | `sat_mid50` | score | IPEDS (computed) | Descriptive only | Submission bias under test-optional policies; not for clustering |
| Yield gap (women minus men), percentage points | `yield_men_vs_women` | percentage | IPEDS (computed) | Exploratory | Exploratory only; not a core variable |
| Yield rate | `yield_rate` | percentage | IPEDS (computed) | Used in peer distance |  |

