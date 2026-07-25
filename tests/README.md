# TAPSHOP tests

Helper-level Lua harness for the macOS implementation (`TAPSHOP-macos/`).

These tests exercise state, services, hotkeys, persistence, and UI controllers against a fake `hs` shim. They do **not** drive live Hammerspoon, Accessibility, real hotkey registration, or end-to-end desktop focus timing.

There is no Windows automated suite yet.

## Run

From the **repository root**:

```bash
./tests/run-macos.sh
```

Or directly:

```bash
lua tests/macos/run.lua
```

Focused app-restart recovery edges only:

```bash
lua tests/macos/run_app_restart_edge_recovery.lua
```

### Requirements

- A Lua runtime (`lua`, `lua5.4` / `lua5.3`, or `luajit`), or a working Hammerspoon CLI (`hs`) with IPC enabled
- Optional overrides: `LUA_BIN`, `HS_BIN`

Success: process exits `0` and prints `PASS …` lines. Any failure prints to stderr and exits `1`.

## Layout

```text
tests/
├── README.md                 # This file
├── run-macos.sh              # Finds lua/hs and runs the full macOS suite
├── helpers/                  # Shared fakes and runner utilities
│   ├── assert.lua
│   ├── fake_hs.lua           # Minimal Hammerspoon shim
│   ├── fakes.lua             # Settings, window, and service fakes
│   ├── temp_dir.lua          # Temp data-dir helpers for on-disk tests
│   ├── test_env.lua          # Module reset between cases
│   └── test_runner.lua
└── macos/
    ├── _bootstrap.lua        # Shared package.path setup
    ├── run.lua               # Full suite entrypoint
    ├── run_app_restart_edge_recovery.lua
    └── *_spec.lua            # Spec modules
```

## What the suite covers

Registered by `tests/macos/run.lua`:

| Spec | What it covers |
| --- | --- |
| `debug_logger_spec` | Debug logger enable/disable, redaction, filters, launch-arm, JSON edges |
| `toast_spec` | Toast stacking, expiry, cap eviction, styled segments |
| `panel_layout_spec` | Shared popover/settings geometry clamp and frame helpers |
| `popover_spec` | Popover refresh/coalesce, header-only active-window updates, AOT `toggleOrFocus`, UI auto-hide |
| `popover_fullscreen_visibility_spec` | Hide-during-fullscreens pin/restore/settle and intentional dismiss |
| `settings_window_spec` | Settings cache warm, hotkeys-tab layout, validation/commit, toggleOrFocus |
| `workspace_spec` | Slot pair/clear, recoverable metadata, minimize threshold, fullscreen tracking |
| `slot_row_spec` | Popover row projection for empty / minimized / fullscreen / off-space / recoverable states |
| `app_state_spec` | Pairing, Space routing, recovery, focus UI coalesce, profile persistence, fullscreen hide wiring |
| `settings_store_spec` | Settings/appdata bootstrap, hotkey override sanitize, legacy migrate, corruption recovery |
| `real_appdata_restart_spec` | On-disk restart rematch of an already-open window without restore toasts |
| `window_service_spec` | Frontmost helpers, cross-Space focus settle/backoff/cancel/timeout |
| `youtube_service_spec` | YouTube target detection and key dispatch |
| `hotkey_conflicts_spec` | Combo normalization and conflict detection |
| `hotkey_manager_spec` | Bind/remap/clear/reset, fallback reservation, system-key dispatch |

Separate focused runner (not in the full suite):

| Spec | What it covers |
| --- | --- |
| `app_restart_edge_recovery_spec` | Minimized / off-space / fullscreen restore edges and recoverable relink behavior |

The tables above are indicative. For the live case list and exact assertions, open the named `*_spec.lua` files — they are the source of truth for what the harness currently locks.
