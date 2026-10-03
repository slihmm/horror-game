#!/bin/bash
# Installs the toolchain used by scripts/check.sh and scripts/test.sh
# (Rojo, luau-lsp + Roblox type definitions, Lune) in cloud sessions.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install_zip() { # name url
  local name="$1" url="$2"
  if [ ! -x "$BIN/$name" ]; then
    curl -sSfL -o "$TMP/$name.zip" "$url"
    unzip -o -q "$TMP/$name.zip" -d "$TMP/$name"
    install -m 755 "$(find "$TMP/$name" -type f -name "$name" | head -1)" "$BIN/$name"
  fi
}

install_zip rojo "https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip"
install_zip luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip"
install_zip lune "https://github.com/lune-org/lune/releases/download/v0.8.9/lune-0.8.9-linux-x86_64.zip"

DEFS="$CLAUDE_PROJECT_DIR/.tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
  mkdir -p "$(dirname "$DEFS")"
  curl -sSfL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
