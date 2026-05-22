# Data Sources

This project integrates four federal datasets from the Centers for Medicare & Medicaid Services (CMS). All are free, publicly available, and downloadable without registration. This document captures the exact vintages, URLs, and reasoning behind the choices — partly as my own reference, partly so anyone reading the repo can reproduce the project.

## The four datasets

| # | Dataset | Source | Vintage | Grain | Approx size |
|---|---|---|---|---|---|
| 1 | Medicare Physician & Other Practitioners — by Provider and Service | data.cms.gov | CY 2023 | NPI × HCPCS × place of service | ~9M rows |
| 2 | Hospital General Information | Provider Data Catalog | Refreshed monthly | One row per hospital | ~5K rows |
| 3 | Hospital quality measures (bundle) | Provider Data Catalog | Refreshed quarterly | Hospital × measure | ~500K rows |
| 4 | Provider specialty reference | Derived from MUP-PHY data dictionary | Static | One row per specialty code | ~100 rows |

## 1. Medicare Physician & Other Practitioners — by Provider and Service (MUP-PHY)

The headline dataset and the reason this project uses Spark. ~9 million rows is past the comfort zone for pandas on a typical workstation, which makes Databricks the right tool rather than overkill.

- **What it contains:** For each provider (identified by NPI), every HCPCS service code they billed Medicare for, how many times, total Medicare allowed amount, total Medicare payment, place of service.
- **Vintage:** Calendar year 2023 — the most recent year available as of November 2025. CMS publishes physician utilization data with about a two-year lag, so 2024 data won't appear until late 2026.
- **Direct CSV URL** (verified live, May 2026): `https://data.cms.gov/sites/default/files/2025-04/e3f823f8-db5b-4cc7-ba04-e7ae92b99757/MUP_PHY_R25_P05_V20_D23_Prov_Svc.csv`
- **Landing page:** https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service
- **Filename decoded:** `MUP_PHY` = Medicare Utilization Payment, Physician. `R25` = Release 25. `P05` = Publication 5. `V20` = Version 20. `D23` = Data year 2023.

The CMS data file naming convention encodes the release and data year directly in the filename, which makes it easy to confirm you're working with the right vintage when reconciling multiple sources.

## 2. Hospital General Information

The reference table for hospitals. Maps CMS Certification Numbers (CCN) to hospital name, address, type, ownership, and overall star rating.

- **What it contains:** One row per Medicare-certified hospital with identifying info and CMS's overall hospital rating (1-5 stars).
- **Vintage:** Continuously updated, refreshed roughly monthly.
- **Dataset ID:** `xubh-q36u`
- **Landing page:** https://data.cms.gov/provider-data/dataset/xubh-q36u
- **Download approach:** Use the Provider Data Catalog metastore API to fetch the current CSV URL programmatically, since the direct URL changes each refresh. Pattern: `https://data.cms.gov/provider-data/api/1/metastore/schemas/dataset/items/xubh-q36u` returns JSON containing the current `downloadURL`.

## 3. Hospital quality measures

This is the dataset that the original project plan called "Hospital Compare Quality Measures." CMS retired the Hospital Compare brand a few years back; the data now lives in the Provider Data Catalog under various measure-specific files. The exact file to use will be confirmed in Phase 2 once the file structure is inspected — there are three to four candidates that bundle quality measures at different levels of detail.

- **What it contains:** Mortality rates, readmission rates, patient experience (HCAHPS) scores, healthcare-associated infection rates, and other publicly reported measures, scored at the hospital level.
- **Scope decision:** Filter down to ~10 high-signal measures for the analysis rather than working with all 100+. The curated set will likely include: 30-day mortality (AMI, heart failure, pneumonia), 30-day readmission (same three), hospital-wide readmission, HCAHPS overall rating, and HAI infection rates. Final list locked in Phase 2.
- **Refresh cadence:** Quarterly.

## 4. Provider specialty reference

The MUP-PHY dataset has a `Rndrng_Prvdr_Type` column with cryptic codes (e.g., `01`, `02`, `08`). The human-readable mapping isn't published as a separate file — it lives inside the MUP-PHY methodology document. The plan is to build a small reference table in the silver layer from the methodology PDF rather than treating this as an ingested external dataset.

- **Source:** MUP-PHY methodology document at https://data.cms.gov/resources/medicare-physician-other-practitioners-methodology
- **Approach:** Manually transcribe the specialty code table into a static CSV that's checked into the repo. ~100 rows. This is small enough that doing it once and versioning it is cleaner than scraping a PDF on every pipeline run.

## Geographic scope

Nationwide — all 50 states plus DC and territories present in the source data. Single-state filtering would weaken the case for Spark since the data volume would drop into pandas-comfortable territory, and the most interesting analytical story in this project is geographic variation in spending and quality.

## Reproducibility notes

- The MUP-PHY direct URL above is stable for the 2023 vintage. CMS doesn't change historical file URLs; they add new ones for new years.
- The Provider Data Catalog datasets (Hospital General Info, quality measures) use rotating CSV URLs that change on each refresh. The metastore API endpoint is the durable way to get current URLs.
- All four datasets are released under https://www.usa.gov/government-works — public domain, no attribution required, but I'm citing CMS anyway because that's the right thing to do.

## Known limitations of the source data

Worth flagging up front so the final analysis can be honest about them:

- **Small-cell suppression.** CMS suppresses any row where the service count is fewer than 11, to protect beneficiary privacy. This means provider-level totals are systematically slightly understated, especially for rare procedures.
- **Two-year lag.** 2023 utilization data published in late 2025 is the freshest available. The project will note this rather than pretending the data is current.
- **Medicare fee-for-service only.** The MUP-PHY file does not include Medicare Advantage encounters, which now cover roughly half of Medicare beneficiaries. Any conclusions about "what Medicare pays" are really "what fee-for-service Medicare pays."
- **Hospital quality measures are reported lagged from underlying claims** by 1-3 years depending on the measure. The 2025 quality release is mostly looking at 2021-2023 outcomes.
- **NPI vs. CCN.** Physician data uses NPI (National Provider Identifier). Hospital data uses CCN (CMS Certification Number). These do not join directly — connecting a physician's payments to a hospital's quality scores requires inferring an affiliation, which is itself a modeling choice that will be documented in the silver layer.

That last limitation is actually one of the more interesting engineering problems in the project, and it'll get its own writeup when we get to Phase 3.
