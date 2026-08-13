#!/usr/bin/env bash
# memovault.sh - MemoVault entry point.
# Preflight + subcommand dispatch. Pure local filesystem skill (shell-only
# runtime): all operations read and write markdown directly under
# $AGENT_MEMO_VAULT. The official Obsidian CLI is no longer a runtime
# dependency; Obsidian is only for humans browsing the vault.
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

# Fallback version helpers when install/lib/resolve.sh is not yet installed.
mm_version_of() {
  local dir="$1"
  [ -f "$dir/VERSION" ] && { cat "$dir/VERSION" 2>/dev/null | tr -d '[:space:]'; return; }
  printf ''
}

mm_vercmp() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && { printf 'equal'; return; }
  local IFS='.'
  # shellcheck disable=SC2086
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

mm_check_update() {
  local dev inst_ver dev_ver rel
  if type mm_pick_upgrade_tree >/dev/null 2>&1; then
    export MM_RESOLVE_SOURCE="$MM_SOURCE"
    export MM_RESOLVE_ROOT=""
    MM_RESOLVE_NO_PULL=1
    export MM_RESOLVE_NO_PULL
    # Quiet pick: temporarily stub mm_note
    mm_note() { :; }
    dev="$(mm_pick_upgrade_tree 2>/dev/null)" || { unset -f mm_note 2>/dev/null; return 1; }
    unset -f mm_note 2>/dev/null || true
  else
    dev="$(mm_resolve_dev_repo 2>/dev/null)" || return 1
  fi
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

# Prefer shared resolve helpers once install/ is present (0.7.1+).
if [ -f "$MM_SOURCE/install/lib/resolve.sh" ]; then
  # shellcheck source=/dev/null
  . "$MM_SOURCE/install/lib/resolve.sh"
fi

# Source runtime config (vault path) so it applies to every caller.
[ -f "$MM_SOURCE/env.sh" ] && . "$MM_SOURCE/env.sh"

MM_VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"

# shellcheck source=lib/fs.sh
. "$MM_ROOT/lib/fs.sh"
# shellcheck source=lib/rewrite.sh
. "$MM_ROOT/lib/rewrite.sh"
# shellcheck source=lib/classify.sh
. "$MM_ROOT/lib/classify.sh"
# shellcheck source=lib/obs.sh
. "$MM_ROOT/lib/obs.sh"
# shellcheck source=lib/eval.sh
. "$MM_ROOT/lib/eval.sh"

# MM_FORCE_FS is deprecated. The runtime is always shell/fs now; if a caller
# still exports it (e.g. an old env.sh or e2e harness), warn once and ignore.
if [ "${MM_FORCE_FS:-0}" = 1 ]; then
  mm_log "MM_FORCE_FS is deprecated and ignored (runtime is always shell)" >&2
fi

# --- preflight ------------------------------------------------------------

# Detect the search backend used by mmfs_search / mmfs_backlinks: prefer rg,
# fall back to grep. Print the binary name (rg|grep).
mm_detect_search() {
  if command -v rg >/dev/null 2>&1; then printf 'rg'; else printf 'grep'; fi
}

# Preflight contract (see docs/superpowers/specs/2026-08-04-shell-only-runtime-design.md
# section 4.3). Single machine-readable line plus source. No bin=/app=;
# mode=fs and forced=0 are kept as transitional fields for one minor version
# so older agent stubs that parse the legacy line do not break.
mm_preflight() {
  local search; search="$(mm_detect_search)"
  printf 'runtime=shell mode=fs vault=%s search=%s forced=0\n' "$MM_VAULT" "$search"
  printf 'source=%s\n' "$MM_SOURCE"
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

# Upgrade: delegate to install.sh --upgrade (SOURCE, then origin, then cache).
mm_cmd_upgrade() {
  local installer=""
  if type mm_find_installer >/dev/null 2>&1; then
    installer="$(mm_find_installer "$MM_SOURCE")" || true
  fi
  if [ -z "$installer" ]; then
    if [ -f "$MM_SOURCE/install/install.sh" ]; then
      installer="$MM_SOURCE/install/install.sh"
    elif [ -f "$MM_SOURCE/.source-origin" ]; then
      local origin
      origin="$(cat "$MM_SOURCE/.source-origin" 2>/dev/null | tr -d '[:space:]')"
      [ -n "$origin" ] && [ -f "$origin/install/install.sh" ] \
        && installer="$origin/install/install.sh"
    fi
  fi
  if [ -z "$installer" ] || [ ! -f "$installer" ]; then
    mm_die "upgrade: installer not found (re-run curl|bash install or ./install/install.sh --upgrade from a checkout)"
  fi
  chmod +x "$installer" 2>/dev/null || true
  exec "$installer" --upgrade "$@"
}

mm_usage() {
  cat <<'USAGE'
memovault - sink knowledge into the local memo vault.

Resolve:
  preflight                     show runtime (shell/fs), vault, search backend
  upgrade                       re-sync from newest full tree; re-inject agents
                                (delegates to install.sh --upgrade)

Capture / edit:
  new <domain> <title> [--tags a,b] [--kind atom] [--body "text"]
  append <note> "<markdown>"
  prepend <note> "<markdown>"   (inserted after frontmatter)
  read <note>
  distill <raw> <domain> <title> [--kind atom|scenario]
  supersede <old> <new>         mark old superseded by new
  daily                         (legacy) show today's daily note
  daily:append "<line>"         (legacy) append to today's daily note

Retrieve:
  search <query> [--limit N] [--domain D] [--kind K] [--heat H]
                 [--include-raw] [--include-superseded]
  recall <query> [--limit N] [--no-graph] [--include-superseded]
  cite <title>                  record that a note was used in an answer
  feedback <title> +1|-1        explicit reinforce signal (ledger only)
  dedupe <query-or-title>       near-duplicate candidates
  suggest                       promote/dedupe suggestions (no mutations)
  tags                          all tags with counts
  tag <name> | by-tag <name>    notes bearing a tag
  by-heat                       notes grouped by heat tier
  health | stats                vault + ledger metrics (L0-L2 proxies)
  ledger:rotate [--keep N]      trim ledger.log (default keep 5000 lines)
  eval [--fixture dir] [--limit N] [--no-graph]
                                recall hit@k gate on fixture cases

Graph:
  backlinks <note>              notes linking to this note
  links <note>                  notes this note links to
  orphans                       notes with no incoming links
  unresolved                    [[links]] pointing nowhere yet

Organize / curate:
  move <note> <folder-or-path>  (filesystem move; links not auto-updated)
  rename <note> "<New Title>"  (link-safe: rewrites [[wikilinks]] across vault)
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
    distill)      mmfs_distill "$@" ;;
    supersede)    mmfs_supersede "${1:-}" "${2:-}" ;;
    daily)        mmfs_daily ;;
    daily:append) mmfs_daily_append "${1:-}" ;;
    search)       MM_SEARCH_OBS=1 mmfs_search "$@" ;;
    recall)       mmfs_recall "$@" ;;
    cite)         mm_obs_cite "${1:-}" ;;
    feedback)     mm_obs_feedback "${1:-}" "${2:-}" ;;
    dedupe)       mmfs_dedupe "$@" ;;
    suggest)      mm_obs_suggest ;;
    health|stats) mm_obs_health ;;
    ledger:rotate) mm_obs_rotate "$@" ;;
    eval)         mm_eval_run "$@" ;;
    tags)         mmfs_tags ;;
    tag)          mmfs_tag "${1:-}" ;;
    by-tag)       mmfs_tag "${1:-}" ;;
    backlinks)    mmfs_backlinks "${1:-}" ;;
    links)        mmfs_links "${1:-}" ;;
    orphans)      mmfs_orphans ;;
    unresolved)   mmfs_unresolved ;;
    move)         mmfs_move "${1:-}" "${2:-}" ;;
    rename)       mmfs_rename "${1:-}" "${2:-}" ;;
    promote)      mm_promote "${1:-}" ;;
    moc)          mm_moc "${1:-}" ;;
    by-heat)      mm_by_heat ;;
    -h|--help|help) mm_usage ;;
    *)            mm_die "unknown subcommand: $sub (try: memovault help)" ;;
  esac
}

main "$@"