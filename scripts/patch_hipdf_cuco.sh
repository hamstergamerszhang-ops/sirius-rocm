#!/usr/bin/env bash
# =============================================================================
# patch_hipdf_cuco.sh — Patch hipDF to work with hipCollections cuco.
#
# hipDF uses NVIDIA cuco internal APIs that differ from hipCollections.
# This script patches hipDF source files to use the hipCollections API.
#
# Usage: patch_hipdf_cuco.sh <hipDF-source-dir>
# =============================================================================

set -eo pipefail

HIPDF_DIR="${1:?Usage: $0 <hipDF-source-dir>}"
CUCO_INC="${2:-}"

# Find cuco include dir if not provided
if [ -z "$CUCO_INC" ]; then
  echo "ERROR: cuco include dir must be provided as second argument"
  exit 1
fi

echo "=== Patching hipDF for hipCollections cuco compatibility ==="
echo "  hipDF: $HIPDF_DIR"
echo "  cuco:  $CUCO_INC"

# Patch 1: Add valid_extent + make_valid_extent to cuco extent.cuh
EXTENT_FILE="$CUCO_INC/extent.cuh"
if [ -f "$EXTENT_FILE" ] && ! grep -q "valid_extent" "$EXTENT_FILE"; then
  echo "  Patching extent.cuh: adding valid_extent + make_valid_extent"
  sed -i '/^#include <cuco\/detail\/extent\/extent.inl>/i\
\
template <typename SizeType, std::size_t Extent = dynamic_extent>\
using valid_extent = extent<SizeType, Extent>;\
\
template <int32_t CGSize, int32_t BucketSize, typename SizeType, std::size_t N = dynamic_extent>\
[[nodiscard]] auto constexpr make_valid_extent(extent<SizeType, N> const& ext) {\
  return make_bucket_extent<CGSize, BucketSize, SizeType, N>(ext);\
}\
template <typename ProbingScheme, typename Storage, typename SizeType, std::size_t N = dynamic_extent>\
[[nodiscard]] auto constexpr make_valid_extent(SizeType size) {\
  return bucket_extent<SizeType, N>(size);\
}' "$EXTENT_FILE"
else
  echo "  extent.cuh: already has valid_extent"
fi

# Patch 2: Add <span> to hipDF files missing it
for f in src/jit/row_ir.hpp src/jit/row_ir.cpp \
         src/io/parquet/experimental/hybrid_scan.cpp \
         include/cudf/io/experimental/hybrid_scan.hpp \
         include/cudf/utilities/span.hpp \
         include/cudf/detail/jit/span.cuh; do
  full="$HIPDF_DIR/cpp/$f"
  if [ -f "$full" ] && ! grep -q '#include.*<span>' "$full"; then
    echo "  Patching $f: adding #include <span>"
    sed -i '1i #include <span>' "$full"
  fi
done

# Patch 3: Fix ZSTD typo
ZSTD_CMAKE="$HIPDF_DIR/cpp/cmake/thirdparty/get_zstd.cmake"
if [ -f "$ZSTD_CMAKE" ] && grep -q "ZSTD_STATIC_LINKING_ONLY=0N" "$ZSTD_CMAKE"; then
  echo "  Patching get_zstd.cmake: ZSTD_STATIC_LINKING_ONLY=0N → =0"
  sed -i 's/ZSTD_STATIC_LINKING_ONLY=0N/ZSTD_STATIC_LINKING_ONLY=0/' "$ZSTD_CMAKE"
fi

# Patch 4: Patch get_rmm.cmake to use find_package
RMM_CMAKE="$HIPDF_DIR/cpp/cmake/thirdparty/get_rmm.cmake"
if [ -f "$RMM_CMAKE" ] && ! grep -q "find_package(rmm" "$RMM_CMAKE"; then
  echo "  Patching get_rmm.cmake: find_package(rmm) instead of CPM"
  cat > "$RMM_CMAKE" << 'RMMEOF'
function(find_and_configure_rmm)
  find_package(rmm REQUIRED CONFIG)
endfunction()
find_and_configure_rmm()
RMMEOF
fi

# Patch 5: Check if static_set_ref has the right template params
# If hipCollections cuco's static_set_ref doesn't accept 6 template params,
# we need to add a compatibility wrapper. Check the actual signature:
STATIC_SET_REF="$CUCO_INC/static_set_ref.cuh"
if [ -f "$STATIC_SET_REF" ]; then
  # Count template params in the class declaration
  PARAM_COUNT=$(grep -m1 "template.*class static_set_ref\|class static_set_ref" "$STATIC_SET_REF" | grep -o "typename" | wc -l)
  echo "  static_set_ref template params: $PARAM_COUNT"
  if [ "$PARAM_COUNT" -lt 6 ]; then
    echo "  WARNING: static_set_ref has $PARAM_COUNT params, hipDF expects 6"
    echo "  hipDF groupby/hash code may not compile — needs manual porting"
  fi
fi

echo "=== hipDF cuco patch complete ==="
