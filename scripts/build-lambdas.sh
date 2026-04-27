#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build Lambdas Script
# Only rebuilds lambda functions when source code changes are detected.
# Uses content hashing to determine if a rebuild is necessary.
#
# Usage:
#   LAMBDAS_SOURCE_DIR=<path> LAMBDAS_CACHE_DIR=<path> NODE_ENV=production ./build-lambdas.sh
#
# Required environment variables:
#   LAMBDAS_SOURCE_DIR                Path to the lambdas source directory
#
# Optional environment variables:
#   LAMBDAS_CACHE_DIR                 Build cache directory (default: .lambda-build-cache)
#   NODE_ENV=production|development   Build mode (default: production, enables minification)
#   FORCE_LAMBDA_REBUILD=true         Force rebuild even if no changes detected
# -----------------------------------------------------------------------------

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration (from environment variables)
# -----------------------------------------------------------------------------
LAMBDAS_DIR_INPUT="${LAMBDAS_SOURCE_DIR:-}"
CACHE_DIR_INPUT="${LAMBDAS_CACHE_DIR:-.lambda-build-cache}"
FORCE_REBUILD="${FORCE_LAMBDA_REBUILD:-false}"
NODE_ENV="${NODE_ENV:-production}"

if [[ -z "$LAMBDAS_DIR_INPUT" ]]; then
  echo "Error: LAMBDAS_SOURCE_DIR is required"
  echo ""
  echo "Required environment variables:"
  echo "  LAMBDAS_SOURCE_DIR                  Path to the lambdas source directory"
  echo ""
  echo "Optional environment variables:"
  echo "  LAMBDAS_CACHE_DIR                   Build cache directory (default: .lambda-build-cache)"
  echo "  NODE_ENV=production|development     Build mode (default: production, enables minification)"
  echo "  FORCE_LAMBDA_REBUILD=true           Force rebuild even if no changes detected"
  exit 1
fi

# Resolve to absolute paths
if [[ ! -d "$LAMBDAS_DIR_INPUT" ]]; then
  echo "Error: Lambdas directory not found: $LAMBDAS_DIR_INPUT"
  exit 1
fi
LAMBDAS_DIR=$(cd "$LAMBDAS_DIR_INPUT" && pwd)
SERVICE_ROOT=$(dirname "$LAMBDAS_DIR")

# Create and resolve cache directory
mkdir -p "$CACHE_DIR_INPUT"
CACHE_DIR=$(cd "$CACHE_DIR_INPUT" && pwd)

# Cache file locations
HASH_FILE="$CACHE_DIR/lambdas.hash"
BUILD_LOG="$CACHE_DIR/last-build.log"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

calculate_source_hash() {
  # Calculate hash of all source files that affect the build:
  # - TypeScript/JavaScript source files (*.ts, *.js, *.mjs, *.cjs)
  # - JSON config files in src
  # - package.json and pnpm-lock.yaml (dependencies)
  # - tsconfig.json (build configuration)
  # - Build scripts

  local hash_cmd="sha256sum"
  if ! command -v sha256sum &> /dev/null; then
    hash_cmd="md5sum"
  fi

  local all_hashes=""

  # Hash all source code files
  # Find .ts, .js, .mjs, .cjs, .json files in src directory
  if [[ -d "$LAMBDAS_DIR/src" ]]; then
    local src_hash
    src_hash=$(find "$LAMBDAS_DIR/src" -type f \( \
      -name "*.ts" -o \
      -name "*.js" -o \
      -name "*.mjs" -o \
      -name "*.cjs" -o \
      -name "*.json" \
    \) 2>/dev/null | sort | xargs cat 2>/dev/null | $hash_cmd | cut -d' ' -f1)
    all_hashes+="src:${src_hash}|"
  fi

  # Hash build scripts
  if [[ -d "$LAMBDAS_DIR/scripts" ]]; then
    local scripts_hash
    scripts_hash=$(find "$LAMBDAS_DIR/scripts" -type f \( \
      -name "*.ts" -o \
      -name "*.js" -o \
      -name "*.mjs" \
    \) 2>/dev/null | sort | xargs cat 2>/dev/null | $hash_cmd | cut -d' ' -f1)
    all_hashes+="scripts:${scripts_hash}|"
  fi

  # Hash config files at root level
  for file in \
    "$LAMBDAS_DIR/package.json" \
    "$LAMBDAS_DIR/pnpm-lock.yaml" \
    "$LAMBDAS_DIR/tsconfig.json" \
    "$LAMBDAS_DIR/babel.config.cjs" \
    "$LAMBDAS_DIR/esbuild.config.js"; do
    if [[ -f "$file" ]]; then
      local file_hash
      file_hash=$($hash_cmd "$file" | cut -d' ' -f1)
      all_hashes+="$(basename "$file"):${file_hash}|"
    fi
  done

  # Combine all hashes into final hash
  local final_hash
  final_hash=$(echo "$all_hashes" | $hash_cmd | cut -d' ' -f1)

  echo "$final_hash"
}

# For debugging: show what files are being hashed
show_hash_inputs() {
  echo "Files included in hash calculation:"
  echo "  Source files:"
  find "$LAMBDAS_DIR/src" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.json" \) 2>/dev/null | wc -l | xargs printf "    %s files in src/\n"

  if [[ -d "$LAMBDAS_DIR/scripts" ]]; then
    find "$LAMBDAS_DIR/scripts" -type f \( -name "*.ts" -o -name "*.js" \) 2>/dev/null | wc -l | xargs printf "    %s files in scripts/\n"
  fi

  echo "  Config files:"
  for file in package.json pnpm-lock.yaml tsconfig.json babel.config.cjs; do
    if [[ -f "$LAMBDAS_DIR/$file" ]]; then
      echo "    $file"
    fi
  done
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
    echo "Force rebuild requested via FORCE_LAMBDA_REBUILD=true"
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

  # Also check if dist directory exists and has content
  if [[ ! -d "$LAMBDAS_DIR/dist" ]] || [[ -z "$(ls -A "$LAMBDAS_DIR/dist" 2>/dev/null)" ]]; then
    echo "Dist directory missing or empty - rebuild required"
    return 0
  fi

  # Check if all lambda zips exist
  for lambda_dist in "$LAMBDAS_DIR/dist"/*/; do
    if [[ -d "$lambda_dist" ]]; then
      local lambda_name
      lambda_name=$(basename "$lambda_dist")
      local zip_file="$LAMBDAS_DIR/src/$lambda_name/$lambda_name.zip"
      if [[ ! -f "$zip_file" ]]; then
        echo "Missing zip for $lambda_name - rebuild required"
        return 0
      fi
    fi
  done

  return 1
}

install_dependencies() {
  echo "Installing dependencies..."

  # Install root dependencies (if needed for shared libs)
  cd "$SERVICE_ROOT"
  if [[ -f "package.json" ]]; then
    pnpm install --silent 2>/dev/null || pnpm install
  fi

  # Install lambda dependencies
  cd "$LAMBDAS_DIR"
  pnpm install --frozen-lockfile --silent 2>/dev/null || pnpm install --silent 2>/dev/null || pnpm install
}

build_lambdas() {
  echo "Building lambdas (NODE_ENV=$NODE_ENV)..."
  cd "$LAMBDAS_DIR"

  # NODE_ENV controls minification in esbuild: production=minified, development=unminified+sourcemaps
  NODE_ENV="$NODE_ENV" pnpm --silent run build 2>/dev/null || NODE_ENV="$NODE_ENV" pnpm run build
}

package_lambdas() {
  echo "Packaging lambdas..."
  cd "$LAMBDAS_DIR"

  if [[ ! -d "dist" ]]; then
    echo "Error: dist directory not found after build"
    exit 1
  fi

  # Check if zip is available
  if ! command -v zip &> /dev/null; then
    echo "Warning: 'zip' command not found, attempting to install..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update -qq && sudo apt-get install -qq -y zip
    elif command -v apk &> /dev/null; then
      apk add --no-cache zip
    elif command -v yum &> /dev/null; then
      sudo yum install -y zip
    else
      echo "Error: Cannot install zip - no supported package manager found"
      exit 1
    fi
  fi

  local packaged=0
  for lambda_dist in dist/*/; do
    if [[ -d "$lambda_dist" ]]; then
      local lambda_name
      lambda_name=$(basename "$lambda_dist")

      if [[ -d "src/$lambda_name" ]]; then
        echo "  Packaging $lambda_name..."
        local zip_target="src/$lambda_name/$lambda_name.zip"

        # Remove existing zip if present
        rm -f "$zip_target"

        # Debug: show what we're zipping
        echo "    Source: dist/$lambda_name"
        echo "    Target: $zip_target"
        echo "    Files: $(find "dist/$lambda_name" -type f | wc -l)"

        # Create zip from dist directory (|| true to handle set -e)
        local zip_result=0
        (cd "dist/$lambda_name" && zip -r "../../$zip_target" . 2>&1) || zip_result=$?

        if [[ $zip_result -eq 0 ]] && [[ -f "$zip_target" ]]; then
          echo "    Created: $zip_target ($(du -h "$zip_target" | cut -f1))"
          packaged=$((packaged + 1))
        else
          echo "    Error: Failed to create $zip_target"
          exit 1
        fi
      else
        echo "  Skipping $lambda_name (no src directory)"
      fi
    fi
  done

  echo "Packaged $packaged lambda(s)"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

echo "=========================================="
echo "Lambda Build Script"
echo "=========================================="
echo "Lambdas directory: $LAMBDAS_DIR"
echo "Cache directory:   $CACHE_DIR"
echo ""

# Validate src directory exists
if [[ ! -d "$LAMBDAS_DIR/src" ]]; then
  echo "Error: No src directory found in $LAMBDAS_DIR"
  exit 1
fi

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
  install_dependencies
  build_lambdas
  package_lambdas

  # Calculate and save new hash
  new_hash=$(calculate_source_hash)
  save_hash "$new_hash"

  # Calculate duration
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  echo ""
  echo "=========================================="
  echo "Lambda build complete! (${duration}s)"
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
