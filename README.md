 peer_schools
 
A data layer for institutional peer comparison, built around the College of the
Holy Cross but designed to generalize to any institution. Pulls from IPEDS, US
News Academic Insights, and the Carnegie 2025 Public Data File. Produces
normalized facts and variable-metadata tables that downstream applications
consume.
 
## Quick start
 
```bash
git clone https://github.com/YOUR_USERNAME/peer_schools.git
cd peer_schools
cp .Renviron.template .Renviron
# edit .Renviron and fill in your real API keys
```
 
Then open `peer_schools.Rproj` in RStudio. From the R console:
 
```r
# install packages (one-time, per machine)
install.packages(c("dplyr", "tidyr", "purrr", "stringr",
                   "httr2", "jsonlite", "readxl"))
 
# verify .Renviron was picked up - should print a non-zero length
nchar(Sys.getenv("ACADEMIC_INSIGHTS_API_KEY"))
 
# run the pipelines
source("R/schools_pipeline.R");    schools <- build_schools()
source("R/aid_module_pipeline.R"); aid     <- run_aid_module()
```
 
`build_schools()` takes 5-10 minutes (mostly the 52 state-by-state US News API
calls; IPEDS data loads from local `.Rda` files in seconds). `run_aid_module()`
takes 1-2 minutes (paged Academic Insights API calls).