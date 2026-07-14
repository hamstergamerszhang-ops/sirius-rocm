#!/usr/bin/env bash
# =============================================================================
# setup.sh — Initialize the Sirius submodule and apply ROCm source patches.
#
# This must be run once after cloning sirius-rocm, and again after any
# update to the submodule pin or the patch files.
#
# Usage:
#   ./scripts/setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMODULE_DIR="$REPO_DIR/sirius"

echo "=== sirius-rocm setup ==="

# -----------------------------------------------------------------------------
# Step 1: Initialize the Sirius submodule
# -----------------------------------------------------------------------------
echo "Step 1: Initializing Sirius submodule..."
cd "$REPO_DIR"
git submodule update --init --recursive sirius
echo "  Submodule at: $(cd sirius && git rev-parse HEAD)"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Apply ROCm source patches
# -----------------------------------------------------------------------------
echo "Step 2: Applying ROCm source patches..."
cd "$SUBMODULE_DIR"

PATCH_DIR="$REPO_DIR/patches"
APPLIED=0
FAILED=0

for patch in "$PATCH_DIR"/*.patch; do
  [ -f "$patch" ] || continue
  patch_name=$(basename "$patch")
  echo -n "  Applying $patch_name... "

  # Check if already applied (reverse applies cleanly = already applied)
  if git apply --reverse --check "$patch" 2>/dev/null; then
    echo "SKIP (already applied)"
    continue
  fi

  # Try forward apply
  if git apply "$patch" 2>/dev/null; then
    echo "OK"
    APPLIED=$((APPLIED + 1))
  else
    echo "FAILED"
    echo "    Manual resolution may be needed."
    FAILED=$((FAILED + 1))
  fi
done

echo "  Applied: $APPLIED, Failed: $FAILED, Skipped: (already applied)"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Initialize Sirius's own submodules (duckdb, substrait, etc.)
# -----------------------------------------------------------------------------
echo "Step 3: Initializing Sirius sub-submodules..."
cd "$SUBMODULE_DIR"
# Only init the ones needed for the build (not all of them — some are huge)
git submodule init duckdb substrait 2>/dev/null || true
git submodule update --depth 1 duckdb substrait 2>/dev/null || true
echo "  Done"
echo ""

# -----------------------------------------------------------------------------
# Step 4: Verify hipDF + hipMM are installed (informational)
# -----------------------------------------------------------------------------
echo "Step 4: Checking for hipDF + hipMM..."
if find /opt/rocm -name "libcudf*" 2>/dev/null | grep -q .; then
  echo "  hipDF: FOUND"
else
  echo "  hipDF: NOT FOUND — run ./scripts/build_rocm_deps.sh"
fi
if find /opt/rocm -name "librmm*" 2>/dev/null | grep -q .; then
  echo "  hipMM: FOUND"
else
  echo "  hipMM: NOT FOUND — run ./scripts/build_rocm_deps.sh"
fi
echo ""

echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. ./scripts/build_rocm_deps.sh    # build hipDF + hipMM (if not installed)"
echo "  2. cmake -B build -S .             # configure Sirius with ROCm"
echo "  3. cmake --build build -j\$(nproc) --target duckdb sirius_extension"
echo "  4. ./scripts/run_tpch_rocm.sh      # run TPC-H benchmarks"
