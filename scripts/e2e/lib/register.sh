#!/usr/bin/env bash
# scripts/e2e/lib/register.sh - ephemeral Obsidian vault registration.
# Restores obsidian.json from a full-file backup. Requires jq.
# Bash 3.2. No set -e. No emoji. Source this file; do not execute.

e2e_obsidian_json() {
  local f
  for f in \
    "$HOME/Library/Application Support/obsidian/obsidian.json" \
    "$HOME/.config/obsidian/obsidian.json"; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

e2e_register_vault() {
  local f id ts tmp
  command -v jq >/dev/null 2>&1 || {
    printf 'e2e: jq required to register vault for cli phase\n' >&2
    return 1
  }
  f="$(e2e_obsidian_json)" || {
    printf 'e2e: obsidian.json not found; cannot enter cli mode\n' >&2
    return 1
  }
  E2E_OBSIDIAN_JSON="$f"
  E2E_OBSIDIAN_BAK="$E2E_ROOT/obsidian.json.bak"
  cp "$f" "$E2E_OBSIDIAN_BAK" || return 1
  id="memovault-e2e"
  ts="$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || printf '%s000' "$(date +%s)")"
  tmp="$(mktemp)"
  # Replace any prior memovault-e2e id while preserving other top-level keys in obsidian.json.
  jq --arg id "$id" --arg path "$E2E_VAULT" --argjson ts "$ts" \
    '(.vaults) |= ((. // {}) | del(.[$id]) | . + {($id): {path:$path, ts:$ts, open:false}})' \
    "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  E2E_REGISTERED=1
  printf 'e2e: registered vault id=%s path=%s\n' "$id" "$E2E_VAULT" >&2
}

e2e_unregister_vault() {
  [ "${E2E_REGISTERED:-0}" = 1 ] || return 0
  [ -n "${E2E_OBSIDIAN_BAK:-}" ] && [ -f "$E2E_OBSIDIAN_BAK" ] || return 0
  [ -n "${E2E_OBSIDIAN_JSON:-}" ] || return 0
  cp "$E2E_OBSIDIAN_BAK" "$E2E_OBSIDIAN_JSON" || {
    printf 'e2e: failed to restore obsidian.json from backup\n' >&2
    return 1
  }
  E2E_REGISTERED=0
  printf 'e2e: restored obsidian.json from backup\n' >&2
}
