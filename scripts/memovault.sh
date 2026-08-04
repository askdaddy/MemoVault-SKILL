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

# Print the version string from a VERSION file, or empty if missing.
mm_version_of() {
  local dir="$1"
  [ -f "$dir/VERSION" ] && { cat "$dir/VERSION" 2>/dev/null | tr -d '[:space:]'; return; }
  printf ''
}

# Compare two dotted versions. Print newer|equal|older (a vs b).
mm_vercmp() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && { printf 'equal'; return; }
  local IFS='.'
  set -- $a $b
  local a1="${1:-0}" a2="${2:-0}" a3="${3:-0}" b1="${4:-0}" b2="${5:-0}" b3="${6:-0}"
  if [ "$a1" -gt "$b1" ] 2>/dev/null; then printf 'newer'; return; fi
  if [ "$a1" -lt "$b1" ] 2>/dev/null; then printf 'older'; return; fi
  if [ "$a2" -gt "$b2" ] 2>/dev/null; then printf 'newer'; return; fi
  if [ "$a2" -lt "$b2" ] 2>/dev/null; then printf 'older'; return; fi
  if [ "$a3" -gt "$b3" ] 2>/dev/null; then printf 'newer'; return; fi
  if [ "$a3" -lt "$b3" ] 2>/dev/null; then printf 'older'; return; fi
  printf 'equal'
}

# Resolve the dev repo for update checks. Priority:
#   1. MEMOVAULT_DEV_REPO env var
#   2. .source-origin recorded at install time (lives in the source dir)
#   3. the repo this helper lives in (best effort, for dev runs)
# Print path or return 1.
mm_resolve_dev_repo() {
  local p
  p="${MEMOVAULT_DEV_REPO:-}"
  [ -n "$p" ] && [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  if [ -f "$MM_SOURCE/.source-origin" ]; then
    p="$(cat "$MM_SOURCE/.source-origin" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$p" ] && [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  fi
  if [ -f "$MM_SOURCE/VERSION" ]; then
    printf '%s' "$MM_SOURCE"
    return 0
  fi
  return 1
}

# Check for an available update. Print "update-available <installed> <dev>" or
# nothing. Returns 0 if an update is available, 1 otherwise.
mm_check_update() {
  local dev inst_ver dev_ver rel
  dev="$(mm_resolve_dev_repo 2>/dev/null)" || return 1
  [ -f "$dev/VERSION" ] || return 1
  inst_ver="$(mm_version_of "$MM_SOURCE")"
  dev_ver="$(mm_version_of "$dev")"
  [ -n "$inst_ver" ] && [ -n "$dev_ver" ] || return 1
  rel="$(mm_vercmp "$dev_ver" "$inst_ver")"
  [ "$rel" = newer ] || return 1
  printf 'update-available %s %s' "$inst_ver" "$dev_ver"
  return 0
}

# --- environment ----------------------------------------------------------

MM_ROOT="$(mm_resolve_root)"
MM_SOURCE="$(cd "$MM_ROOT/.." && pwd)"            # skill source dir

# Source runtime config (vault path, headless mode) so it applies to every
# caller. Agents rarely export these themselves; without this, env.sh would only
# take effect if the caller's shell had sourced it first. Each var uses
# ${VAR:-...} so a caller may still override per invocation.
[ -f "$MM_SOURCE/env.sh" ] && . "$MM_SOURCE/env.sh"

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
  printf 'mode=%s vault=%s bin=%s app=%s forced=%s\n' \
    "$MM_MODE" "$MM_VAULT" "${MM_OBSIDIAN:-}" "$app_state" "${MM_FORCED:-0}"
  printf 'source=%s\n' "$MM_SOURCE"
  if [ "$MM_MODE" = fs ]; then
    if [ "${MM_FORCED:-0}" = 1 ]; then
      printf 'hint: fs mode forced via MM_FORCE_FS=1; CLI probe skipped (Obsidian GUI will not launch)\n' >&2
    elif [ -z "${MM_OBSIDIAN:-}" ]; then
      printf 'hint: obsidian CLI not found; install Obsidian 1.12.7+ and enable Settings -> General -> Command line interface\n' >&2
    elif [ "$app_state" = stopped ]; then
      printf 'hint: Obsidian app is not running; start it for cli mode (backlink graph, link-safe move)\n' >&2
    fi
  fi
  # Update check: compare installed VERSION vs dev repo VERSION.
  local upd
  if upd="$(mm_check_update 2>/dev/null)"; then
    printf 'hint: %s (run: memovault upgrade)\n' "$upd" >&2
  fi
}

# --- subcommand handlers --------------------------------------------------

mm_cmd_new() {
  local domain="$1" title="$2"; shift 2 2>/dev/null || true
  local tags="" body="" kind=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tags) tags="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  mmfs_new "$domain" "$title" "$tags" "$body" "$kind"
}

# Upgrade: delegate to install.sh --upgrade. The installer re-syncs the source
# from the dev repo (auto-detected or via MEMOVAULT_DEV_REPO), optionally pulls
# from git, and re-injects all agent stubs.
mm_cmd_upgrade() {
  local installer="$MM_SOURCE/install/install.sh"
  if [ ! -x "$installer" ]; then
    mm_die "upgrade: installer not found at $installer (is the source dir intact?)"
  fi
  exec "$installer" --upgrade "$@"
}

mm_usage() {
  cat <<'USAGE'
memovault - sink knowledge into the local memo vault.

Resolve:
  preflight                     show mode (cli/fs), vault, obsidian binary, app state
  upgrade                       re-sync from the dev repo and re-inject agents
                                (delegates to install.sh --upgrade)

Capture / edit:
  new <domain> <title> [--tags a,b] [--kind atom] [--body "text"]
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
    upgrade)      mm_cmd_upgrade "$@" ;;
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