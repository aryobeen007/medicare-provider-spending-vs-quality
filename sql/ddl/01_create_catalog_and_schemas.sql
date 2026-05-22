-- =============================================================================
-- Phase 1: Create the Unity Catalog, medallion schemas, and raw landing volume
-- =============================================================================
-- This script sets up the foundational structure for the project.
-- Run this once in the Databricks SQL Editor before any data ingestion.
-- Uses IF NOT EXISTS throughout so the script is idempotent.
-- =============================================================================

-- Create the catalog for the project
CREATE CATALOG IF NOT EXISTS medicare_provider_quality
  COMMENT 'Catalog for Medicare provider spending vs. quality portfolio project';

-- Create the three medallion layer schemas
CREATE SCHEMA IF NOT EXISTS medicare_provider_quality.bronze
  COMMENT 'Bronze layer: raw CMS data landed as Delta tables with schema enforcement';

CREATE SCHEMA IF NOT EXISTS medicare_provider_quality.silver
  COMMENT 'Silver layer: cleaned, deduplicated, and standardized data';

CREATE SCHEMA IF NOT EXISTS medicare_provider_quality.gold
  COMMENT 'Gold layer: analytical aggregates for dashboards and reports';

-- Create a fourth schema for raw file landing (volumes live here)
CREATE SCHEMA IF NOT EXISTS medicare_provider_quality.raw
  COMMENT 'Raw layer: Unity Catalog volumes for landing source CSV files';

-- Create the managed volume where raw CMS CSV files will land before ingestion
CREATE VOLUME IF NOT EXISTS medicare_provider_quality.raw.landing
  COMMENT 'Landing zone for raw CMS CSV files before bronze ingestion';

-- Verification queries (uncomment to re-run after setup)
-- SHOW SCHEMAS IN medicare_provider_quality;
-- SHOW VOLUMES IN medicare_provider_quality.raw;
