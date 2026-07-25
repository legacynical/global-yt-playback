#!/bin/sh
# Convenience launcher for the macOS Lua harness.
# Prefer: lua tests/macos/run.lua
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$ROOT_DIR"

for candidate in "${LUA_BIN:-}" lua lua5.4 lua5.3 luajit; do
  if [ -n "${candidate}" ] && command -v "$candidate" >/dev/null 2>&1; then
    exec "$(command -v "$candidate")" ./tests/macos/run.lua
  fi
done

if [ -n "${HS_BIN:-}" ]; then
  RUNNER="$HS_BIN"
elif command -v hs >/dev/null 2>&1; then
  RUNNER=$(command -v hs)
elif [ -x /opt/homebrew/bin/hs ]; then
  RUNNER=/opt/homebrew/bin/hs
else
  echo "No Lua runner found. Install lua/luajit, or set HS_BIN to a working Hammerspoon CLI." >&2
  exit 1
fi

if "$RUNNER" -c 'return true' >/dev/null 2>&1; then
  exec "$RUNNER" ./tests/macos/run.lua
fi

echo "Hammerspoon CLI is installed but not reachable." >&2
echo "Load the ipc module in ~/.hammerspoon/init.lua (for example: require(\"hs.ipc\")) or install a standalone lua binary." >&2
exit 1
