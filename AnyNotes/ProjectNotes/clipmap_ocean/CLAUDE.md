# ext-fx-water-system

Water rendering and simulation module for the rays-engine. Provides ocean/lake surfaces, FFT-based wave simulation, underwater effects, screen-space reflections, fluid dynamics, and physical water interactions.

## Build

```bash
# Development (RelWithDebInfo)
cmake --preset development
cmake --build build/development

# Release
cmake --preset release
cmake --build build/release
```

Other presets: `engine-dev`, `engine-release`, `release-small`.

CMake delegates to `core/build.cmake` — do not modify `CMakeLists.txt` directly.

## Architecture

### Rendering Pipeline
Pass-based: each rendering step is a distinct Pass class (`Ocean_Pass`, `Lake_Pass`, `Underwater_Pass`, `Caustics_Pass`, `Wave_Height_Pass`, etc.). Effect graphs are declared in `.fxg` files under `asset/ext-fx-water-system/effect/`.

### Scene Services
Major features are implemented as `Scene_Service` subclasses (e.g. `Wave_Service`, `Fluids_Simulation_Service`). Services respond to lifecycle callbacks: `enable_service`, `on_post_attach_trait`, `on_pre_detach_trait`, `on_save`, `on_load`.

### Trait System
Configuration is attached to scene nodes as traits (e.g. `Ocean_Mesh_Config`, `Wave_Config`, `Water_Material_Config`). Traits use `CCTT_INTROSPECT` macros for serialization and editor integration.

### Wave Simulation
- **Gerstner Waves**: Procedural procedural generation for ocean surfaces
- **FFT Spectrum**: Frequency-domain simulation (`fft/`)
- **Dynamic Waves**: Real-time disturbance from object interaction
- **Fluid Height Fields**: CPU-based 2D simulation for lakes/ponds (`fluids-simulation-pass`)

## Source Layout

```
source/ext-fx-water-system/
├── action/               # Scene action imports
├── trait/                # Config trait definitions
├── service/              # Scene services
├── editor/               # Editor integration
├── cascade-data/         # Hierarchical data management
├── screen-space-reflection/
├── fft/                  # FFT wave spectrum
├── util/
├── ocean-pass.*          # Ocean surface rendering
├── lake-pass.*           # Lake surface rendering
├── underwater-pass.*     # Underwater effects
├── fluids-simulation-pass.*
├── caustics-pass.*
├── wave-height-pass.*
├── light-shaft-animation-pass.*
├── top-view-pass.*
└── init.cpp
```

Optional modules (conditionally compiled):
- `source-physical-interaction/` — sphere-water collisions, floating objects
- `source-checking-box/` — debug bounding box visualization

## Compile Flags

Defined in `manifest.txt` and feature manifests:

| Flag | Default | Purpose |
|---|---|---|
| `SS_EXT_WATER_SYSTEM_USE_ATMOSPHERE_SUN` | 1 | Atmospheric sun integration |
| `SS_EXT_WATER_SYSTEM_IDFT_COMPUTE_TYPE` | 0 | IDFT computation method |
| `SS_EXT_WATER_SYSTEM_DEBUG_MODE` | 0 | Debug visualization |
| `SS_EXT_WATER_SYSTEM_USE_MORPHA_UI` | 0 | UI framework selection |
| `SS_EXT_WATER_SYSTEM_USE_GRAND_TERRAIN` | — | Shoreline wave attenuation (requires `ext-fx-grand-terrain`) |
| `SS_EXT_WATER_SYSTEM_PHYSICAL_INTERACTION` | — | Physical interactions (requires `ext-svc-physics`) |
| `SS_EXT_WATER_SYSTEM_CHECKING_BOX` | — | Debug checking box |

Feature manifests: `manifest-physical-interaction.txt`, `manifest-checking-box.txt`, `manifest-shoreline-wave-attenuation.txt`.

## Key Dependencies

- `core` / `core-base` — rays-engine scene graph, math, resource management
- `ext-fx-standard-pipeline` — Lighting, G-buffers, IBL
- `ext-action-import-via-assimp` — Model import
- `ext-fx-grand-terrain` — Shoreline integration (optional)
- `ext-svc-physics` — Physical interactions (optional)

## Shaders & Effects

GLSL shaders live under `asset/ext-fx-water-system/`. Effect pipelines (`.fxg`):
- `water-system.fxg` — Main water rendering
- `fft.fxg` — FFT wave spectrum
- `fluids.fxg` — Fluid simulation
- `underwater.fxg` — Underwater effects
- `ssr.fxg` — Screen-space reflections
- `caustics.fxg`, `dynamic-wave.fxg`, `top-view-pipeline.fxg`, `bypass.fxg`

## Current Branch

`feature/river` — active development of river system pipeline.