# =============================================================================
# sirius-rocm — Top-level CMake overlay for building Sirius with ROCm/HIP.
#
# This is NOT a standalone project. It wraps the sirius-db/sirius submodule
# (at sirius/) with the ROCm-specific build options, so you don't have to
# pass 10 -D flags on the command line.
#
# Usage:
#   ./scripts/setup.sh           # init submodule + apply patches
#   ./scripts/build_rocm_deps.sh # build hipDF + hipMM
#   cmake -B build -S .          # configure (this file)
#   cmake --build build -j$(nproc) --target duckdb sirius_extension
#
# The submodule's own CMakeLists.txt (after patching) contains the ENABLE_ROCM
# logic, FetchContent for cuda2rocm, roctx discovery, etc. This file just
# sets the defaults.
# =============================================================================

cmake_minimum_required(VERSION 3.30 FATAL_ERROR)

# Default ROCm-specific options — can be overridden via -D on the command line.
set(ENABLE_ROCM              ON  CACHE BOOL "Build with AMD ROCm/HIP backend" FORCE)
set(SIRIUS_ENABLE_CUCO       OFF CACHE BOOL "cuCollections (NVIDIA-only)" FORCE)
set(SIRIUS_ENABLE_CUCASCADE  OFF CACHE BOOL "cuCascade submodule (NVIDIA-only)" FORCE)
set(SIRIUS_BUILD_S3_TESTS    OFF CACHE BOOL "S3 integration tests (needs Go)" FORCE)
set(SIRIUS_BUILD_TELEMETRY   OFF CACHE BOOL "Telemetry bridge (needs Rust)" FORCE)
set(EXTENSION_STATIC_BUILD   ON  CACHE BOOL "Link sirius into duckdb binary" FORCE)

# Auto-detect GPU architecture via rocminfo (works on any AMD GPU).
# Override with -DCMAKE_HIP_ARCHITECTURES=gfx90a etc. if needed.
if(NOT DEFINED CMAKE_HIP_ARCHITECTURES)
  execute_process(
    COMMAND rocminfo
    OUTPUT_VARIABLE _rocminfo_output
    ERROR_QUIET
    RESULT_VARIABLE _rocminfo_result)
  if(_rocminfo_result EQUAL 0 AND _rocminfo_output MATCHES "gfx[0-9]+[a-z]?[0-9]*")
    set(CMAKE_HIP_ARCHITECTURES "native" CACHE STRING "AMD GPU architecture (auto-detected)" FORCE)
    message(STATUS "CMAKE_HIP_ARCHITECTURES: auto-detected via rocminfo (native)")
  else()
    set(CMAKE_HIP_ARCHITECTURES "gfx942" CACHE STRING "AMD GPU architecture" FORCE)
    message(STATUS "CMAKE_HIP_ARCHITECTURES: no GPU detected, defaulting to gfx942")
  endif()
endif()

# Use hipcc as the compiler (wraps clang++ with HIP target flags).
if(NOT DEFINED CMAKE_CXX_COMPILER)
  set(CMAKE_CXX_COMPILER "hipcc" CACHE STRING "C++ compiler" FORCE)
endif()
if(NOT DEFINED CMAKE_C_COMPILER)
  set(CMAKE_C_COMPILER "hipcc" CACHE STRING "C compiler" FORCE)
endif()

# Ensure /opt/rocm is on the search path for hipDF + hipMM cmake configs.
list(APPEND CMAKE_PREFIX_PATH "/opt/rocm")

# Now delegate to the patched Sirius submodule.
add_subdirectory(sirius)
