-- +goose Up

-- =================================================================
-- Schema-per-environment setup
--
-- This migration creates:
-- 1. A dedicated schema for the current environment
-- 2. An app_user role with access ONLY to that schema
--
-- The schema name is set via search_path at connection time.
-- The goose migrator connects with search_path=<env_schema>,
-- so all DDL runs inside that schema automatically.
--
-- NOTE: This migration runs as the master (postgres) user which
-- has the privileges to create schemas and roles.
-- =================================================================

-- Create extension if not exists (database-level, idempotent)
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- +goose Down
-- Down migration intentionally left minimal to avoid data loss.
-- To fully remove, manually drop the schema and role.
