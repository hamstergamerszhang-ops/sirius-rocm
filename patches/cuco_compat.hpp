// =============================================================================
// cuco NVIDIA API compatibility layer for hipCollections cuco.
//
// hipDF (release/rocmds-26.03) uses NVIDIA cuco APIs that don't exist in the
// hipCollections fork. This header adds the missing types/functions so hipDF
// compiles without modification.
//
// This file is injected into the cuco include path by build_rocm_deps.sh
// Step 0.5. It must be included after the hipCollections cuco headers.
// =============================================================================

#pragma once

// This header is intentionally empty — the actual patches are applied directly
// to extent.cuh and other cuco headers by build_rocm_deps.sh.
// This file exists so the include path is set up correctly.
