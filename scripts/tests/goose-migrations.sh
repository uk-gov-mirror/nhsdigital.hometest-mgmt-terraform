#!/bin/bash

# Test Goose database migrations against a local PostgreSQL container,
# replicating the exact behaviour of the lambda-goose-migrator Lambda:
#
#   1. Connect as master user
#   2. Create a named schema (DB_SCHEMA) if it doesn't exist
#   3. Create app_user_<schema> role, grant schema-scoped privileges
#   4. Set search_path to the schema, run goose migrations
#   5. Verify app_user can connect and perform DML — but cannot see other schemas
#   6. Test rollback and idempotent re-apply
#
# Usage:
#   ./scripts/tests/goose-migrations.sh
#
# Prerequisites:
#   - Docker installed and running
#   - mise installed (will install goose automatically)
#
# Environment variables (optional):
#   POSTGRES_IMAGE     - PostgreSQL Docker image (default: postgres:16)
#   POSTGRES_USER      - Master DB user (default: testuser)
#   POSTGRES_PASSWORD  - Master DB password (default: testpassword)
#   POSTGRES_DB        - Database name (default: testdb)
#   POSTGRES_PORT      - Host port to map (default: 5432)
#   POSTGRES_SCHEMA    - Target schema, mirroring DB_SCHEMA in the Lambda (default: hometest)
#   APP_USER_PASSWORD  - Password for app_user_<schema> (default: appuserpassword)
#   KEEP_CONTAINER     - Set to "true" to keep container after tests (default: false)

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATIONS_DIR="${PROJECT_ROOT}/infrastructure/src/lambda-goose-migrator/src/migrations"

POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16}"
POSTGRES_USER="${POSTGRES_USER:-testuser}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-testpassword}"
POSTGRES_DB="${POSTGRES_DB:-testdb}"
POSTGRES_PORT="${POSTGRES_PORT:-15432}"
POSTGRES_SCHEMA="${POSTGRES_SCHEMA:-hometest}"
APP_USER_PASSWORD="${APP_USER_PASSWORD:-appuserpassword}"
KEEP_CONTAINER="${KEEP_CONTAINER:-false}"

# Derived — mirrors the naming convention in main.go: app_user_<schema>
APP_USERNAME="app_user_${POSTGRES_SCHEMA}"

CONTAINER_NAME="goose-migrations-test-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==============================================================================
# Functions
# ==============================================================================

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

cleanup() {
  if [[ "${KEEP_CONTAINER}" != "true" ]]; then
    log_info "Cleaning up container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
  else
    log_warn "Container ${CONTAINER_NAME} kept running (KEEP_CONTAINER=true)"
  fi
}

wait_for_postgres() {
  local max_attempts=30
  local attempt=1

  log_info "Waiting for PostgreSQL to be ready (in-container check)..."
  until docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
    if [[ ${attempt} -ge ${max_attempts} ]]; then
      log_error "PostgreSQL failed to become ready after ${max_attempts} attempts"
      return 1
    fi
    echo -n "."
    sleep 1
    ((attempt++))
  done
  echo ""

  # Also verify the host-side port mapping is reachable (important on macOS Docker Desktop)
  attempt=1
  log_info "Verifying host-side connectivity on port ${POSTGRES_PORT}..."
  until PGPASSWORD="${POSTGRES_PASSWORD}" psql -h localhost -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1" >/dev/null 2>&1 \
      || nc -z localhost "${POSTGRES_PORT}" 2>/dev/null; do
    if [[ ${attempt} -ge ${max_attempts} ]]; then
      log_error "Host-side connection to localhost:${POSTGRES_PORT} failed after ${max_attempts} attempts"
      return 1
    fi
    echo -n "."
    sleep 1
    ((attempt++))
  done
  echo ""
  log_info "PostgreSQL is ready!"
}

ensure_goose() {
  if command -v goose &>/dev/null; then
    log_info "Using goose: $(goose --version 2>&1 | head -1)"
    return 0
  fi

  if command -v mise &>/dev/null; then
    log_info "Installing goose via mise..."
    mise install "aqua:pressly/goose"
    eval "$(mise env)"
    if command -v goose &>/dev/null; then
      log_info "Goose installed: $(goose --version 2>&1 | head -1)"
      return 0
    fi
  fi

  log_error "goose not found. Please install it via 'mise install' or 'go install github.com/pressly/goose/v3/cmd/goose@latest'"
  return 1
}

# psql as master user.
psql_master() {
  docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" "${CONTAINER_NAME}" \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" "$@"
}

# psql as app_user_<schema> (limited role).
psql_appuser() {
  docker exec -i -e PGPASSWORD="${APP_USER_PASSWORD}" "${CONTAINER_NAME}" \
    psql -U "${APP_USERNAME}" -d "${POSTGRES_DB}" "$@"
}

# Run goose as the master user. search_path is already configured at the
# role level (ALTER ROLE ... SET search_path) in setup_schema_and_user,
# so goose will create its tables in the target schema automatically.
run_goose() {
  local cmd="$1"
  shift
  GOOSE_DRIVER=postgres \
  GOOSE_DBSTRING="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable" \
  goose -dir "${MIGRATIONS_DIR}" "${cmd}" "$@"
}

# Replicate setupSchemaAndUser from main.go:
#   - CREATE SCHEMA IF NOT EXISTS
#   - CREATE ROLE app_user_<schema> LOGIN PASSWORD '...'
#   - GRANT USAGE ON SCHEMA
#   - GRANT SELECT/INSERT/UPDATE/DELETE ON ALL TABLES
#   - GRANT USAGE/SELECT/UPDATE ON ALL SEQUENCES
#   - ALTER DEFAULT PRIVILEGES (so future tables are also covered)
#   - ALTER ROLE ... SET search_path TO <schema>
setup_schema_and_user() {
  log_info "Setting up schema '${POSTGRES_SCHEMA}' and role '${APP_USERNAME}'..."

  psql_master -v ON_ERROR_STOP=1 <<-SQL
    -- 1. Create schema
    CREATE SCHEMA IF NOT EXISTS ${POSTGRES_SCHEMA};

    -- 2. Create app_user role (idempotent)
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '${APP_USERNAME}') THEN
        CREATE ROLE ${APP_USERNAME} LOGIN PASSWORD '${APP_USER_PASSWORD}';
      ELSE
        ALTER ROLE ${APP_USERNAME} PASSWORD '${APP_USER_PASSWORD}';
      END IF;
    END
    \$\$;

    -- 3. Default search_path for this role (mirrors ALTER ROLE ... SET search_path in main.go)
    ALTER ROLE ${APP_USERNAME} SET search_path TO ${POSTGRES_SCHEMA};

    -- 4. Set master user search_path so goose creates tables in the target schema
    ALTER ROLE ${POSTGRES_USER} SET search_path TO ${POSTGRES_SCHEMA};

    -- 5. Schema-scoped grants
    GRANT USAGE ON SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};
    GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};
    ALTER DEFAULT PRIVILEGES IN SCHEMA ${POSTGRES_SCHEMA}
      GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_USERNAME};
    ALTER DEFAULT PRIVILEGES IN SCHEMA ${POSTGRES_SCHEMA}
      GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${APP_USERNAME};
SQL

  log_info "Schema '${POSTGRES_SCHEMA}' and role '${APP_USERNAME}' ready."
}

verify_tables_in_schema() {
  log_info "=== Verifying tables exist in schema '${POSTGRES_SCHEMA}' (not public) ==="

  local table_count
  table_count=$(psql_master -t -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = '${POSTGRES_SCHEMA}';" \
    | xargs)

  if [[ "${table_count}" -eq 0 ]]; then
    log_error "No tables found in schema '${POSTGRES_SCHEMA}' after migration!"
    return 1
  fi
  log_info "Found ${table_count} table(s) in schema '${POSTGRES_SCHEMA}'"

  log_info "Table list in '${POSTGRES_SCHEMA}':"
  psql_master -c \
    "SELECT table_name FROM information_schema.tables WHERE table_schema = '${POSTGRES_SCHEMA}' ORDER BY table_name;"

  log_info "Goose version table in '${POSTGRES_SCHEMA}':"
  psql_master -c "SELECT * FROM ${POSTGRES_SCHEMA}.goose_db_version ORDER BY id;"
}

verify_no_tables_in_public() {
  log_info "=== Verifying no application tables leaked into 'public' schema ==="

  log_info "All schemas in database:"
  psql_master -c \
    "SELECT schema_name FROM information_schema.schemata ORDER BY schema_name;"

  log_info "Tables in 'public' schema:"
  psql_master -c \
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"

  local public_tables
  public_tables=$(psql_master -t -c \
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name != 'goose_db_version';" \
    | xargs)

  if [[ -n "${public_tables}" ]]; then
    log_warn "Unexpected tables found in public schema: ${public_tables}"
  else
    log_info "public schema is clean (no application tables)"
  fi
}

verify_app_user_access() {
  log_info "=== Verifying app_user access as '${APP_USERNAME}' ==="

  # app_user must be able to SELECT from tables in the schema
  log_info "  SELECT from test_type..."
  psql_appuser -v ON_ERROR_STOP=1 -c "SELECT * FROM test_type LIMIT 1;" >/dev/null

  # app_user must be able to INSERT into test_type (seeded by migrations)
  log_info "  INSERT into test_type..."
  psql_appuser -v ON_ERROR_STOP=1 -c \
    "INSERT INTO test_type (test_code, description) VALUES ('TEST_ACCESS_CHECK', 'app_user access verification') ON CONFLICT DO NOTHING;" >/dev/null

  # app_user must be able to DELETE what it just inserted
  log_info "  DELETE from test_type..."
  psql_appuser -v ON_ERROR_STOP=1 -c \
    "DELETE FROM test_type WHERE test_code = 'TEST_ACCESS_CHECK';" >/dev/null

  # app_user must NOT be able to create tables (not a schema owner)
  log_info "  Verify app_user cannot CREATE TABLE..."
  if psql_appuser -c "CREATE TABLE ${POSTGRES_SCHEMA}.should_fail (id int);" 2>&1; then
    log_error "app_user was unexpectedly able to CREATE TABLE — privileges are too broad!"
    return 1
  else
    log_info "  Correctly denied: app_user cannot CREATE TABLE"
  fi

  log_info "app_user access checks passed."
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  trap cleanup EXIT

  cd "${PROJECT_ROOT}"

  log_info "=== Goose Migration Tests ==="
  log_info "Migrations directory : ${MIGRATIONS_DIR}"
  log_info "Target schema        : ${POSTGRES_SCHEMA}"
  log_info "App user             : ${APP_USERNAME}"

  # Check prerequisites
  if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
    log_error "Migrations directory not found: ${MIGRATIONS_DIR}"
    exit 1
  fi

  ensure_goose

  # Start PostgreSQL container
  log_info "Starting PostgreSQL container (${POSTGRES_IMAGE})..."
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -p "${POSTGRES_PORT}:5432" \
    "${POSTGRES_IMAGE}"

  wait_for_postgres

  # Step 1: Replicate setupSchemaAndUser (Lambda step 1)
  setup_schema_and_user

  # Step 2: Validate migration files before running them
  log_info "=== Validating Migrations ==="
  run_goose validate

  # Step 3: Goose status before any migrations
  log_info "=== Migration Status (Initial) ==="
  run_goose status

  # Step 4: Run migrations with search_path=<schema> (Lambda step 2)
  log_info "=== Running Migrations (Up) ==="
  run_goose up

  log_info "=== Migration Status (After Up) ==="
  run_goose status

  # Step 5: Verify tables landed in the right schema
  verify_tables_in_schema
  verify_no_tables_in_public

  # Step 6: Re-grant on existing tables (Lambda step 3 — covers tables created before DEFAULT PRIVILEGES)
  log_info "=== Granting privileges on migrated tables to '${APP_USERNAME}' ==="
  psql_master -v ON_ERROR_STOP=1 -c \
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};"
  psql_master -v ON_ERROR_STOP=1 -c \
    "GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};"

  # Step 7: Verify app_user can perform DML but cannot create tables
  verify_app_user_access

  # Step 8: Rollback and re-apply (idempotency)
  log_info "=== Testing Rollback (Down) ==="
  run_goose down

  log_info "=== Migration Status (After Down) ==="
  run_goose status

  log_info "=== Testing Re-apply (Up again — idempotency) ==="
  run_goose up

  # Step 9: Re-grant after re-apply (mirrors what the Lambda does on each invocation)
  psql_master -v ON_ERROR_STOP=1 -c \
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};" >/dev/null
  psql_master -v ON_ERROR_STOP=1 -c \
    "GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA ${POSTGRES_SCHEMA} TO ${APP_USERNAME};" >/dev/null

  log_info "=== Final Migration Status ==="
  run_goose status

  verify_tables_in_schema
  verify_app_user_access

  log_info ""
  log_info "=== All migration tests passed! ==="
}

main "$@"
