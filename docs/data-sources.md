# Data Sources

This project integrates federal datasets from the Centers for Medicare & Medicaid Services (CMS). All are free, publicly available, and downloadable without registration. This document captures the exact vintages, URLs, and reasoning behind the choices — partly as my own reference, partly so anyone reading the repo can reproduce the project.

## The five source files

| # | Dataset | Source | Vintage | Grain | Approx size |
|---|---|---|---|---|---|
| 1 | Medicare Physician & Other Practitioners — by Provider and Service | data.cms.gov | CY 2023 | NPI × HCPCS × place of service | ~9.6M rows |
| 2 | Hospital General Information | Provider Data Catalog | Refreshed monthly | One row per hospital | ~5K rows |
| 3 | Complications and Deaths — Hospital | Provider Data Catalog | Refreshed quarterly | Hospital × measure | ~96K rows |
| 4 | Unplanned Hospital Visits — Hospital | Provider Data Catalog | Refreshed quarterly | Hospital × measure | ~67K rows |
| 5 | HCAHPS — Hospital (patient experience) | Provider Data Catalog | Refreshed quarterly | Hospital × measure × answer | ~326K rows |

The original Phase 1 plan listed a sixth source — a "Provider specialty reference" table to map cryptic numeric specialty codes to human-readable names. After ingesting the MUP-PHY data, that turned out to be unnecessary; CMS already publishes the human-readable specialty name directly in the file. See section 6 for the full reasoning.

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

## 3. Complications and Deaths — Hospital

Hospital-level quality measures covering 30-day mortality (heart attack, heart failure, pneumonia, COPD, stroke, CABG), hip/knee complications, and CMS Patient Safety Indicators.

- **What it contains:** One row per hospital per measure, with the score (rate), confidence interval (lower/higher estimate), and "Compared to National" categorical comparison.
- **Vintage:** Continuously updated, refreshed roughly quarterly.
- **Dataset ID:** `ynj2-r877`
- **Landing page:** https://data.cms.gov/provider-data/dataset/ynj2-r877
- **Download approach:** Provider Data Catalog metastore API (same pattern as Hospital General Information).

## 4. Unplanned Hospital Visits — Hospital

Hospital-level readmission and unplanned-visit measures. Includes hospital-wide all-cause 30-day readmission (the `Hybrid_HWR` measure, which combines claims and EHR data) and condition-specific readmission rates.

- **What it contains:** One row per hospital per measure, with score, denominator, and patient counts where applicable.
- **Dataset ID:** `632h-zaca`
- **Landing page:** https://data.cms.gov/provider-data/dataset/632h-zaca

## 5. HCAHPS — Hospital (Patient Experience)

The Hospital Consumer Assessment of Healthcare Providers and Systems survey — the national standardized patient experience survey. Covers ~35 survey questions across nurse communication, doctor communication, pain management, discharge information, and overall hospital rating.

- **What it contains:** One row per hospital per HCAHPS measure ID per answer description. Higher row count than the other quality files because each question is broken out into multiple "answer percentage" rows.
- **Dataset ID:** `dgck-syfz`
- **Landing page:** https://data.cms.gov/provider-data/dataset/dgck-syfz

### Why three quality files instead of one bundled file

CMS publishes hospital quality measures broken across several files by measure category, not as one combined dataset. The Phase 1 plan called for a "broad quality file" — that file doesn't exist in CMS's current data model. Decision in Phase 2: pull the three files that cover the ~10 high-signal measures committed to in Phase 1. Mortality and complications come from the Complications-and-Deaths file. Readmission comes from Unplanned-Hospital-Visits. Patient experience comes from HCAHPS. Together they cover the targeted measure set with each file staying at a manageable size.

## 6. Why there's no specialty reference file

The original Phase 1 plan called for a sixth source: a manually transcribed reference table mapping CMS numeric specialty codes (`01`, `02`, etc.) to readable names like "General practice" and "Cardiology." The reasoning was that the MUP-PHY `Rndrng_Prvdr_Type` column would contain those numeric codes.

After ingesting MUP-PHY in Phase 2, inspection of the actual data showed that assumption was wrong. CMS publishes the human-readable specialty name directly in `Rndrng_Prvdr_Type` — values like `"Addiction Medicine"`, `"Cardiology"`, `"Ambulatory Surgical Center"`. The numeric specialty codes do exist, but in a different CMS data product (line-level claims data), not in the aggregated MUP-PHY file I'm using.

A reference table that maps `"Cardiology"` → `"Cardiology"` would be making work where no problem exists. Decision: drop the planned specialty reference table. Phase 2 closed with four bronze tables instead of five.

This is the kind of plan adjustment that happens when data is actually loaded and inspected. Phase 1 plans are written before the data is in hand — encountering reality then adjusting is the work, not a flaw.

## Geographic scope

Nationwide — all 50 states plus DC and territories present in the source data. Single-state filtering would weaken the case for Spark since the data volume would drop into pandas-comfortable territory, and the most interesting analytical story in this project is geographic variation in spending and quality.

## Reproducibility notes

- The MUP-PHY direct URL above is stable for the 2023 vintage. CMS doesn't change historical file URLs; they add new ones for new years.
- The Provider Data Catalog datasets (Hospital General Info, quality measures) use rotating CSV URLs that change on each refresh. The metastore API endpoint is the durable way to get current URLs.
- All five datasets are released under https://www.usa.gov/government-works — public domain, no attribution required, but I'm citing CMS anyway because that's the right thing to do.

## Known limitations of the source data

Worth flagging up front so the final analysis can be honest about them:

- **Small-cell suppression.** CMS suppresses any row where the service count is fewer than 11, to protect beneficiary privacy. This means provider-level totals are systematically slightly understated, especially for rare procedures.
- **Two-year lag.** 2023 utilization data published in late 2025 is the freshest available. The project will note this rather than pretending the data is current.
- **Medicare fee-for-service only.** The MUP-PHY file does not include Medicare Advantage encounters, which now cover roughly half of Medicare beneficiaries. Any conclusions about "what Medicare pays" are really "what fee-for-service Medicare pays."
- **Hospital quality measures are reported lagged from underlying claims** by 1-3 years depending on the measure. The 2025 quality release is mostly looking at 2021-2023 outcomes.
- **NPI vs. CCN.** Physician data uses NPI (National Provider Identifier). Hospital data uses CCN (CMS Certification Number). These do not join directly — connecting a physician's payments to a hospital's quality scores requires inferring an affiliation, which is itself a modeling choice that will be documented in the silver layer.

That last limitation is actually one of the more interesting engineering problems in the project, and it'll get its own writeup when I get to Phase 3.
