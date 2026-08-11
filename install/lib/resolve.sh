#!/usr/bin/env bash
# install/lib/resolve.sh - shared version + upgrade tree selection.
# Sourced by install/install.sh and (when present) scripts/memovault.sh.
# Bash 3.2 compatible. No emoji. No set -e.

# True if $1 looks like a complete MemoVault-SKILL checkout.
mm_is_full_tree() {
  local r="${1:-}"
  [ -n "$r" ] \
    && [ -f "$r/VERSION" ] \
    && [ -f "$r/SKILL.md" ] \
    && [ -f "$r/install/targets.sh" ] \
    && [ -f "$r/scripts/memovault.sh" ]
}

# Print VERSION contents (trimmed) or empty.
mm_version_of() {
  local dir="$1"
  [ -f "$dir/VERSION" ] && { cat "$dir/VERSION" 2>/dev/null | tr -d '[:space:]'; return; }
  printf ''
}

# Compare two dotted versions. Print newer|equal|older (relation of a vs b).
mm_vercmp() {
  local a="$1" b="$2"
  if [ "$a" = "$b" ]; then printf 'equal'; return; fi
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

# Cache path used for curl|bash / upgrade refresh.
mm_cache_repo_path() {
  printf '%s' "${MEMOVAULT_CACHE_REPO:-$HOME/.cache/memovault/repo}"
}

# Best-effort update of the git cache. Never fails the caller.
# Optional: MM_RESOLVE_NO_PULL=1 to skip.
mm_refresh_cache_best_effort() {
  local cache ref
  [ "${MM_RESOLVE_NO_PULL:-0}" = 1 ] && return 0
  cache="$(mm_cache_repo_path)"
  ref="${MEMOVAULT_REF:-main}"
  [ -d "$cache/.git" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  if type mm_note >/dev/null 2>&1; then
    mm_note "upgrade: refreshing cache $cache ($ref)"
  else
    printf 'upgrade: refreshing cache %s (%s)\n' "$cache" "$ref" >&2
  fi
  git -C "$cache" fetch --depth 1 origin "$ref" >/dev/null 2>&1 || return 0
  git -C "$cache" checkout -q "$ref" 2>/dev/null \
    || git -C "$cache" checkout -q -B "$ref" FETCH_HEAD 2>/dev/null || true
  git -C "$cache" pull --ff-only origin "$ref" >/dev/null 2>&1 || true
}

# Read default vault path baked into env.sh (${AGENT_MEMO_VAULT:-PATH}).
# Prints PATH or empty.
mm_read_env_vault_default() {
  local envf="${1:-}" line
  [ -f "$envf" ] || { printf ''; return 0; }
  line="$(grep -E '^export AGENT_MEMO_VAULT=' "$envf" 2>/dev/null | head -1)" || true
  [ -n "$line" ] || { printf ''; return 0; }
  # Forms: ${AGENT_MEMO_VAULT:-/path} or ${AGENT_MEMO_VAULT:-"$HOME/..."} etc.
  case "$line" in
    *'${AGENT_MEMO_VAULT:-'*)
      line="${line#*\$\{AGENT_MEMO_VAULT:-}"
      line="${line%%\}*}"
      line="${line#\"}"
      line="${line%\"}"
      line="${line#\'}"
      line="${line%\'}"
      printf '%s' "$line"
      ;;
    *)
      printf ''
      ;;
  esac
}

# Pick upgrade source tree (strategy B).
# Env:
#   MM_RESOLVE_SOURCE  installed skill dir (required for origin)
#   MM_RESOLVE_ROOT    current installer ROOT (optional)
#   MM_RESOLVE_NO_PULL=1 skip cache refresh
#   MEMOVAULT_DEV_REPO forces pick when it is a full tree
# Prints absolute path on stdout. Returns 1 if none.
mm_pick_upgrade_tree() {
  local source="${MM_RESOLVE_SOURCE:-}" root="${MM_RESOLVE_ROOT:-}"
  local p origin cache cand_list="" best="" best_ver="" best_rank=0
  local v rel rank path

  p="${MEMOVAULT_DEV_REPO:-}"
  if [ -n "$p" ] && [ -d "$p" ]; then
    if mm_is_full_tree "$p"; then
      printf 'upgrade: picked=%s ver=%s (forced MEMOVAULT_DEV_REPO)\n' "$p" "$(mm_version_of "$p")" >&2
      printf '%s' "$p"
      return 0
    fi
  fi

  mm_refresh_cache_best_effort

  origin=""
  if [ -n "$source" ] && [ -f "$source/.source-origin" ]; then
    origin="$(cat "$source/.source-origin" 2>/dev/null | tr -d '[:space:]')"
  fi
  cache="$(mm_cache_repo_path)"

  # Collect unique full trees with tie-break rank: ROOT=3 origin=2 cache=1
  for path in "$root" "$origin" "$cache"; do
    [ -n "$path" ] || continue
    [ -d "$path" ] || continue
    mm_is_full_tree "$path" || continue
    case "|$cand_list|" in
      *"|$path|"*) continue ;;
    esac
    cand_list="${cand_list}|$path"
  done

  if [ -z "$cand_list" ]; then
    return 1
  fi

  # Strip leading |
  cand_list="${cand_list#|}"

  local IFS='|'
  # shellcheck disable=SC2086
  set -- $cand_list
  for path in "$@"; do
    [ -n "$path" ] || continue
    v="$(mm_version_of "$path")"
    [ -n "$v" ] || continue
    rank=1
    [ "$path" = "$cache" ] && rank=1
    [ -n "$origin" ] && [ "$path" = "$origin" ] && rank=2
    [ -n "$root" ] && [ "$path" = "$root" ] && rank=3
    if [ -z "$best" ]; then
      best="$path"
      best_ver="$v"
      best_rank=$rank
      continue
    fi
    rel="$(mm_vercmp "$v" "$best_ver")"
    if [ "$rel" = newer ]; then
      best="$path"
      best_ver="$v"
      best_rank=$rank
    elif [ "$rel" = equal ] && [ "$rank" -gt "$best_rank" ]; then
      best="$path"
      best_ver="$v"
      best_rank=$rank
    fi
  done

  [ -n "$best" ] || return 1

  printf 'upgrade: picked=%s ver=%s (candidates: %s)\n' "$best" "$best_ver" "$cand_list" >&2
  printf '%s' "$best"
  return 0
}

# Resolve installer script path for helper upgrade. Args: skill_source
# Prints path or returns 1.
mm_find_installer() {
  local source="${1:-}" origin cache
  [ -n "$source" ] || return 1
  if [ -f "$source/install/install.sh" ]; then
    printf '%s' "$source/install/install.sh"
    return 0
  fi
  if [ -f "$source/.source-origin" ]; then
    origin="$(cat "$source/.source-origin" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$origin" ] && [ -f "$origin/install/install.sh" ]; then
      printf '%s' "$origin/install/install.sh"
      return 0
    fi
  fi
  cache="$(mm_cache_repo_path)"
  if [ -f "$cache/install/install.sh" ]; then
    printf '%s' "$cache/install/install.sh"
    return 0
  fi
  return 1
}
