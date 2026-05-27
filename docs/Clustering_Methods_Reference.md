# Clustering and Similarity Methods: A Reference

A walkthrough of the major method families for computing institutional peer sets, with honest pros, cons, and guidance on when each is the right tool. Written for the College of the Holy Cross peer-comparison project but generalizable to any institutional benchmarking context.

This document is a reference companion to `Peer_Schools_Methodology.docx` (which covers the specific methodology this project uses) and `Project_Handoff.md` (which covers the project's architecture). Read this when evaluating method choices or planning the Shiny app's exploratory features.

---

## The fundamental distinction: what question are you asking?

This is the single most important framing. Different methods answer different questions, and conflating them is where peer-comparison projects often go wrong.

| Question | Method category |
|---|---|
| "Which schools are most similar to *this specific institution*?" | **Anchored similarity** (what this project uses) |
| "How does the universe naturally partition into groups?" | **Partitioning clustering** (k-means, hierarchical) |
| "What latent populations generated this data?" | **Model-based clustering** (Gaussian mixtures, finite mixture models) |
| "Where are the dense regions of the data?" | **Density-based clustering** (DBSCAN, HDBSCAN) |
| "What does the data look like in 2D?" | **Dimension reduction** (PCA, t-SNE, UMAP) |

Picking the wrong category produces a technically valid analysis that doesn't answer the question you actually care about.

---

## 1. Anchored similarity (weighted Euclidean distance)

**What this project uses.** Pick an anchor school, standardize all variables to z-scores, compute weighted distance to every candidate, rank ascending.

**How it works:**
- Variables are pre-processed (log transforms, theme normalization)
- Standardized to z-scores using candidate-pool statistics
- Weighted Euclidean distance: `sqrt(sum(w_v × (z_anchor,v - z_candidate,v)²))`
- Top-K nearest neighbors returned

### Pros

- **Directly answers the question.** "Who looks like the anchor?" → ranked list of schools.
- **Interpretable.** Distance is a single number you can decompose by theme or variable. You can debug a surprising result by asking "which variables contributed most to this school's distance?"
- **Configurable.** Theme weights, variable weights, candidate pool filters are all first-class parameters. Multiple peer sets emerge from different configurations.
- **Reproducible.** No random seeds, no convergence concerns. Same data + same weights = same peer set, always.
- **Computationally cheap.** Linear in number of candidates.
- **Doesn't require deciding the "right" number of clusters.** You just ask for the top K, where K is your choice.
- **Handles missing data gracefully.** Pairwise NA handling — candidate skips dimensions where it has NA.

### Cons

- **Doesn't discover unanticipated structure.** If there's a meaningful cluster of schools that share an unmeasured characteristic, you won't find it unless that characteristic correlates with measured variables.
- **The weights are subjective.** No statistical procedure tells you what weights "should" be. Different defensible weights produce different peer sets — a feature when you want multiple peer sets, but it means you can't claim "objective optimal peers."
- **Treats dimensions as orthogonal.** Highly correlated variables (e.g., 4 NECHE enrollment counts) inflate their joint contribution. Theme normalization addresses this at the theme level, but the issue persists at sub-theme level.
- **Equal-weight defaults are a choice, not a discovery.** The methodology doesn't tell you what your peer set "really is" — it tells you what your peer set is *given your weighting choices*.
- **Symmetric distance.** Schools that are "aspirational peers" (similar in outcomes but very different in resources) aren't separable from "true peers" without direction-aware filters.

### When this is the right tool

- Peer benchmarking
- Anchored what-if analysis ("how do we compare?")
- Configurable multi-purpose peer sets
- Defensible audit-friendly methodology

### When it's wrong

- Discovering natural groupings
- Identifying latent populations
- Exploratory analysis of structure you don't yet know exists

---

## 2. K-means clustering

**The classic partitioning method.** Partition the universe into k mutually exclusive groups by minimizing within-cluster variance.

**How it works:**
- Pick k (number of clusters)
- Initialize k random centroids
- Iteratively: assign each school to its nearest centroid, then update each centroid as the mean of its members
- Converge when assignments stop changing

### Pros

- **Discovers natural groupings.** If "small selective LACs with large endowments" is a real cluster in the data, k-means will find it without being told.
- **Scales well** to large datasets. O(n × k × i) where i is iterations.
- **Well-understood.** Decades of research; standard in every statistical package.
- **Produces a full partition.** Every school gets a cluster assignment — useful for cohort analyses.

### Cons

- **No anchor-relative ranking.** Once an institution is in cluster 4, all schools in cluster 4 are "equally peer-y." You can compute distance-to-centroid as a secondary measure, but at that point you've added work that anchored distance does directly.
- **K is hard to choose.** Elbow method, silhouette score, gap statistic — all give different answers. Different k → different peer sets. No clean way to defend "k = 7 is correct."
- **Assumes spherical, equal-sized clusters.** Higher-ed institutions don't sit in equal-sized spherical groups in 50-dimensional space. Imposing this geometry distorts results.
- **Sensitive to initialization.** Different random seeds can produce different cluster assignments, especially for borderline schools. Mitigated by `nstart` parameter (typically 25+) but never fully solved.
- **All variables contribute equally.** No natural way to encode theme priorities. You can pre-weight before standardization, but generating multiple peer sets with different theme emphases requires re-running clustering from scratch.
- **Doesn't handle missing data gracefully.** Schools with NA on any variable are typically dropped or imputed.

### When this is the right tool

- Exploratory analysis of natural groupings
- Cohort analysis where every school needs a category
- When you genuinely don't know the structure ahead of time

### When it's wrong

- Anchored peer comparison
- Configurable peer sets
- When the question is "who's similar to X" rather than "what groups exist"

---

## 3. Hierarchical clustering

**Build a tree.** At the bottom, every school is its own cluster; at the top, everything merges into one. Cut the tree at some height to get a peer set.

**How it works:**
- Compute pairwise distances between all schools (computationally expensive)
- Agglomerative: iteratively merge the two closest clusters (single, complete, average, or Ward's linkage)
- Or divisive: iteratively split the largest cluster
- Result: a dendrogram you cut at a chosen height

### Pros

- **Produces a dendrogram you can visualize.** You can see *how* an institution's peer group nests within wider groupings. This is genuinely useful for understanding similarity structure.
- **Multiple resolution levels.** Cut high → broad groups; cut low → fine-grained peer sets. Useful when you want to explore "small peer set → broader peer set → universe."
- **No need to pre-specify k.** Choose by inspecting the dendrogram.
- **Deterministic.** Same data → same tree every time (within a given linkage choice).

### Cons

- **Computationally expensive.** Pairwise distance matrix is O(n²). On 1,235 schools manageable; on a larger universe, less so.
- **Linkage choice matters substantially.** Single-linkage (chains form), complete-linkage (tight clusters), Ward's (variance-minimizing), average-linkage — each produces different trees from identical data. Yet another methodological choice that affects results.
- **Same "where to cut" problem as K-means.** You're substituting "choose k" for "choose cut height" — equivalent decision.
- **No ranking within a cluster.** After cutting the tree, schools within a cluster are equally peer-y.
- **Sensitive to outliers.** A few institutions with extreme values can pull cluster structure in unhelpful ways.
- **Can produce unbalanced clusters.** Some clusters end up with 200+ schools; others with 3.

### When this is the right tool

- Exploratory visualization of similarity structure
- When you want to see *how* schools nest within broader groupings
- Multi-resolution analysis

### When it's wrong

- Production peer-comparison workflow
- Anchored ranking
- Very large universes

---

## 4. Finite Mixture Models (FMM) / Gaussian Mixture Models (GMM)

**The probabilistic cousin of k-means.** Assumes the data is generated by k latent populations, each Gaussian (or whatever distribution you specify). Each school has a probability of belonging to each population.

**How it works:**
- Specify k populations and a distribution family (typically multivariate Gaussian)
- Use Expectation-Maximization (EM) algorithm:
  - E-step: compute each school's probability of belonging to each population
  - M-step: update each population's mean and covariance based on weighted membership
- Iterate until convergence
- Output: each school is, say, 73% Population A, 21% Population B, 5% Population C

### Pros

- **Soft membership.** A school isn't forced into one bucket — it can be partially in two or three. More realistic than hard partition.
- **Principled statistical framework.** BIC/AIC give principled criteria for choosing k.
- **Captures covariance structure within clusters.** Unlike k-means which assumes spherical clusters, GMM allows elliptical clusters with arbitrary orientation.
- **Maximum likelihood estimation.** Well-understood statistical properties; standard errors available.

### Cons

- **Strong distributional assumptions.** Assumes variables are Gaussian within each population. Higher-ed data is heavily skewed (endowment, enrollment). Requires transformation (log) before fitting.
- **Computationally slow.** EM is iterative and slower than k-means. Can get stuck in local optima — typically requires multiple random restarts.
- **Component identification problem.** Component A in one fit may be labeled Component B in another. Makes comparing results across runs awkward.
- **Interpretability problem.** "School X is 73% Population 4 and 21% Population 7" doesn't translate naturally to "here are X's peers." You have to define peers as "schools with similar population-membership profiles" — a secondary computation.
- **Sensitive to the number of components.** Different k → very different results. BIC and AIC sometimes disagree.
- **No natural place for theme weighting.** Variables are pooled into the covariance matrix; you can't easily say "weight Outcomes higher."

### When this is the right tool

- When you have theoretical reasons to believe the data is a mixture of distinct populations (e.g., "R1 universities are fundamentally different from LACs, not just at the extreme end of a continuum")
- Modeling uncertainty in cluster membership
- Statistical inference about population structure

### When it's wrong

- Configurable peer comparison
- When you want ranked peer lists
- When distributional assumptions don't hold

---

## 5. Density-based clustering (DBSCAN, HDBSCAN)

**Finds dense regions.** No assumption about cluster shape or count — just identifies pockets where points are densely packed, plus "noise" points that don't belong to any cluster.

**How it works:**
- **DBSCAN**: a point is a "core point" if it has ≥ minPts neighbors within distance ε. Core points and their neighbors form clusters. Points not reachable from any core point are noise.
- **HDBSCAN**: generalizes by varying ε across the density landscape — handles clusters of different densities better than DBSCAN.

### Pros

- **No pre-specified k.** Number of clusters emerges from the data.
- **Arbitrary cluster shapes.** Unlike k-means's spherical assumption, DBSCAN finds clusters of any shape.
- **Identifies outliers explicitly.** Schools that don't fit any cluster are labeled as noise, not forced into the nearest one.

### Cons

- **Sensitive to ε and minPts.** Choosing these parameters is a guessing game.
- **Doesn't handle varying densities well** (DBSCAN; HDBSCAN partially addresses this).
- **No ranking within clusters.** Same problem as k-means.
- **Hard to interpret in high dimensions.** Density estimation becomes unreliable as dimensionality grows.

### When this is the right tool

- When you suspect arbitrary-shaped clusters
- Explicit outlier detection
- Spatial data, fraud detection

### When it's wrong

- Peer comparison generally. The "noise" label and parameter sensitivity make this poorly suited to institutional comparison.

---

## 6. Dimension reduction (PCA, UMAP, t-SNE)

**Reduces 50+ variables to 2-3 dimensions** for visualization and exploration. Not clustering per se — produces coordinates, not cluster assignments.

### 6a. PCA (Principal Components Analysis)

**Linear projection** that captures the most variance in the fewest dimensions.

**Pros:**
- **Deterministic.** Same data → same components every time.
- **Interpretable loadings.** Each principal component is a weighted combination of original variables; you can see which variables drive each dimension.
- **Well-understood statistical theory.**

**Cons:**
- **Linear.** Can't capture curved manifolds in the data.
- **Often the first 2 components only capture 40-60% of variance** in higher-ed data. Important structure may be in PC3-PC5.

**When it's right:** First-pass exploration, visualization, validating that the data has separable structure.

### 6b. UMAP (Uniform Manifold Approximation and Projection)

**Non-linear projection** preserving local neighborhood structure.

**Pros:**
- **Captures non-linear structure.** Can find curved manifolds PCA misses.
- **Reasonable computational performance** on datasets of moderate size.

**Cons:**
- **Parameter sensitivity.** `n_neighbors`, `min_dist`, etc. produce visually different maps from identical data.
- **Non-deterministic.** Different random seeds → different projections → different visual "neighbors." Bad for reproducibility unless seeds are fixed.
- **Distance in projected space is not interpretable.** A school 1 cm away in the UMAP plot isn't "1 standard deviation away" or any other meaningful unit.
- **Local-preserving but not global-preserving.** Two schools far apart in the UMAP plot may actually be similar overall.

**When it's right:** Exploratory visualization, illustrating structure in presentations. Supplements but doesn't replace a numeric methodology.

### 6c. t-SNE (t-Distributed Stochastic Neighbor Embedding)

**Similar to UMAP but older.** Same family, same general tradeoffs.

**Pros:**
- **Captures local structure well.**

**Cons:**
- **Doesn't preserve global distances at all.** Two well-separated clusters in t-SNE may be close in the original space.
- **Hyperparameter sensitive** (perplexity).
- **Slower than UMAP.**

**When it's right:** Same use cases as UMAP; usually superseded by UMAP in modern workflows.

---

## 7. Variable selection methods (clustvarsel, sparcl)

**Not clustering itself — preprocessing.** Identifies which variables carry cluster signal and which add noise.

### 7a. `clustvarsel` (continuous analog of LCAvarsel)

**Forward-backward selection** for Gaussian mixture models.

**Pros:**
- **Principled framework.** Selects variables to maximize BIC of the resulting clustering.
- **Directly compatible with mclust** (GMM fitting).

**Cons:**
- **Computationally expensive.** On 50+ variables × 1,235 schools, could take hours.
- **Sensitive to assumed cluster structure.** Different k → different selected variables.
- **Selects variables that distinguish *any* clusters** — not necessarily the clusters you care about.

### 7b. `sparcl` (Sparse Clustering)

**L1 penalty applied to K-means or hierarchical clustering** — selects variables via sparsity.

**Pros:**
- **Faster than clustvarsel.**
- **Variable weights rather than binary include/exclude.** More flexible output.

**Cons:**
- **Tuning parameter (the penalty strength) requires cross-validation.**
- **Less principled than clustvarsel** — heuristic feature selection.

### When variable selection is the right tool

- When you have many candidate variables and suspect most don't carry signal
- As input to informing which variables a downstream peer methodology should feature

### When it's wrong

- When you already have strong theoretical reasons for your variable set
- When you want to keep all variables for interpretability (e.g., institutional research requires reporting on the full feature set)

---

## How the methods compare for an anchored peer-comparison question

If we'd built each method instead of `compute_peers()`, here's what an output for a given anchor school would look like:

| Method | What the "peer list" would look like |
|---|---|
| **Anchored Euclidean** (this project) | Ranked list: School #1 (distance 0.77), School #2 (1.13), ..., School #20 (1.48). Distance is a single number per school. Configurable via theme weights. |
| **K-means** | "Anchor is in cluster 4, which contains these 47 schools." No ranking within. Different K → different cluster definitions. |
| **Hierarchical** | "Anchor's nearest neighbor is X. Cut the tree at height 1.5 → 12-school cluster. Cut at 2.0 → 34-school cluster." Multi-resolution. |
| **GMM/FMM** | "Anchor is 81% in Component 2 and 14% in Component 5." Schools ranked by similarity of component-membership profile (secondary computation). |
| **DBSCAN** | "Anchor is in cluster 1 with 23 other schools. The following 4 schools are noise (outliers)." |
| **UMAP/PCA** | A 2D scatter plot with the anchor and its nearest neighbors visible. Not a list per se. |

---

## Guidance for Layer 3 (variable selection) work

When tackling Layer 3, here's an honest framing:

1. **Run `clustvarsel` once** on the full variable set to see which variables it identifies as carrying cluster signal. This is research-grade analysis, not production code.

2. **Compare the selected variable set to your current theme assignments.** If `clustvarsel` says "drop variables X, Y, Z," that's a finding worth thinking about. It may mean those variables don't help distinguish institutional types, or it may mean they distinguish types you don't care about (e.g., research universities vs LACs, when you're already filtering to selective privates).

3. **Don't take the result as definitive.** The variables clustvarsel selects depend on assumed cluster structure (k value, covariance assumptions). Use the output to inform analyst judgment, not as a finished variable list.

4. **Build the Shiny app around the curated variable set**, with the option to toggle methods (Euclidean / K-means / Hierarchical / GMM) for exploratory comparison.

---

## Bottom-line recommendation for institutional peer comparison

For most peer-comparison projects, **stay with anchored weighted Euclidean as the primary methodology.** It's:

- The right tool for the question most institutions are actually asking
- Interpretable and defensible
- Configurable for multiple peer-set purposes
- Reproducible without random seeds or model selection
- Computationally cheap

**Use other methods as supplements, not replacements:**

- **PCA for visualization** — see where the anchor sits in the data
- **K-means or hierarchical for exploration** — when you want to ask "what natural groupings exist?" separately from "who's like the anchor?"
- **clustvarsel for one-time variable selection analysis** — to inform which variables deserve emphasis

An interactive exploration tool should let users compare alternative methods side-by-side and see how peer sets differ, but the *primary* peer-comparison workflow should remain anchored similarity.

---

## Why this project chose weighted Euclidean from anchor

For reference, the specific reasoning that drove the project's methodology choice:

**The question being answered:** "Which schools are most similar to the College of the Holy Cross under specified weighting assumptions?" This is a fundamentally anchored question, not a partition-the-universe question.

**The framework requirements:**
- Must support multiple peer sets for different purposes (institutional comparison, competitive set, aspirational peers)
- Must be configurable via theme weights and variable weights
- Must be defensible in writing for accreditation and benchmarking reports
- Must be reproducible (no random seeds, no model selection)
- Must handle the project's missing-data patterns gracefully

**Why not K-means or hierarchical:** They produce partitions, not anchored rankings. Once HC is in cluster 4, you've lost the resolution to ask "of the 47 schools in cluster 4, which 10 are closest to HC?"

**Why not GMM:** Distributional assumptions are violated by the project's heavily-skewed financial and enrollment variables, even with log transforms. Component identification across runs adds reproducibility overhead.

**Why not UMAP:** Distances in projected space don't have institutional meaning. The non-determinism makes audit-friendly methodology harder.

**Why not Mahalanobis distance** (which we did consider): Empirically, Mahalanobis and weighted Euclidean produce nearly identical rankings on this data once redundant variables are pruned. The theme normalization (auto-normalize by theme) already handles most of the correlation issues that Mahalanobis would address. We kept Mahalanobis as an opt-in alternative metric for sensitivity analysis, but it's not the default.

The current methodology's empirical validation: for the HC anchor on default settings, the top 20 peers are mostly institutions the College has historically benchmarked against (Lafayette, Trinity CT, Colgate, Hamilton, Davidson, Vassar, Carleton, Middlebury, Skidmore, Colby, etc.), with Catholic peers like Boston College, Fairfield, and Providence appearing in the 21-50 range. This is the kind of output peer-comparison work is supposed to produce.
