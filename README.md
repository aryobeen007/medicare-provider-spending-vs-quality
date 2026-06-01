# Medicare Provider Spending vs Quality

> An end-to-end Databricks medallion pipeline analyzing whether Medicare actually pays more for better hospital care. The short answer: not really. Hospital-level spending and mortality correlate at **r = 0.033** — essentially zero.

---

## Live artifacts

- **Project page (portfolio site)** — [nasaryobee.com/projects/medicare-pipeline/](https://nasaryobee.com/projects/medicare-pipeline/) · the full project story with embedded notebooks
- **Tableau Public dashboard** — [open the interactive dashboard](https://public.tableau.com/app/profile/naseer3899/viz/MedicareProviderSpendingvsQuality/MedicareProviderSpendingvsQuality) · the four-quadrant cost-vs-quality story with state filtering

---

## What this project is

A reproducible data engineering pipeline that ingests five public CMS datasets (about 10 million rows total), shapes them through a bronze → silver → gold medallion architecture, and answers a single business question: **does Medicare get what it pays for?**

The full pipeline runs end-to-end in **5 minutes 26 seconds** via Databricks Workflows. Every transformation is documented, every analytical claim is defensible, and every "no" decision (things deliberately not built) is explained.

## The findings, briefly

| Grain | Metric | Result | What it means |
|---|---|---|---|
| Hospital | Correlation between spending intensity and composite mortality | **r = 0.033** | Essentially independent |
| State | Correlation between payment per beneficiary and avg hospital rating | **r = −0.118** | Slightly negative |
| Hospital | Share of hospitals that are "value-mismatched" | **~50%** | Half pay too much for poor outcomes, or get good outcomes cheaply |
| Specialty | Nurse Practitioner top-1% spending concentration | **30.2%** | Reflects organizational billing aggregation, not individual earnings |

The full analytical writeup with charts lives in [`notebooks/04_analysis/`](notebooks/04_analysis/).

## How it's built

```
Raw CSV
   ↓  (ingest from CMS, write to Delta with schema enforcement)
Bronze · 4 tables
   ↓  (clean, aggregate, build NPI ↔ CCN bridge)
Silver · 5 tables
   ↓  (purpose-built aggregates, ranks, value quadrants)
Gold · 4 tables
   ↓  (analytical answers + visualizations)
Analysis · 4 questions answered
```

Orchestrated as a Databricks Workflow — each notebook is a task in a 4-step DAG. See [`docs/architecture.md`](docs/architecture.md) for the full design and decision log.

## Tech stack

Databricks (Free Edition) · PySpark · Delta Lake · Unity Catalog · Databricks Workflows · Databricks SQL · Databricks AI/BI · Tableau Public · Python · matplotlib · Git · PowerShell · Databricks CLI

## Repo map

```
notebooks/
  01_bronze_ingestion/   ← raw CSV → Delta tables (4 bronze tables)
  02_silver_transforms/  ← modeling, joins, NPI↔CCN bridge (5 silver tables)
  03_gold_aggregates/    ← analytical aggregates (4 gold tables)
  04_analysis/           ← the four headline findings with charts
sql/
  ddl/                   ← catalog and schema setup
docs/
  architecture.md        ← full pipeline design, decisions, findings
  data-sources.md        ← every CMS dataset documented with verified URLs
etl/
  download_cms_datasets.ps1  ← reproducible PowerShell script to fetch source data
dashboards/
  screenshots/           ← visual evidence at every phase
```

## Reproducing the pipeline

1. Spin up a Databricks workspace (Free Edition works — that's what this was built on)
2. Run `sql/ddl/01_create_catalog_and_schemas.sql` to create the Unity Catalog structure
3. Use `etl/download_cms_datasets.ps1` to fetch the five source files into your Databricks volume
4. Run the notebooks in order: `01` → `02` → `03` → `04`, or trigger the full pipeline via the Databricks Workflow

The pipeline is **idempotent** — every Delta write uses `mode("overwrite")`, so re-running it doesn't duplicate data.

## What this analysis does NOT claim

- **Not causal.** Sicker populations cost more and have worse outcomes regardless of care quality. This data can't separate "spending doesn't help" from "high-need areas spend more and still struggle."
- **Not complete on quality.** Mortality is one dimension. A fuller picture would weight readmissions, patient experience, and safety together.
- **Bounded by the bridge.** The hospital-level analysis only covers hospitals where the address-matching bridge connected providers (62.6% of acute care hospitals), and is biased toward providers whose billing address matches their hospital exactly.

These limits are real, and the architecture doc states them plainly. The value of the work is in showing — with reproducible code on real federal data — that the intuitive "you get what you pay for" assumption does not hold for Medicare spending and hospital quality.

---

**Author:** Naseer Aryobee · [LinkedIn](https://www.linkedin.com/in/naseer-aryobee/) · [Portfolio](https://nasaryobee.com)
