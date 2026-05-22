# Architecture

This project uses the medallion architecture pattern in Databricks — three Delta Lake table layers (bronze, silver, gold) with progressively more refinement at each layer. This document captures the layout and the reasoning behind it.

## The diagram

```mermaid
flowchart TD
    classDef rawStyle fill:#e8e8e8,stroke:#666,stroke-width:2px,color:#000,font-size:14px
    classDef bronzeStyle fill:#cd7f32,stroke:#8b5a2b,stroke-width:2px,color:#fff,font-size:14px,font-weight:bold
    classDef silverStyle fill:#c0c0c0,stroke:#808080,stroke-width:2px,color:#000,font-size:14px,font-weight:bold
    classDef goldStyle fill:#ffd700,stroke:#b8860b,stroke-width:2px,color:#000,font-size:14px,font-weight:bold
    classDef outputStyle fill:#4a90e2,stroke:#2c5f9e,stroke-width:2px,color:#fff,font-size:14px,font-weight:bold

    RAW["<b>RAW</b><br/>4 CSV files from CMS<br/>~9.5M rows total"]:::rawStyle

    BRONZE["<b>BRONZE</b> — Delta tables, schema enforced<br/><br/>medicare_physician_payments &nbsp;•&nbsp; hospital_info<br/>hospital_quality_measures &nbsp;•&nbsp; provider_specialty_ref"]:::bronzeStyle

    SILVER["<b>SILVER</b> — cleaned, deduplicated, standardized<br/><br/>providers (1 row per NPI)<br/>provider_services (NPI × service)<br/>hospital_quality (hospital × measure)"]:::silverStyle

    GOLD["<b>GOLD</b> — analytical aggregates<br/><br/>provider_spending_summary &nbsp;•&nbsp; specialty_benchmarks<br/>state_spending_quality &nbsp;•&nbsp; hospital_value_scorecard"]:::goldStyle

    DASH["<b>Databricks SQL Dashboard</b><br/>+ Analysis Notebooks"]:::outputStyle

    RAW --> BRONZE
    BRONZE --> SILVER
    SILVER --> GOLD
    GOLD --> DASH
```

## Why medallion

The medallion pattern is the standard lakehouse architecture in Databricks, Snowflake, and pretty much every other major data platform that emerged in the last few years. It exists because moving raw data straight to analytics tables conflates three concerns that should be separate:

1. **Landing data reliably from external sources** (bronze)
2. **Cleaning and conforming it to business rules** (silver)
3. **Aggregating it for specific analytical questions** (gold)

Mixing these means every change to a business rule ripples back into your ingestion logic, every schema drift in a source file breaks your reports, and every new analytical question requires re-reading and re-cleaning the raw data. Separating the layers gives you the freedom to fix issues at the right level without breaking the others.

## What lives at each layer

### Bronze — raw landed as Delta

Bronze tables are nearly identical to the source CSVs. The only transformations:

- **CSV to Delta format.** Delta gives ACID transactions, schema enforcement, time travel, and faster reads. Once it's in Delta we never go back to raw CSV.
- **Schema explicitly declared.** No `inferSchema=True` — every column gets a deliberate type at this layer. This catches CMS schema drift the moment it happens instead of silently coercing.
- **Ingestion metadata added.** A `_ingested_at` timestamp and `_source_file` column on every bronze table, for lineage.

Nothing else. No deduplication, no joins, no business logic. Bronze is the durable, replayable source of truth that everything downstream is derived from.

### Silver — cleaned and conformed

Silver is where the data becomes usable. Decisions made at this layer:

- **Deduplicate.** CMS files have duplicate rows in places, especially when providers practice at multiple locations.
- **Standardize codes.** Specialty codes get joined to the reference table. State codes get validated against a known list. HCPCS codes get checked for format.
- **Handle suppression markers.** CMS uses `*` and various flags to indicate suppressed small-cell values. Silver translates these to proper `NULL` so downstream aggregations behave correctly.
- **Define the canonical grain for each entity.** `silver.providers` has one row per NPI — this is the grain decision that the rest of the project depends on.

Silver tables are what an analyst would query if they wanted "the cleaned data." They're not pre-aggregated for any specific question.

### Gold — analytical aggregates

Gold tables answer specific business questions. Each one corresponds to a slice of the analysis:

- **`gold.provider_spending_summary`** — one row per provider, total Medicare payments, service counts, specialty, state. The base table for the "top spenders" analysis.
- **`gold.specialty_benchmarks`** — medians and percentiles of spending and service volume by specialty. The base for "spending variation by specialty."
- **`gold.state_spending_quality`** — state-level rollups of provider spending joined to state-level quality measure aggregates. The base for the geographic variation maps.
- **`gold.hospital_value_scorecard`** — hospital-level integration of spending intensity and quality scores. The base for the cost-quality scatter analysis.

Gold tables are denormalized on purpose. They're optimized for being read by dashboards and notebooks, not for being maintained as part of a normalized schema.

## Why Delta Lake specifically

Three reasons that matter for this project:

1. **Schema enforcement at write time.** When CMS publishes a new file with a renamed column, the write fails loudly instead of silently producing nulls. That's exactly what you want in a pipeline that runs once a year on data that periodically changes shape.
2. **Time travel.** Every transformation creates a new version. If I run the silver pipeline and discover it dropped 200 NPIs incorrectly, I can query the previous version and figure out what changed without re-ingesting from source.
3. **ACID transactions.** Spark jobs that partially fail don't leave the table in a corrupt half-written state. This stops mattering at toy scale and starts mattering at 9M-row scale.

The alternative would be Parquet files in a bucket with manual metadata management. That's how data lakes worked five years ago. Delta is what made the "lakehouse" idea actually viable.

## Catalog and schema layout

Inside Databricks, the layout will use Unity Catalog with the three layers as schemas under a single catalog:

```
medicare_provider_quality (catalog)
├── bronze (schema)
│   ├── medicare_physician_payments
│   ├── hospital_info
│   ├── hospital_quality_measures
│   └── provider_specialty_ref
├── silver (schema)
│   ├── providers
│   ├── provider_services
│   └── hospital_quality
└── gold (schema)
    ├── provider_spending_summary
    ├── specialty_benchmarks
    ├── state_spending_quality
    └── hospital_value_scorecard
```

Three-part naming (`catalog.schema.table`) is the Unity Catalog convention and lets you reference tables unambiguously across the workspace. Even on Databricks Free with a single workspace it's worth doing properly — it's the same pattern used in production environments and it costs nothing to set up correctly the first time.

Raw CSVs will land in a Databricks Volume (`medicare_provider_quality.raw.landing`) before being read into bronze. Volumes are Unity Catalog's mechanism for managing files alongside tables, and using one keeps the entire pipeline inside Unity governance rather than relying on DBFS or external storage.

## What this architecture deliberately does not do

A few things that might look like omissions:

- **No streaming.** CMS publishes annually. Streaming infrastructure for an annual file would be theater. Batch with Auto Loader is the right pattern here.
- **No CDC.** The data doesn't update — each year's release is a complete snapshot. SCD type 2 patterns will be discussed in the silver layer (year-over-year provider tracking) but aren't needed for the core pipeline.
- **No real-time serving.** The dashboard reads from gold tables, which are refreshed when the pipeline runs. That's the right granularity for annual data.

These are decisions, not gaps. Building infrastructure that doesn't match the actual data refresh cadence is a common mistake and worth flagging up front.

## Reproducibility

The full pipeline will be reproducible by running the notebooks in order:

1. Ingestion notebook (raw CSV → bronze)
2. Silver transformation notebooks
3. Gold aggregation notebooks
4. Analysis notebooks

Each notebook will be idempotent — running it twice produces the same result as running it once. Non-idempotent pipelines are a common source of bugs that only surface on re-runs, after the original author has moved on to other work.
