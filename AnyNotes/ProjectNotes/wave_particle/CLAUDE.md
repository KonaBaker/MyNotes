# ext-fx-river-system

A Rays Engine extension implementing CDLOD (Continuous Distance-based Level-of-Detail) terrain rendering for river/water surfaces. Part of the `ext-fx-water-system` workspace.

## Architecture

The extension follows the Rays Engine service/trait/pass pattern:

- **Service** (`service/`) — Manages `Cdlod_Config` traits on scene nodes; handles attach/detach/mutate lifecycle events.
- **Pass** (`pass/`) — `Cdlod_Pass` performs LOD selection and submits the render queue each frame.
- **Trait** (`trait/`) — `Cdlod_Config` holds per-node configuration with CCTT introspection metadata (GUI hints, serialization).
- **Action** (`action/`) — `Import_Cdlod` attaches `Cdlod_Config` to nodes during scene import.
- **Mesh** (`mesh/`) — Quad-tree spatial structure, AABB, LOD selection algorithm, and patch mesh generation.
- **Pipeline data provider** (`pipeline-data-provider.*`) — Extracts camera data and forwards it to the CDLOD pass.

Entry point: `source/ext-fx-river-system/init.cpp` — registers the camera data provider, loads effect graphs, and enables `Cdlod_Service`.

## Key Files

| Path | Role |
|------|------|
| `source/.../init.cpp` | Extension initialization and registration |
| `source/.../pass/cdlod-pass.cpp` | Main rendering pass (LOD selection, draw calls) |
| `source/.../service/cdlod-service.cpp` | Scene trait lifecycle management |
| `source/.../mesh/lod-selection.*` | CDLOD LOD selection algorithm |
| `source/.../mesh/quad-tree.*` | Spatial quad-tree partitioning |
| `source/.../trait/cdlod-config.hpp` | Configuration trait with CCTT introspection |
| `asset/.../shader/cdlod-vert.glsl` | Vertex shader (morph, LOD patch instancing) |
| `asset/.../shader/cdlod-frag.glsl` | Fragment shader (debug modes: LOD color, wireframe, height) |
| `asset/.../effect/cdlod.fxg` | CDLOD effect graph |
| `asset/.../effect/river-system.fxg` | Top-level river system pipeline composition |

## Build

Built via the `rsbuild` CMake system from the parent workspace (`ext-fx-water-system/`). Do not build this extension in isolation.

```bash
# From ext-fx-water-system/
cmake --preset development   # RelWithDebInfo, native compiler
cmake --preset engine-dev    # RelWithDebInfo, engine-dev config
cmake --preset release       # Release
cmake --build build/development
```

Generator: Ninja. Build type is always `RelWithDebInfo` for development (never plain `Debug`).

Dependencies declared in `manifest.txt`:
- `ext-action-import-via-assimp`
- `ext-fx-standard-pipeline`
- `ext-milicon`

## Coding Conventions

**Naming:**
- Classes/structs: `PascalCase` (e.g., `Cdlod_Pass`, `Selected_Patch`)
- Functions/variables: `snake_case`
- Implementation structs: `Foo_Impl` (nested in `.cpp` via pimpl pattern)
- Namespace: `ss::ext_fx_river_system`, subnamespaces for `scene_action`

**Patterns:**
- Pimpl via `core::Opaque<T>` — keep heavy implementation details out of headers
- `core::Pinned` — mark types that must not be copied
- `CCTT_INTROSPECT()` macro — required on all configurable trait fields for GUI/serialization
- Guard macros: `SS_UNLIKELY()`, `SS_BUG()` for error paths
- OpenGL ES compatibility: use `#ifndef` guards around desktop-only GL features

**Files:**
- `.hpp` for declarations, `.cpp` for implementations — no inline implementations in headers unless trivial
- Asset configs (`.json`, `.fxg`) live under `asset/ext-fx-river-system/`, mirroring the source namespace

## Shader Conventions

Vertex attributes passed as instanced arrays: `CDLOD_PATCH`, `CDLOD_MORPH`, `CDLOD_HEIGHT`.

Debug modes toggled via shader macros (set dynamically in `Cdlod_Pass`):
- `CDLOD_DEBUG_LOD_COLOR` — color patches by LOD level
- `CDLOD_DEBUG_WIREFRAME` — wireframe overlay
- `CDLOD_DEBUG_HEIGHT` — visualize heightmap values
- `CDLOD_DEBUG_WAVE_PARTICLE` — visualize wave particle map

Reserved (not yet active): `enable_wave_particle`, `wave_particle_displace_scale`, `wave_particle_normal_strength`.