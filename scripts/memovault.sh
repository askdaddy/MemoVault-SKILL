#!/usr/bin/env bash
# memovault.sh - MemoVault entry point.
# Preflight + runtime mode detection + subcommand dispatch.
# Pure local filesystem skill. Uses the official Obsidian CLI when the desktop
# app is running; falls back to plain filesystem operations otherwise.
# No emoji. Never writes outside $AGENT_MEMO_VAULT.

set -uo pipefail

# --- core utilities -------------------------------------------------------

mm_today() { date +%Y-%m-%d; }

mm_die() { printf 'memovault: %s\n' "$*" >&2; exit 1; }

mm_log() { printf 'memovault: %s\n' "$*" >&2; }

mm_resolve_root() {
  local src="${BASH_SOURCE[0]}"
  printf '%s' "$(cd "$(dirname "$src")" && pwd)"
}

# --- environment ----------------------------------------------------------

MM_ROOT="$(mm_resolve_root)"
MM_SOURCE="$(cd "$MM_ROOT/.." && pwd)"            # skill source dir
MM_VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"

# shellcheck source=lib/fs.sh
. "$MM_ROOT/lib/fs.sh"
# shellcheck source=lib/cli.sh
. "$MM_ROOT/lib/cli.sh"
# shellcheck source=lib/classify.sh
. "$MM_ROOT/lib/classify.sh"

mmcli_detect   # sets MM_OBSIDIAN, MM_APP_RUNNING, MM_MODE

# --- wrappers with cli -> fs fallback -------------------------------------

mm_w_search() {
  local q="$1"; shift
  if [ "$MM_MODE" = cli ]; then
    local out rc
    out="$(mmcli_search "$q" "$@" 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian search failed, using fs" >&2
  fi
  mmfs_search "$q" "$@"
}

mm_w_tags() {
  if [ "$MM_MODE" = cli ]; then
    local out rc; out="$(mmcli_tags 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian tags failed, using fs" >&2
  fi
  mmfs_tags
}

mm_w_tag() {
  local tag="$1"
  if [ "$MM_MODE" = cli ]; then
    local out rc; out="$(mmcli_tag "$tag" 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian tag failed, using fs" >&2
  fi
  mmfs_tag "$tag"
}

mm_w_backlinks() {
  local ref="$1"
  if [ "$MM_MODE" = cli ]; then
    local out rc; out="$(mmcli_backlinks "$ref" 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian backlinks failed, using fs" >&2
  fi
  mmfs_backlinks "$ref"
}

mm_w_links() {
  local ref="$1"
  if [ "$MM_MODE" = cli ]; then
    local out rc; out="$(mmcli_links "$ref" 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian links failed, using fs" >&2
  fi
  mmfs_links "$ref"
}

mm_w_orphans() {
  if [ "$MM_MODE" = cli ]; then
    local out rc; out="$(mmcli_orphans 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian orphans failed, using fs" >&2
  fi
  mmfs_orphans
}

mm_w_unresolved() {
  if [ "$MM_MODE" = cli ]; then
    local out rc; out="$(mmcli_unresolved 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    mm_log "obsidian unresolved failed, using fs" >&2
  fi
  mmfs_unresolved
}

mm_w_move() {
  local ref="$1" to="$2"
  if [ "$MM_MODE" = cli ]; then
    if mmcli_move "$ref" "$to" 2>/dev/null; then return 0; fi
    mm_log "obsidian move failed, using fs (links will NOT update)" >&2
  fi
  mmfs_move "$ref" "$to"
}

mm_w_rename() {
  local ref="$1" newname="$2"
  if [ "$MM_MODE" = cli ]; then
    if mmcli_rename "$ref" "$newname" 2>/dev/null; then return 0; fi
    mm_log "obsidian rename failed, using fs (links will NOT update)" >&2
  fi
  mmfs_rename "$ref" "$newname"
}

# --- preflight ------------------------------------------------------------

mm_preflight() {
  local app_state="stopped"
  [ "${MM_APP_RUNNING:-0}" = 1 ] && app_state="running"
  printf 'mode=%s vault=%s bin=%s app=%s\n' \
    "$MM_MODE" "$MM_VAULT" "${MM_OBSIDIAN:-}" "$app_state"
  printf 'source=%s\n' "$MM_SOURCE"
  if [ "$MM_MODE" = fs ]; then
    if [ -z "${MM_OBSIDIAN:-}" ]; then
      printf 'hint: obsidian CLI not found; install Obsidian 1.12.7+ and enable Settings -> General -> Command line interface\n' >&2
    elif [ "$app_state" = stopped ]; then
      printf 'hint: Obsidian app is not running; start it for cli mode (backlink graph, link-safe move)\n' >&2
    fi
  fi
}

# --- subcommand handlers --------------------------------------------------

mm_cmd_new() {
  local domain="$1" title="$2"; shift 2 2>/dev/null || true
  local tags="" body=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tags) tags="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  mmfs_new "$domain" "$title" "$tags" "$body"
}

mm_usage() {
  cat <<'USAGE'
memovault - sink knowledge into the local memo vault.

Resolve:
  preflight                     show mode (cli/fs), vault, obsidian binary, app state

Capture / edit:
  new <domain> <title> [--tags a,b] [--body "text"]
  append <note> "<markdown>"
  prepend <note> "<markdown>"   (inserted after frontmatter)
  read <note>
  daily                         show today's daily note
  daily:append "<line>"         append to today's daily note

Retrieve:
  search <query> [--limit N]    full text search
  tags                          all tags with counts
  tag <name> | by-tag <name>    notes bearing a tag
  by-heat                       notes grouped by heat tier

Graph:
  backlinks <note>              notes linking to this note
  links <note>                  notes this note links to
  orphans                       notes with no incoming links
  unresolved                    [[links]] pointing nowhere yet

Organize / curate:
  move <note> <folder-or-path>  (link-safe in cli mode)
  rename <note> "<New Title>"
  promote <note>                seedling -> growing -> evergreen
  moc <domain>                  (re)generate the domain index note

Vault path is $AGENT_MEMO_VAULT (default ~/.agent-memo-vault).
USAGE
}

# --- dispatch -------------------------------------------------------------

main() {
  local sub="${1:-}"
  [ -n "$sub" ] || { mm_usage; exit 0; }
  shift

  case "$sub" in
    preflight)    mm_preflight ;;
    new)          mm_cmd_new "$@" ;;
    append)       mmfs_append "${1:-}" "${2:-}" ;;
    prepend)      mmfs_prepend "${1:-}" "${2:-}" ;;
    read)         mmfs_read "${1:-}" ;;
    daily)        mmfs_daily ;;
    daily:append) mmfs_daily_append "${1:-}" ;;
    search)       mm_w_search "${1:-}" ;;
    tags)         mm_w_tags ;;
    tag)          mm_w_tag "${1:-}" ;;
    by-tag)       mm_w_tag "${1:-}" ;;
    backlinks)    mm_w_backlinks "${1:-}" ;;
    links)        mm_w_links "${1:-}" ;;
    orphans)      mm_w_orphans ;;
    unresolved)   mm_w_unresolved ;;
    move)         mm_w_move "${1:-}" "${2:-}" ;;
    rename)       mm_w_rename "${1:-}" "${2:-}" ;;
    promote)      mm_promote "${1:-}" ;;
    moc)          mm_moc "${1:-}" ;;
    by-heat)      mm_by_heat ;;
    -h|--help|help) mm_usage ;;
    *)            mm_die "unknown subcommand: $sub (try: memovault help)" ;;
  esac
}

main "$@"
