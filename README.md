# sirius-rocm

Standalone **ROCm/HIP backend** for [Sirius](https://github.com/sirius-db/sirius) — the GPU-native SQL engine that intercepts DuckDB queries via Substrait and executes them on GPU.

## What this is

This repository provides everything needed to build and run Sirius on AMD ROCm/HIP hardware (MI300 / gfx942), without modifying the main Sirius codebase. It was spun out from [PR #1153](https://github.com/sirius-db/sirius/pull/1153) at the request of the upstream maintainer (Xiangyao Yu), who wants the ROCm backend developed separately to avoid burdening the main repo with dual CUDA/ROCm maintenance.

### Architecture

```
sirius-rocm/
├── CMakeLists.txt              # Top-level overlay: sets ENABLE_ROCM + delegates to submodule
├── sirius/                     # Git submodule → sirius-db/sirius (pinned commit)
├── patches/
│   ├── rocm-source-fixes.patch         # Committed ROCm changes (CMakeLists, pixi.toml, shuffle masks)
│   └── rocm-uncommitted-fixes.patch    # Latest ROCm fixes (bitpacking lane, find_package(rmm), build scripts)
├── scripts/
│   ├── setup.sh                # Init submodule + apply patches
│   ├── build_rocm_deps.sh      # Build + install hipDF (cuDF for HIP) + hipMM (RMM for HIP)
│   ├── hipdf_26.06_api_patch.sh # Patch hipDF 25.10 with cuDF 26.06 APIs Sirius needs
│   └── run_tpch_rocm.sh        # End-to-end TPC-H: build → generate data → run 22 queries
├── .github/workflows/
│   └── rocm-test.yml           # CI: shim compile-test on ubuntu-latest
├── PORTING.md                  # Engineering reference: component architecture, shim design, build fixes
└── README.md                   # This file
```

### Dependencies

| Dependency | Source | How consumed |
|---|---|---|
| [sirius-db/sirius](https://github.com/sirius-db/sirius) | Git submodule | Pinned to commit `e88da526` |
| [cuda2rocm](https://github.com/hamstergamerszhang-ops/cuda2rocm) | GitHub | CMake FetchContent (pinned URL + SHA256) |
| [hipDF](https://github.com/ROCm-DS/hipDF) (cuDF for HIP) | Built from source | `build_rocm_deps.sh` → `/opt/rocm` |
| [hipMM](https://github.com/ROCm-DS/hipMM) (RMM for HIP) | Built from source | `build_rocm_deps.sh` → `/opt/rocm` |
| ROCm 7.2.1+ (hipCUB, rocThrust, rocPRIM) | System install | `find_package` / system paths |

## Relationship to sirius-db/sirius and PR #1153

- **PR #1153** remains open as the discussion thread with the upstream maintainer. It is **not** modified by this repo.
- This repo is the **standalone development home** for the ROCm backend, per the maintainer's request.
- The Sirius source is consumed as a **git submodule** (not a fork), so there's no code duplication or drift.
- Source patches (64-bit shuffle masks, CMakeLists ROCm blocks, etc.) are applied via `scripts/setup.sh` — they're additive and gated by `ENABLE_ROCM=ON`, so they don't affect the CUDA build path.

## Current status

| Component | Status |
|---|---|
| CUDA→HIP compat shims (cuda2rocm) | ✅ 0 compile errors on gfx942/ROCm 7.2.1 |
| cuco-rocm (bloom_filter, static_set) | ✅ GPU tests pass: 7/7 bloom, 6/6 set, ~3M keys/s |
| hipMM (RMM for HIP) | ✅ Built + installed to `/opt/rocm` on real gfx942 |
| hipDF (cuDF for HIP) | 🔧 Build in progress — 5 hardware-specific fixes applied |
| Sirius end-to-end build | 🔧 Not yet built (blocked on hipDF completion) |
| TPC-H benchmark | ❌ Not yet run |

### Build fixes discovered on real hardware (gfx942 / ROCm 7.2.1)

1. **hipcc as C/CXX compiler** — hipMM's `.cpp` files need `-x hip --offload-arch` (plain `g++` fails)
2. **`git config http.version HTTP/1.1`** — fixes flaky GitHub clones on DSW pods
3. **`ROCM_AMDGPU_TARGETS=gfx942` env** — avoids rapids_cmake architecture mismatch
4. **Pre-clone all 16 CPM deps** — correct branch names from rapids-cmake `versions.json`
5. **Patch `get_rmm.cmake`** — use `find_package(rmm)` instead of CPM re-fetch (avoids rapids_logger conflict)

See `PORTING.md` §8 for full details.

## Quick start

```bash
# Clone
git clone --recursive https://github.com/hamstergamerszhang-ops/sirius-rocm.git
cd sirius-rocm

# Apply ROCm patches to the Sirius submodule
./scripts/setup.sh

# Build hipDF + hipMM (one-time, ~30 min)
./scripts/build_rocm_deps.sh

# Build Sirius with ROCm
cmake -B build -S .
cmake --build build -j$(nproc) --target duckdb sirius_extension

# Run TPC-H
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
./scripts/run_tpch_rocm.sh --scale-factor 1
```

## Path to adoption

1. **Complete hipDF build** on a stable AMD box (the 5 build fixes are applied — needs a box that doesn't get recycled mid-build)
2. **Build Sirius end-to-end** with `ENABLE_ROCM=ON`
3. **Run TPC-H** on real gfx942 hardware — demonstrate correctness + performance
4. **Potential hosting under `sirius-db/sirius-rocm`** — the upstream maintainer is open to hosting once TPC-H benchmarks pass on real hardware

## License

Apache-2.0, matching [Sirius](https://github.com/sirius-db/sirius), [cuDF/hipDF](https://github.com/ROCm-DS/hipDF), [RMM/hipMM](https://github.com/ROCm-DS/hipMM), and [cuda2rocm](https://github.com/hamstergamerszhang-ops/cuda2rocm).
