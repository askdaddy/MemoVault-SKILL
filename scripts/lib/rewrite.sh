#!/usr/bin/env bash
# lib/rewrite.sh - wikilink rewrite for MemoVault (shell-only runtime).
# Provides the link-rewrite half of rename: collect the old title keys of a
# note, then rewrite [[Old]] / [[Old|label]] across brain/ and daily/ to a new
# title. Pure bash + awk, Bash 3.2 safe. No emoji. Never writes outside
# $MM_VAULT. No `sed -i`. No `set -e`.

# Print the wikilink keys for a note file, one per line, deduped, in order:
#   1. filename stem (basename without .md)
#   2. frontmatter `title:` value (if any)
#   3. each item in frontmatter `aliases:` (inline `[a, b]` form only)
# Empty/blank keys are skipped. Returns 0 even if the file is missing.
mm_wikilink_keys_for_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  local stem; stem="$(basename "$file" .md)"
  {
    printf '%s\n' "$stem"
    awk '
      function strip_quotes(s) {
        if (length(s) >= 2) {
          q = substr(s, 1, 1)
          if ((q == "\"" || q == "'\''") && substr(s, length(s), 1) == q)
            return substr(s, 2, length(s) - 2)
        }
        return s
      }
      /^---[[:space:]]*$/ { c++; next }
      c == 1 {
        if ($0 ~ /^title:/) {
          sub(/^title:[[:space:]]*/, "")
          gsub(/^[ \t]+|[ \t]+$/, "")
          $0 = strip_quotes($0)
          if ($0 != "") print
        } else if ($0 ~ /^aliases:/) {
          sub(/^aliases:[[:space:]]*/, "")
          sub(/^\[/, ""); sub(/\][[:space:]]*$/, "")
          n = split($0, parts, ",")
          for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", parts[i])
            parts[i] = strip_quotes(parts[i])
            if (parts[i] != "") print parts[i]
          }
        }
      }
    ' "$file"
  } | awk '!seen[$0]++'
}

# Rewrite wikilinks across $MM_VAULT/brain and $MM_VAULT/daily.
# Usage: printf '%s\n' <keys> | mm_rewrite_wikilinks <new_title>
# Reads old keys from stdin (one per line). For each markdown file under brain/
# and daily/, scans non-fenced lines for [[target]] and [[target|label]]; if the
# trimmed target equals any old key, replaces the target with new_title
# (whitespace around target is normalized; label is preserved). Fenced ````
# blocks are skipped. Writes via mktemp + mv (no sed -i). Prints
# "files_updated=N" to stdout. Returns non-zero if any file rewrite fails.
mm_rewrite_wikilinks() {
  local new_title="$1"
  [ -n "$new_title" ] || mm_die "rewrite_wikilinks: missing new_title"
  [ -d "$MM_VAULT" ] || { printf 'files_updated=0\n'; return 0; }

  local keys_file; keys_file="$(mktemp)"
  cat > "$keys_file"
  # No keys means nothing to rewrite.
  if [ ! -s "$keys_file" ]; then
    rm -f "$keys_file"
    printf 'files_updated=0\n'
    return 0
  fi

  local files_updated=0
  local d f tmp rc
  for d in "$MM_VAULT/brain" "$MM_VAULT/daily"; do
    [ -d "$d" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      tmp="$(mktemp)"
      new_title="$new_title" keys_file="$keys_file" awk '
        BEGIN {
          new_title = ENVIRON["new_title"]
          kf = ENVIRON["keys_file"]
          n = 0
          while ((getline line < kf) > 0) {
            if (line != "") keys[n++] = line
          }
          close(kf)
          in_fence = 0
          changed = 0
        }
        /^```/ { in_fence = !in_fence; print; next }
        {
          if (in_fence) { print; next }
          s = $0
          out = ""
          while (match(s, /\[\[[^]]+\]\]/)) {
            pre = substr(s, 1, RSTART-1)
            link = substr(s, RSTART+2, RLENGTH-4)
            s = substr(s, RSTART+RLENGTH)
            target = link
            label = ""
            p = index(link, "|")
            if (p > 0) {
              target = substr(link, 1, p-1)
              label = substr(link, p+1)
            }
            gsub(/^[ \t]+|[ \t]+$/, "", target)
            matched = 0
            for (i = 0; i < n; i++) {
              if (target == keys[i]) { matched = 1; break }
            }
            if (matched) {
              changed = 1
              if (label != "") {
                out = out pre "[[" new_title "|" label "]]"
              } else {
                out = out pre "[[" new_title "]]"
              }
            } else {
              out = out pre "[[" link "]]"
            }
          }
          out = out s
          print out
        }
        END { exit (changed ? 1 : 0) }
      ' "$f" > "$tmp"
      rc=$?
      if [ $rc -eq 1 ]; then
        if mv "$tmp" "$f"; then
          files_updated=$((files_updated + 1))
        else
          rm -f "$tmp"
          mm_log "rewrite_wikilinks: failed to write $f" >&2
          rm -f "$keys_file"
          return 1
        fi
      else
        rm -f "$tmp"
      fi
    done < <(find "$d" -type f -name '*.md' 2>/dev/null)
  done

  rm -f "$keys_file"
  printf 'files_updated=%d\n' "$files_updated"
}
