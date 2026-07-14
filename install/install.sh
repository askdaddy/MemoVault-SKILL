#!/usr/bin/env bash
# install/install.sh - install MemoVault into the canonical source location and
# inject pointer stubs into one or more coding agents.
# Bash 3.2 compatible. No emoji.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/targets.sh"

SOURCE="${MEMOVAULT_SOURCE:-$HOME/.agent-memo-vault-skill}"
VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"
HELPER="$SOURCE/scripts/memovault.sh"

DRY_RUN=0
FORCE=0
INLINE=0
DO_REGISTER=0
DO_SOURCE_ONLY=0
AGENTS=""

mm_die() { printf 'install: %s\n' "$*" >&2; exit 1; }
mm_log() { printf 'install: %s\n' "$*"; }
mm_note() { printf '%s\n' "$*"; }

mm_usage() {
  cat <<'USAGE'
install.sh - install MemoVault and inject it into agents.

Usage:
  install.sh [--source <dir>] [--vault <dir>] [--force] [--dry-run]
             [--source-only] [--register-vault] [--inline]
             (--agent <name> ... | --all)

Options:
  --source <dir>     skill source dir (default ~/.agent-memo-vault-skill)
  --vault <dir>      knowledge vault dir (default ~/.agent-memo-vault)
  --source-only      only install the source + scaffold the vault
  --register-vault   register the vault into Obsidian's obsidian.json
  --agent <name>     inject into one agent (repeatable)
  --all              inject into every supported agent
  --inline           embed the full SKILL.md instead of a pointer stub
  --force            overwrite existing stub files
  --dry-run          print actions without writing
  -h | --help        show this help

Supported agents: claude, pi, codex, opencode, crush, gemini, cline, cursor,
trae, copilot.
USAGE
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
# Source this file to pin the MemoVault vault path.
export AGENT_MEMO_VAULT="\${AGENT_MEMO_VAULT:-$VAULT}"
EOF
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
      mm_render "$adapter" | sed 's/^/   | /'
    fi
    return 0
  fi

  mkdir -p "$(dirname "$path")"

  if [ "$kind" = skill ]; then
    if [ "$INLINE" = 1 ]; then
      [ -f "$path" ] && [ "$FORCE" = 0 ] && mm_die "exists (use --force): $path"
      cp "$ROOT/SKILL.md" "$path"
    else
      [ -f "$path" ] && [ "$FORCE" = 0 ] && mm_die "exists (use --force): $path"
      mm_render "$adapter" > "$path"
    fi
    return 0
  fi

  if [ "$kind" = rules ]; then
    [ -f "$path" ] && [ "$FORCE" = 0 ] && mm_die "exists (use --force): $path"
    mm_render "$adapter" > "$path"
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
    mm_render "$adapter"
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

# --- arg parsing -----------------------------------------------------------

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
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) mm_usage; exit 0 ;;
    *) mm_die "unknown flag: $1 (try --help)" ;;
  esac
done

HELPER="$SOURCE/scripts/memovault.sh"

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
mm_note "  - verify: $HELPER preflight"
