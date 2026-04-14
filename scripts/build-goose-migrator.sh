#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build Goose Migrator Script
# Only rebuilds the goose-migrator Lambda when source code changes are detected.
# Uses content hashing to determine if a rebuild is necessary.
#
# Usage:
#   LAMBDAS_SOURCE_DIR=<path> MIGRATOR_CACHE_DIR=<path> ./build-goose-migrator.sh
#
# Required environment variables:
#   LAMBDAS_SOURCE_DIR                Path to the lambdas source directory
#
# Optional environment variables:
#   MIGRATOR_CACHE_DIR                Build cache directory (default: .migrator-build-cache)
#   FORCE_MIGRATOR_REBUILD=true       Force rebuild even if no changes detected
# -----------------------------------------------------------------------------

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration (from environment variables)
# -----------------------------------------------------------------------------
LAMBDAS_DIR_INPUT="${LAMBDAS_SOURCE_DIR:-}"
CACHE_DIR_INPUT="${MIGRATOR_CACHE_DIR:-.migrator-build-cache}"
FORCE_REBUILD="${FORCE_MIGRATOR_REBUILD:-false}"

if [[ -z "$LAMBDAS_DIR_INPUT" ]]; then
  echo "Error: LAMBDAS_SOURCE_DIR is required"
  echo ""
  echo "Required environment variables:"
  echo "  LAMBDAS_SOURCE_DIR                  Path to the lambdas source directory"
  echo ""
  echo "Optional environment variables:"
  echo "  MIGRATOR_CACHE_DIR                  Build cache directory (default: .migrator-build-cache)"
  echo "  FORCE_MIGRATOR_REBUILD=true         Force rebuild even if no changes detected"
  exit 1
fi

MIGRATOR_DIR="$LAMBDAS_DIR_INPUT/goose-migrator"

if [[ ! -d "$MIGRATOR_DIR" ]]; then
  echo "Error: Goose migrator directory not found: $MIGRATOR_DIR"
  exit 1
fi
MIGRATOR_DIR=$(cd "$MIGRATOR_DIR" && pwd)

# Create and resolve cache directory
mkdir -p "$CACHE_DIR_INPUT"
CACHE_DIR=$(cd "$CACHE_DIR_INPUT" && pwd)

# Cache file locations
HASH_FILE="$CACHE_DIR/goose-migrator.hash"
BUILD_LOG="$CACHE_DIR/last-build.log"

# Output zip path
ZIP_FILE="$MIGRATOR_DIR/goose-migrator.zip"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

calculate_source_hash() {
  # Calculate hash of all source files that affect the build:
  # - Go source files (*.go)
  # - Go module files (go.mod, go.sum)
  # - SQL migration files (*.sql)

  local hash_cmd="sha256sum"
  if ! command -v sha256sum &> /dev/null; then
    hash_cmd="md5sum"
  fi

  local all_hashes=""

  # Hash Go source files
  if [[ -d "$MIGRATOR_DIR/src" ]]; then
    local go_hash
    go_hash=$(find "$MIGRATOR_DIR/src" -maxdepth 1 -type f \( \
      -name "*.go" \
    \) 2>/dev/null | sort | xargs cat 2>/dev/null | $hash_cmd | cut -d' ' -f1)
    all_hashes+="go:${go_hash}|"
  fi

  # Hash Go module files
  for file in "$MIGRATOR_DIR/src/go.mod" "$MIGRATOR_DIR/src/go.sum"; do
    if [[ -f "$file" ]]; then
      local file_hash
      file_hash=$($hash_cmd "$file" | cut -d' ' -f1)
      all_hashes+="$(basename "$file"):${file_hash}|"
    fi
  done

  # Hash SQL migration files
  if [[ -d "$MIGRATOR_DIR/migrations" ]]; then
    local sql_hash
    sql_hash=$(find "$MIGRATOR_DIR/migrations" -type f -name "*.sql" 2>/dev/null | sort | xargs cat 2>/dev/null | $hash_cmd | cut -d' ' -f1)
    all_hashes+="migrations:${sql_hash}|"
  fi

  # Combine all hashes into final hash
  local final_hash
  final_hash=$(echo "$all_hashes" | $hash_cmd | cut -d' ' -f1)

  echo "$final_hash"
}

show_hash_inputs() {
  echo "Files included in hash calculation:"
  echo "  Go source files:"
  find "$MIGRATOR_DIR/src" -maxdepth 1 -type f -name "*.go" 2>/dev/null | wc -l | xargs printf "    %s files in src/\n"

  echo "  Module files:"
  for file in go.mod go.sum; do
    if [[ -f "$MIGRATOR_DIR/src/$file" ]]; then
      echo "    $file"
    fi
  done

  echo "  Migration files:"
  find "$MIGRATOR_DIR/migrations" -type f -name "*.sql" 2>/dev/null | wc -l | xargs printf "    %s files in migrations/\n"
}

get_cached_hash() {
  if [[ -f "$HASH_FILE" ]]; then
    cat "$HASH_FILE"
  else
    echo ""
  fi
}

save_hash() {
  local hash="$1"
  echo "$hash" > "$HASH_FILE"
}

needs_rebuild() {
  if [[ "$FORCE_REBUILD" == "true" ]]; then
    echo "Force rebuild requested via FORCE_MIGRATOR_REBUILD=true"
    return 0
  fi

  local current_hash
  current_hash=$(calculate_source_hash)
  local cached_hash
  cached_hash=$(get_cached_hash)

  if [[ -z "$cached_hash" ]]; then
    echo "No cached hash found - initial build required"
    return 0
  fi

  if [[ "$current_hash" != "$cached_hash" ]]; then
    echo "Source changes detected (hash changed)"
    echo "  Previous: ${cached_hash:0:16}..."
    echo "  Current:  ${current_hash:0:16}..."
    return 0
  fi

  # Check if zip exists
  if [[ ! -f "$ZIP_FILE" ]]; then
    echo "Zip file missing - rebuild required"
    return 0
  fi

  return 1
}

build_migrator() {
  echo "Compiling Go binary (linux/arm64)..."
  cd "$MIGRATOR_DIR/src"
  go mod tidy
  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o bootstrap main.go
}

package_migrator() {
  echo "Packaging goose-migrator..."
  cd "$MIGRATOR_DIR"

  # Remove existing zip if present
  rm -f "$ZIP_FILE"

  # Create zip: bootstrap binary at root + migrations/ directory
  zip -j "$ZIP_FILE" src/bootstrap
  zip -r "$ZIP_FILE" migrations/

  echo "  Created: $ZIP_FILE ($(du -h "$ZIP_FILE" | cut -f1))"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

echo "=========================================="
echo "Goose Migrator Build Script"
echo "=========================================="
echo "Migrator directory: $MIGRATOR_DIR"
echo "Cache directory:    $CACHE_DIR"
echo ""

# Show what's being tracked for changes
show_hash_inputs
echo ""

# Check if rebuild is needed
if needs_rebuild; then
  echo ""
  echo "Starting build process..."
  echo ""

  # Capture start time
  start_time=$(date +%s)

  # Run build steps
  build_migrator
  package_migrator

  # Calculate and save new hash
  new_hash=$(calculate_source_hash)
  save_hash "$new_hash"

  # Calculate duration
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  echo ""
  echo "=========================================="
  echo "Goose migrator build complete! (${duration}s)"
  echo "Hash: ${new_hash:0:16}..."
  echo "=========================================="

  # Log build info
  {
    echo "Build completed: $(date -Iseconds)"
    echo "Duration: ${duration}s"
    echo "Hash: $new_hash"
  } > "$BUILD_LOG"
else
  echo ""
  echo "=========================================="
  echo "No changes detected - skipping build"
  echo "=========================================="

  if [[ -f "$BUILD_LOG" ]]; then
    echo ""
    echo "Last build info:"
    cat "$BUILD_LOG"
  fi
fi

echo ""
