#!/usr/bin/env bash
# install/install.sh - install MemoVault into the canonical source location and
# inject pointer stubs into one or more coding agents.
# Bash 3.2 compatible. No emoji.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/targets.sh"

SOURCE="${MEMOVAULT_SOURCE:-$HOME/.agents/skills/memovault}"
VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"
HELPER="$SOURCE/scripts/memovault.sh"

DRY_RUN=0
FORCE=0
INLINE=0
STDOUT_MODE=0
FORCE_FS=0
DO_REGISTER=0
DO_SOURCE_ONLY=0
DO_VERIFY=0
DO_UPGRADE=0
AGENTS=""

mm_die() { printf 'install: %s\n' "$*" >&2; exit 1; }
mm_log() { printf 'install: %s\n' "$*"; }
mm_note() { printf '%s\n' "$*"; }

mm_usage() {
  cat <<'USAGE'
install.sh - install MemoVault and inject it into agents.

Usage:
  install.sh [--source <dir>] [--vault <dir>] [--force] [--dry-run]
             [--source-only] [--register-vault] [--inline] [--verify]
             [--upgrade]
             (--agent <name> ... | --all)

Options:
  --source <dir>     skill source dir (default ~/.agents/skills/memovault)
  --vault <dir>      knowledge vault dir (default ~/.agent-memo-vault)
  --source-only      only install the source + scaffold the vault
  --register-vault   register the vault into Obsidian's obsidian.json
  --agent <name>     inject into one agent (repeatable)
  --all              inject into every supported agent
  --inline           embed the full SKILL.md instead of a pointer stub
  --force            overwrite existing stub files
  --force-fs         write MM_FORCE_FS=1 into env.sh so the helper runs headless
                     (skips the Obsidian CLI probe; no GUI). Opt-in; default off
                     preserves cli mode for hosts with a real obsidian-cli.
  --dry-run          print actions without writing
  --stdout           print the rendered body for an agent (for UI-only targets
                     such as Trae global AI Rules); requires --agent <name>
  --verify           check source, vault, and always-on injection status
                     (no writes). Optional --agent to limit which agents to check;
                     default checks every supported agent. Exit 1 if any check fails.
  --upgrade          re-sync the installed source from the dev repo and re-inject
                     all agents. The dev repo is auto-detected from
                     .source-origin, or set via MEMOVAULT_DEV_REPO. If the dev repo
                     is a git repo, pull first (use --no-pull to skip). Implies
                     --all --force unless --agent is given.
  --no-pull          with --upgrade, skip the `git pull` step in the dev repo
  -h | --help        show this help

Supported agents: claude, pi, codex, opencode, crush, gemini, cline, cursor,
trae, copilot.

Note: discovering ~/.agents/skills/memovault is not the same as always-on
memory. Cursor/Claude/etc. need their adapter injection (see --verify).
USAGE
}

# --- version helpers -------------------------------------------------------

# Print the version string from a VERSION file, or empty if missing.
mm_version_of() {
  local dir="$1"
  [ -f "$dir/VERSION" ] && { cat "$dir/VERSION" 2>/dev/null | tr -d '[:space:]'; return; }
  printf ''
}

# Compare two dotted versions. Print "newer"|"equal"|"older".
# Usage: mm_vercmp <a> <b>  -> echoes relation of a vs b.
mm_vercmp() {
  local a="$1" b="$2"
  if [ "$a" = "$b" ]; then printf 'equal'; return; fi
  # Split on '.', compare numerically left to right.
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

# Resolve the dev repo path for upgrade. Priority:
#   1. MEMOVAULT_DEV_REPO env var
#   2. .source-origin recorded at install time
#   3. the dev repo that contains this install.sh (best effort)
# Print path or return 1.
mm_resolve_dev_repo() {
  local p
  p="${MEMOVAULT_DEV_REPO:-}"
  [ -n "$p" ] && [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  if [ -f "$SOURCE/.source-origin" ]; then
    p="$(cat "$SOURCE/.source-origin" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$p" ] && [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  fi
  # Fall back to the repo this installer lives in.
  if [ -f "$ROOT/VERSION" ]; then
    printf '%s' "$ROOT"
    return 0
  fi
  return 1
}

# --- actions ---------------------------------------------------------------

mm_install_source() {
  mm_note "1) install skill source -> $SOURCE"
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  mkdir -p "$SOURCE"
  local item
  for item in SKILL.md AGENTS.md CLAUDE.md README.md VERSION scripts templates docs; do
    [ -e "$ROOT/$item" ] || continue
    if [ -d "$ROOT/$item" ]; then
      rm -rf "$SOURCE/$item"
      cp -R "$ROOT/$item" "$SOURCE/$item"
    else
      cp "$ROOT/$item" "$SOURCE/$item"
    fi
  done
  chmod +x "$SOURCE/scripts/memovault.sh" 2>/dev/null || true
  # Record where the source was copied from, so `upgrade` can auto-detect the
  # dev repo and compare versions. Overriden by --source / MEMOVAULT_DEV_REPO.
  printf '%s\n' "$ROOT" > "$SOURCE/.source-origin" 2>/dev/null || true
}

mm_scaffold_vault() {
  mm_note "2) scaffold vault -> $VAULT"
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  mkdir -p "$VAULT/brain" "$VAULT/daily" "$VAULT/templates"
  local t
  for t in note daily moc; do
    [ -f "$VAULT/templates/$t.md" ] || cp "$ROOT/templates/$t.md" "$VAULT/templates/$t.md" 2>/dev/null || true
  done
}

mm_write_env() {
  mm_note "3) write env snippet -> $SOURCE/env.sh"
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  cat > "$SOURCE/env.sh" <<EOF
# Runtime config for the MemoVault helper. The helper sources this file at
# startup, so it applies to every caller (agents rarely export env vars
# themselves). Each var uses \${VAR:-...} so a caller may override per call.
export AGENT_MEMO_VAULT="\${AGENT_MEMO_VAULT:-$VAULT}"
EOF
  if [ "$FORCE_FS" = 1 ]; then
    cat >> "$SOURCE/env.sh" <<'EOF'
export MM_FORCE_FS="${MM_FORCE_FS:-1}"
EOF
  fi
}

# Render an adapter template with placeholders substituted. Print to stdout.
mm_render() {
  local adapter="$1"
  [ -f "$ROOT/install/adapters/$adapter" ] || mm_die "adapter not found: $adapter"
  sed -e "s#__MEMOVAULT_SOURCE__#$SOURCE#g" \
      -e "s#__MEMOVAULT_HELPER__#$HELPER#g" \
      -e "s#__MEMOVAULT_VAULT__#$VAULT#g" \
      "$ROOT/install/adapters/$adapter"
}

# Compose the final injected body: the agent header plus the shared memory
# protocol (auto recall, semi-auto capture). Authored once in _protocol.md.
mm_compose() {
  local adapter="$1"
  mm_render "$adapter"
  printf '\n'
  mm_render "_protocol.md"
}

mm_inject_one() {
  local agent="$1"
  local kind path adapter
  kind="$(mm_target_kind "$agent")" || mm_die "unknown agent: $agent"
  path="$(mm_target_path "$agent")"
  adapter="$(mm_target_adapter "$agent")"
  mm_note "*) inject [$kind] $agent -> $path"

  if [ "$DRY_RUN" = 1 ]; then
    if [ "$INLINE" = 1 ] && [ "$kind" = skill ]; then
      mm_note "   (inline mode: would embed full SKILL.md)"
    else
      mm_compose "$adapter" | sed 's/^/   | /'
    fi
    return 0
  fi

  if [ "$kind" = native ]; then
    mm_note "   native: self-contained skill auto-discovered at $SOURCE"
    return 0
  fi

  mkdir -p "$(dirname "$path")"

  if [ "$kind" = skill ]; then
    if [ "$INLINE" = 1 ]; then
      [ -f "$path" ] && [ "$FORCE" = 0 ] && mm_die "exists (use --force): $path"
      cp "$ROOT/SKILL.md" "$path"
    else
      [ -f "$path" ] && [ "$FORCE" = 0 ] && mm_die "exists (use --force): $path"
      mm_compose "$adapter" > "$path"
    fi
    return 0
  fi

  if [ "$kind" = rules ]; then
    [ -f "$path" ] && [ "$FORCE" = 0 ] && mm_die "exists (use --force): $path"
    mm_compose "$adapter" > "$path"
    return 0
  fi

  # kind = agents: append an idempotent block to an AGENTS.md style file.
  if [ -f "$path" ] && grep -q '<!-- begin memovault -->' "$path" 2>/dev/null; then
    if [ "$FORCE" = 1 ]; then
      mm_remove_block "$path"
    else
      mm_note "   block already present in $path (use --force to refresh)"
      return 0
    fi
  fi
  {
    printf '\n<!-- begin memovault -->\n'
    mm_compose "$adapter"
    printf '<!-- end memovault -->\n'
  } >> "$path"
}

# Remove an existing memovault block from an AGENTS.md style file.
mm_remove_block() {
  local f="$1" tmp; tmp="$(mktemp)"
  awk '
    /<!-- begin memovault -->/ { skip = 1; next }
    /<!-- end memovault -->/ { skip = 0; next }
    !skip { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  return 0
}

# Locate obsidian.json across platforms. Print path or return 1.
mm_obsidian_json() {
  local f
  for f in \
    "$HOME/Library/Application Support/obsidian/obsidian.json" \
    "$HOME/.config/obsidian/obsidian.json"; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

mm_register_vault() {
  mm_note "+) register vault into Obsidian"
  local f; f="$(mm_obsidian_json)" || { mm_note "   obsidian.json not found; register '$VAULT' manually in Obsidian (open folder as vault)."; return 0; }
  if grep -q "\"$VAULT\"" "$f" 2>/dev/null; then
    mm_note "   vault already registered: $VAULT"
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { mm_note "   jq not installed; add this entry manually to $f:\n   \"<id>\": {\"path\":\"$VAULT\",\"open\":false}"; return 0; }
  local id ts tmp
  id="$(openssl rand -hex 8 2>/dev/null || printf '%016x' "$(date +%s)$$")"
  ts="$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || printf '%s000' "$(date +%s)")"
  if [ "$DRY_RUN" = 1 ]; then
    mm_note "   would add vault id=$id path=$VAULT to $f"
    return 0
  fi
  cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  jq --arg id "$id" --arg path "$VAULT" --argjson ts "$ts" \
    '.vaults[$id] = {path:$path, ts:$ts, open:false}' "$f" > "$tmp" \
    && mv "$tmp" "$f" || { rm -f "$tmp"; mm_die "failed to update $f (backup kept)"; }
  mm_note "   registered vault id=$id path=$VAULT"
  mm_note "   requires Obsidian 1.12.7+ and the app restarted to take effect"
}

# Return 0 if file $1 contains fixed string $2.
mm_file_has() {
  local f="$1" needle="$2"
  [ -f "$f" ] && grep -qF "$needle" "$f" 2>/dev/null
}

# Print one verify line: status agent detail
mm_verify_line() {
  local status="$1" agent="$2" detail="$3"
  printf '%-4s %-10s %s\n' "$status" "$agent" "$detail"
}

# Check one agent's always-on injection. Echo status line; return 0 if ok.
mm_verify_agent() {
  local agent="$1"
  local kind path
  kind="$(mm_target_kind "$agent")" || { mm_verify_line FAIL "$agent" "unknown agent"; return 1; }
  path="$(mm_target_path "$agent")"

  if [ "$kind" = native ]; then
    if [ -f "$SOURCE/SKILL.md" ] && [ -x "$HELPER" ] && mm_file_has "$SOURCE/SKILL.md" "Memory protocol"; then
      mm_verify_line OK "$agent" "native -> $SOURCE (auto-discovered; not always-on by itself)"
      return 0
    fi
    mm_verify_line FAIL "$agent" "native source incomplete at $SOURCE"
    return 1
  fi

  if [ ! -f "$path" ]; then
    mm_verify_line FAIL "$agent" "missing $path (run: install.sh --agent $agent)"
    return 1
  fi

  if [ "$kind" = agents ]; then
    if ! mm_file_has "$path" "<!-- begin memovault -->"; then
      mm_verify_line FAIL "$agent" "no memovault block in $path"
      return 1
    fi
  fi

  if ! mm_file_has "$path" "Memory protocol"; then
    mm_verify_line FAIL "$agent" "injected but missing Memory protocol in $path (re-run with --force)"
    return 1
  fi

  if [ "$agent" = cursor ] && ! mm_file_has "$path" "alwaysApply: true"; then
    mm_verify_line FAIL "$agent" "missing alwaysApply: true in $path"
    return 1
  fi

  mm_verify_line OK "$agent" "[$kind] $path"
  return 0
}

# Read-only health check: source, vault scaffold, always-on injections.
# Exit 1 if anything required is missing. Does not write.
mm_verify() {
  local agents="$1"
  local fail=0

  mm_note "verify source: $SOURCE"
  if [ ! -f "$SOURCE/SKILL.md" ]; then
    mm_verify_line FAIL source "missing $SOURCE/SKILL.md"
    fail=1
  elif ! mm_file_has "$SOURCE/SKILL.md" "Memory protocol"; then
    mm_verify_line FAIL source "SKILL.md present but missing Memory protocol section"
    fail=1
  else
    mm_verify_line OK source "$SOURCE/SKILL.md"
  fi

  if [ ! -x "$HELPER" ]; then
    mm_verify_line FAIL helper "missing or not executable: $HELPER"
    fail=1
  else
    mm_verify_line OK helper "$HELPER"
  fi

  mm_note "verify vault: $VAULT"
  if [ ! -d "$VAULT/brain" ] || [ ! -d "$VAULT/templates" ]; then
    mm_verify_line FAIL vault "scaffold incomplete (need brain/ and templates/ under $VAULT)"
    fail=1
  else
    mm_verify_line OK vault "$VAULT"
  fi

  mm_note "verify always-on injection (discovery alone is not enough):"
  local a
  for a in $agents; do
    mm_verify_agent "$a" || fail=1
  done

  mm_note ""
  if [ "$fail" -ne 0 ]; then
    mm_note "verify: FAIL (fix with: ./install/install.sh --all --force)"
    return 1
  fi
  mm_note "verify: OK"
  mm_note "next: $HELPER preflight"
  return 0
}

# Upgrade: re-sync the installed source from the dev repo and re-inject agents.
# Steps:
#   1. resolve the dev repo (MEMOVAULT_DEV_REPO / .source-origin / this repo)
#   2. compare VERSION; if dev is newer (or --force), proceed
#   3. if dev repo is a git repo, `git pull` (unless --no-pull)
#   4. re-run install_source + scaffold + env + injection (FORCE=1)
mm_upgrade() {
  local dev
  dev="$(mm_resolve_dev_repo)" || mm_die "upgrade: cannot locate dev repo (set MEMOVAULT_DEV_REPO or run install.sh from the dev repo)"
  mm_note "upgrade: dev repo = $dev"

  local inst_ver dev_ver rel
  inst_ver="$(mm_version_of "$SOURCE")"
  dev_ver="$(mm_version_of "$dev")"
  mm_note "upgrade: installed=$inst_ver dev=$dev_ver"

  if [ -z "$dev_ver" ]; then
    mm_die "upgrade: dev repo has no VERSION file at $dev"
  fi
  if [ -z "$inst_ver" ]; then
    mm_note "upgrade: installed has no VERSION; proceeding (first install)"
  else
    rel="$(mm_vercmp "$dev_ver" "$inst_ver")"
    case "$rel" in
      newer) mm_note "upgrade: update available ($inst_ver -> $dev_ver)" ;;
      equal)
        if [ "$FORCE" = 1 ]; then
          mm_note "upgrade: already at $inst_ver (forcing re-sync)"
        else
          mm_note "upgrade: already up to date ($inst_ver); use --force to re-sync anyway"
          return 0
        fi
        ;;
      older) mm_note "upgrade: dev ($dev_ver) is older than installed ($inst_ver); use --force to downgrade" ;;
    esac
  fi

  # Optionally pull from git.
  if [ "$NO_PULL" = 0 ] && [ -d "$dev/.git" ]; then
    if command -v git >/dev/null 2>&1; then
      mm_note "upgrade: git pull in $dev"
      if [ "$DRY_RUN" = 1 ]; then
        mm_note "   (dry-run) would run: git -C $dev pull --ff-only"
      else
        git -C "$dev" pull --ff-only 2>&1 | sed 's/^/   | /' || mm_note "   git pull failed or no upstream; continuing with local files"
        # Re-read version after pull.
        dev_ver="$(mm_version_of "$dev")"
        mm_note "upgrade: dev version after pull = $dev_ver"
      fi
    else
      mm_note "upgrade: git not found; skipping pull (using local files in $dev)"
    fi
  fi

  # Re-point ROOT at the dev repo so install_source copies from there.
  ROOT="$dev"
  HELPER="$SOURCE/scripts/memovault.sh"
  FORCE=1

  mm_install_source
  mm_scaffold_vault
  mm_write_env

  if [ -z "$AGENTS" ]; then
    AGENTS="$(mm_target_list | tr '\n' ' ')"
  fi
  local a
  for a in $AGENTS; do
    mm_inject_one "$a"
  done

  mm_note ""
  mm_note "upgrade: done ($inst_ver -> $dev_ver)"
  mm_note "next: $HELPER preflight"
}

# --- arg parsing -----------------------------------------------------------

NO_PULL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --vault) VAULT="$2"; shift 2 ;;
    --agent) AGENTS="$AGENTS $2"; shift 2 ;;
    --all) AGENTS="$(mm_target_list | tr '\n' ' ')"; shift ;;
    --source-only) DO_SOURCE_ONLY=1; shift ;;
    --register-vault) DO_REGISTER=1; shift ;;
    --inline) INLINE=1; shift ;;
    --force) FORCE=1; shift ;;
    --force-fs) FORCE_FS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --stdout) STDOUT_MODE=1; shift ;;
    --verify) DO_VERIFY=1; shift ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --no-pull) NO_PULL=1; shift ;;
    -h|--help) mm_usage; exit 0 ;;
    *) mm_die "unknown flag: $1 (try --help)" ;;
  esac
done

HELPER="$SOURCE/scripts/memovault.sh"

# Render-only mode: print the composed body for an agent and exit. Used for
# UI-only targets (e.g. Trae global AI Rules) where there is no file to write.
if [ "$STDOUT_MODE" = 1 ]; then
  [ -n "$AGENTS" ] || mm_die "--stdout requires --agent <name>"
  for a in $AGENTS; do
    mm_target_kind "$a" >/dev/null || mm_die "unknown agent: $a"
    mm_compose "$(mm_target_adapter "$a")"
    printf '\n--- (end of %s) ---\n\n' "$a"
  done
  exit 0
fi

# Read-only verify: does not install or inject.
if [ "$DO_VERIFY" = 1 ]; then
  if [ -z "$AGENTS" ]; then
    AGENTS="$(mm_target_list | tr '\n' ' ')"
  fi
  mm_verify "$AGENTS"
  exit $?
fi

# Upgrade: re-sync from dev repo and re-inject.
if [ "$DO_UPGRADE" = 1 ]; then
  mm_upgrade
  exit $?
fi

if [ -z "$AGENTS" ] && [ "$DO_SOURCE_ONLY" = 0 ] && [ "$DO_REGISTER" = 0 ]; then
  mm_usage
  exit 0
fi

# always ensure source + vault + env for any real action
mm_install_source
mm_scaffold_vault
mm_write_env

[ "$DO_REGISTER" = 1 ] && mm_register_vault

if [ -n "$AGENTS" ]; then
  for a in $AGENTS; do
    mm_inject_one "$a"
  done
fi

mm_note ""
mm_note "done."
mm_note "next steps:"
mm_note "  - update Obsidian to installer 1.12.7+ and enable Settings -> General -> Command line interface"
mm_note "  - restart your terminal and your agent(s) so the new skill/rules load"
mm_note "  - verify injection: $ROOT/install/install.sh --verify"
mm_note "  - verify helper: $HELPER preflight"