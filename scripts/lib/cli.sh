#!/usr/bin/env bash
# lib/cli.sh - official Obsidian CLI layer for MemoVault.
# Requires the Obsidian desktop app running and the `obsidian` binary on PATH
# (Settings -> General -> Command line interface, installer 1.12.7+).
# Operations run with cwd = $MM_VAULT so the CLI selects the vault by working
# directory.

# Locate the obsidian binary. Print path or return 1.
mmcli_bin() {
  local b
  for b in \
    "$(command -v obsidian 2>/dev/null)" \
    "/usr/local/bin/obsidian" \
    "$HOME/.local/bin/obsidian" \
    "/Applications/Obsidian.app/Contents/MacOS/obsidian-cli"; do
    [ -n "$b" ] && [ -x "$b" ] && { printf '%s' "$b"; return 0; }
  done
  return 1
}

# Is the Obsidian desktop app running?
mmcli_app_running() {
  pgrep -x Obsidian >/dev/null 2>&1 && return 0
  pgrep -x obsidian >/dev/null 2>&1 && return 0
  pgrep -fi 'Obsidian.app' >/dev/null 2>&1 && return 0
  return 1
}

# Functional probe: is the official CLI actually working?
# The genuine CLI answers `version` with a version token and exits 0. A GUI app
# masquerading on PATH, or a CLI whose vault is missing, returns an error
# string (e.g. "Vault not found.") and may exit 0, so we validate the output.
# We also guard against hangs by backgrounding with a manual timeout (no coreutils
# `timeout` dependency).
mmcli_probe_ok() {
  [ -n "${MM_OBSIDIAN:-}" ] || return 1
  local v tmp pid i rc
  tmp="$(mktemp)"
  "$MM_OBSIDIAN" version >"$tmp" 2>/dev/null &
  pid=$!
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 20 ] || break
    sleep 0.3
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$tmp"; return 1
  fi
  wait "$pid"; rc=$?
  v="$(cat "$tmp" 2>/dev/null)"; rm -f "$tmp"
  [ "$rc" -eq 0 ] || return 1
  [ -n "$v" ] || return 1
  case "$(printf '%s' "$v" | tr 'A-Z' 'a-z')" in
    *"not found"*) return 1 ;;
  esac
  printf '%s' "$v" | grep -Eq '[0-9]+\.[0-9]+' || return 1
  return 0
}

# Detect runtime mode. Sets globals: MM_OBSIDIAN, MM_APP_RUNNING, MM_MODE.
# cli mode requires: a binary, the app running, AND a functional probe success.
mmcli_detect() {
  MM_OBSIDIAN="$(mmcli_bin)"
  if mmcli_app_running; then MM_APP_RUNNING=1; else MM_APP_RUNNING=0; fi
  if [ -n "$MM_OBSIDIAN" ] && [ "$MM_APP_RUNNING" = 1 ] && mmcli_probe_ok; then
    MM_MODE=cli
  else
    MM_MODE=fs
  fi
}

# Run an obsidian command from inside the vault. Args passed verbatim.
mmcli_run() {
  ( cd "$MM_VAULT" && "$MM_OBSIDIAN" "$@" )
}

mmcli_search() {
  local q="$1"; shift
  local limit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: search <query>"
  if [ -n "$limit" ]; then
    mmcli_run search:context query="$q" limit="$limit" format=text
  else
    mmcli_run search:context query="$q" format=text
  fi
}

mmcli_tags() {
  mmcli_run tags counts
}

mmcli_tag() {
  local tag="$1"
  [ -n "$tag" ] || mm_die "usage: tag <name>"
  mmcli_run tag name="$tag" verbose
}

mmcli_backlinks() {
  local ref="$1"
  mmcli_run backlinks file="$ref" counts format=json
}

mmcli_links() {
  local ref="$1"
  mmcli_run links file="$ref"
}

mmcli_orphans() {
  mmcli_run orphans
}

mmcli_unresolved() {
  mmcli_run unresolved verbose
}

mmcli_move() {
  local ref="$1" to="$2"
  mmcli_run move file="$ref" to="$to"
}

mmcli_rename() {
  local ref="$1" newname="$2"
  mmcli_run rename file="$ref" name="$newname"
}

mmcli_set_prop() {
  local relpath="$1" name="$2" value="$3"
  mmcli_run property:set name="$name" value="$value" path="$relpath"
}
