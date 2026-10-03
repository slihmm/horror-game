#!/usr/bin/env bash
# Static verification: builds the place with Rojo and type-checks every script
# against the Roblox API definitions using luau-lsp.
#   ROJO, LUAU_LSP and ROBLOX_DEFS can point at local tool installs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROJO="${ROJO:-rojo}"
LUAU_LSP="${LUAU_LSP:-luau-lsp}"
DEFS="${ROBLOX_DEFS:-.tools/globalTypes.d.luau}"
if [ ! -f "$DEFS" ]; then
  mkdir -p "$(dirname "$DEFS")"
  curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
"$ROJO" sourcemap default.project.json --output sourcemap.json
mkdir -p build
"$ROJO" build default.project.json --output build/Descent.rbxlx
"$LUAU_LSP" analyze --sourcemap=sourcemap.json --definitions="$DEFS" --flag:LuauSolverV2=false src
echo "check passed"
