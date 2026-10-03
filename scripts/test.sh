#!/usr/bin/env bash
# Offline tests: builds the place, then runs the Lune specs in tests/.
#   LUNE and ROJO can point at local tool installs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROJO="${ROJO:-rojo}"
LUNE="${LUNE:-lune}"
mkdir -p build
"$ROJO" build default.project.json --output build/Descent.rbxlx
for spec in tests/*.spec.luau; do
  echo "== $spec"
  "$LUNE" run "$spec"
done
