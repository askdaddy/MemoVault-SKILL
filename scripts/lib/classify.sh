#!/usr/bin/env bash
# lib/classify.sh - domain/heat/MOC helpers for MemoVault.
# These operate on the filesystem directly (the note files are real markdown in
# both modes), so they are mode independent.

mm_heat_rank() {
  case "$1" in
    evergreen) printf 3 ;;
    growing) printf 2 ;;
    seedling) printf 1 ;;
    *) printf 0 ;;
  esac
}

mm_heat_next() {
  case "$1" in
    seedling) printf growing ;;
    growing) printf evergreen ;;
    evergreen) printf "" ;;
    *) printf seedling ;;
  esac
}

# Advance a note one heat tier.
mm_promote() {
  local ref="$1"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] && [ -f "$file" ] || mm_die "note not found: $ref"
  local cur; cur="$(mmfs_get_prop "$file" heat)"
  local next; next="$(mm_heat_next "$cur")"
  [ -n "$next" ] || { mm_log "already evergreen: ${ref}"; return 0; }
  local today; today="$(mm_today)"
  local rel="${file#"$MM_VAULT"/}"
  if [ "$MM_MODE" = cli ]; then
    mmcli_set_prop "$rel" heat "$next" || mmfs_set_prop "$file" heat "$next"
    mmcli_set_prop "$rel" updated "$today" || mmfs_set_prop "$file" updated "$today"
  else
    mmfs_set_prop "$file" heat "$next"
    mmfs_set_prop "$file" updated "$today"
  fi
  mm_log "promoted: ${cur:-<unset>} -> ${next}  (${rel})"
}

# Regenerate the Map of Content for a domain.
mm_moc() {
  local dom="$1"
  [ -n "$dom" ] || mm_die "usage: moc <domain>"
  local dir="$MM_VAULT/brain/$dom"
  [ -d "$dir" ] || mm_die "domain not found: $dom (no $dir)"
  local mocfile="$dir/_${dom}-MOC.md"
  local today; today="$(mm_today)"
  local f title heat
  local -a seed growing evergreen
  while IFS= read -r f; do
    [ "$f" = "$mocfile" ] && continue
    title="$(mmfs_get_prop "$f" title)"
    [ -n "$title" ] || title="$(basename "$f" .md)"
    heat="$(mmfs_get_prop "$f" heat)"; heat="${heat:-seedling}"
    case "$heat" in
      evergreen) evergreen+=("$title") ;;
      growing) growing+=("$title") ;;
      *) seed+=("$title") ;;
    esac
  done < <(find "$dir" -type f -name '*.md' 2>/dev/null | sort)

  {
    printf -- '---\n'
    printf 'title: %s MOC\n' "$dom"
    printf 'domain: %s\n' "$dom"
    printf 'tags: [moc]\n'
    printf 'heat: evergreen\n'
    printf 'aliases: []\n'
    printf 'created: %s\n' "$today"
    printf 'updated: %s\n' "$today"
    printf -- '---\n\n'
    printf '# %s MOC\n\n' "$dom"
    mm_moc_section "evergreen" ${evergreen[@]+"${evergreen[@]}"}
    mm_moc_section "growing" ${growing[@]+"${growing[@]}"}
    mm_moc_section "seedling" ${seed[@]+"${seed[@]}"}
  } > "$mocfile"
  printf '%s\n' "${mocfile#"$MM_VAULT"/}"
}

mm_moc_section() {
  local tier="$1"; shift
  printf '## %s\n\n' "$tier"
  if [ $# -eq 0 ]; then
    printf -- '- (none)\n\n'
    return
  fi
  local t
  for t in "$@"; do
    printf -- '- [[%s]]\n' "$t"
  done
  printf '\n'
}

# List all notes grouped by heat tier.
mm_by_heat() {
  [ -d "$MM_VAULT/brain" ] || return 0
  local f heat rel
  find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null | while read -r f; do
    rel="${f#"$MM_VAULT"/}"
    heat="$(mmfs_get_prop "$f" heat)"; heat="${heat:-seedling}"
    printf '%s\t%s\n' "$(mm_heat_rank "$heat")" "$heat:$rel"
  done | sort -rn | cut -f2- | while IFS=: read -r h name; do
    printf '%s\n' "[$h] $name"
  done
}
