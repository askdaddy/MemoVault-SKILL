# CLI snippet library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a vault-local, non-interactive CLI snippet store (`snip`) with pet semantics (`kind: snippet`, parameterized commands, no exec), so agents can save and retrieve shell commands without polluting default `recall` / `search`.

**Architecture:** New `scripts/lib/snip.sh` owns snippet CRUD, fence extraction, and `<name=default>` expansion. `scripts/lib/fs.sh` extends the kind enum and excludes `snippet` from default search/recall (like `raw`). `scripts/lib/obs.sh` counts `kind_snippet`. Dispatch and protocol live in `memovault.sh` / `SKILL.md` / `_protocol.md`. No pet binary.

**Tech Stack:** bash 3.2, awk, rg/grep, markdown + YAML frontmatter, `scripts/e2e/run.sh`.

**Spec:** `docs/superpowers/specs/2026-09-04-snippet-library-design.md`

## Global Constraints

- Skill name `memovault`. Never write outside `$AGENT_MEMO_VAULT`. No emoji.
- `#!/usr/bin/env bash`, `set -uo pipefail`, no `set -e` inside the helper.
- No associative arrays, no `${v,,}`, no `mapfile` / `readarray`.
- English comments and user-facing helper strings. Dates ISO 8601.
- Do not wrap or probe `pet`. Helper must never `eval` / `sh -c` / `bash -c` a stored command.
- Do not implement gist/TOML import/export, `exec`, fzf, or language snippets.
- Do not change `use_rate` / `cite_rate` / `recall_hit_rate` / `kind_other_pct` formulas.
- Do not merge the pending 0.8.1 health-honesty spec. Leave `[Unreleased]` health-reports notes in CHANGELOG as they are.
- Do not git commit unless the user explicitly asks. Skip every Commit step otherwise.
- Every task implicitly includes this section.

## File map

| File | Responsibility |
|---|---|
| `scripts/lib/snip.sh` | `snip` / `snippet` subcommands, extract, expand, write fence files |
| `scripts/lib/fs.sh` | kind enum, heat for snippet, search/recall exclude, `--include-snippet` |
| `scripts/lib/obs.sh` | `kind_snippet=` (after `kind_skill=`; not in `kind_other`) |
| `scripts/memovault.sh` | source `snip.sh`, dispatch, usage |
| `scripts/e2e/suites/10-snip.sh` | spec section 10 asserts |
| `scripts/e2e/run.sh` | add `10-snip` to the suite list |
| `SKILL.md`, `install/adapters/_protocol.md` | commands + CLI snippets protocol |
| `AGENTS.md`, `docs/*`, `README.md`, `README_CN.md` | surface, kind table, layers |
| `VERSION`, `CHANGELOG.md`, `docs/RIPER.md` | `0.9.0` + process record |

---

### Task 1: Failing e2e suite for snippet library

**Files:**
- Create: `scripts/e2e/suites/10-snip.sh`
- Modify: `scripts/e2e/run.sh` (suite list around the `for s in 01-preflight ...` line)

**Interfaces:**
- Consumes: `e2e_mm`, `E2E_STEM`, `E2E_VAULT`, `E2E_PHASE`, `E2E_REPO`, `assert_*` from `scripts/e2e/lib/assert.sh`
- Produces: a suite that fails until Tasks 2–3 land; unique titles via `E2E_STEM`

- [ ] **Step 1: Write the failing suite**

Create `scripts/e2e/suites/10-snip.sh`:

```bash
#!/usr/bin/env bash
# Sourced by run.sh. Uses e2e_mm, E2E_STEM, E2E_VAULT, E2E_PHASE, E2E_REPO, assert_*.
# Spec: docs/superpowers/specs/2026-09-04-snippet-library-design.md section 10.

tok="snptok$(printf '%s' "$E2E_STEM" | tr -cd '0-9')"
t_ssl="${E2E_STEM} SSL expiry"
t_dup="${E2E_STEM} SSL expiry"
t_path="${E2E_STEM} List path"
t_tag="${E2E_STEM} Ping dns"
cmd_ssl="echo | openssl s_client -connect <host=example.com>:443 2>/dev/null | openssl x509 -dates -noout ${tok}"
cmd_path="ls <path>"
cmd_tag="ping -c 1 8.8.8.8"

# 13. helper must not exec stored commands
if [ -f "$E2E_REPO/scripts/lib/snip.sh" ] \
  && grep -E 'eval |sh -c|bash -c' "$E2E_REPO/scripts/lib/snip.sh" >/dev/null 2>&1; then
  e2e_fail "snip.sh has no eval/sh -c/bash -c ($E2E_PHASE)" "matched exec pattern"
else
  if [ -f "$E2E_REPO/scripts/lib/snip.sh" ]; then
    e2e_pass "snip.sh has no eval/sh -c/bash -c ($E2E_PHASE)"
  else
    e2e_fail "snip.sh has no eval/sh -c/bash -c ($E2E_PHASE)" "missing scripts/lib/snip.sh"
  fi
fi

h_before="$(e2e_mm health 2>/dev/null || true)"
other_before="$(printf '%s\n' "$h_before" | awk -F= '/^kind_other=/ { print $2; exit }')"
[ -n "$other_before" ] || other_before=0

# 1 / 12. snip new writes kind/domain/heat/fence; empty --command fails
empty_rc=0
e2e_mm snip new "${E2E_STEM} Empty" --command "" >/dev/null 2>&1 || empty_rc=$?
if [ "$empty_rc" -ne 0 ]; then
  e2e_pass "snip new empty command nonzero ($E2E_PHASE)"
else
  e2e_fail "snip new empty command nonzero ($E2E_PHASE)" "exit 0"
fi

nout="$(e2e_mm snip new "$t_ssl" --command "$cmd_ssl" --tags ssl,openssl 2>/dev/null || true)"
assert_contains "$nout" "path=brain/snippets/" "snip new path ($E2E_PHASE)"
assert_contains "$nout" "title=$t_ssl" "snip new title ($E2E_PHASE)"
sf="$E2E_VAULT/brain/snippets/${t_ssl}.md"
assert_file "$sf" "snip new file ($E2E_PHASE)"
assert_grep '^kind: snippet$' "$sf" "snip kind ($E2E_PHASE)"
assert_grep '^domain: snippets$' "$sf" "snip domain ($E2E_PHASE)"
assert_grep '^heat: growing$' "$sf" "snip heat growing ($E2E_PHASE)"
assert_grep '^```bash$' "$sf" "snip bash fence ($E2E_PHASE)"
assert_grep "$tok" "$sf" "snip command token ($E2E_PHASE)"

# 2. duplicate title does not overwrite
echo marker-keep >> "$sf"
dup_rc=0
e2e_mm snip new "$t_dup" --command "echo overwritten" >/dev/null 2>&1 || dup_rc=$?
if [ "$dup_rc" -ne 0 ]; then
  e2e_pass "snip new duplicate title fails ($E2E_PHASE)"
else
  e2e_fail "snip new duplicate title fails ($E2E_PHASE)" "exit 0"
fi
assert_grep 'marker-keep' "$sf" "snip new duplicate does not overwrite ($E2E_PHASE)"

e2e_mm snip new "$t_path" --command "$cmd_path" >/dev/null 2>&1 || true
e2e_mm snip new "$t_tag" --command "$cmd_tag" --tags network,dns >/dev/null 2>&1 || true

# 3 / 4 / 5. list / search / --tag
lout="$(e2e_mm snip list 2>/dev/null || true)"
assert_contains "$lout" "title=$t_ssl" "snip list title ($E2E_PHASE)"
assert_contains "$lout" "tags=ssl,openssl" "snip list tags ($E2E_PHASE)"
assert_contains "$lout" "command=" "snip list command field ($E2E_PHASE)"
assert_contains "$lout" "$tok" "snip list command token ($E2E_PHASE)"

sout="$(e2e_mm snip search "$tok" 2>/dev/null || true)"
assert_contains "$sout" "title=$t_ssl" "snip search hits command body ($E2E_PHASE)"
case "$sout" in
  *"title=$t_path"*) e2e_fail "snip search does not list unrelated ($E2E_PHASE)" "out=$sout" ;;
  *) e2e_pass "snip search does not list unrelated ($E2E_PHASE)" ;;
esac

tagout="$(e2e_mm snip list --tag dns 2>/dev/null || true)"
assert_contains "$tagout" "title=$t_tag" "snip list --tag dns hits ($E2E_PHASE)"
case "$tagout" in
  *"title=$t_ssl"*) e2e_fail "snip list --tag dns excludes ssl ($E2E_PHASE)" "out=$tagout" ;;
  *) e2e_pass "snip list --tag dns excludes ssl ($E2E_PHASE)" ;;
esac

# 6 / 7. get expand
got="$(e2e_mm snip get "$t_ssl" 2>/dev/null || true)"
case "$got" in
  title=*|"path="*) e2e_fail "snip get is command only ($E2E_PHASE)" "out=$got" ;;
  *) e2e_pass "snip get is command only ($E2E_PHASE)" ;;
esac
assert_contains "$got" "example.com" "snip get fills default host ($E2E_PHASE)"
case "$got" in
  *"<host="*) e2e_fail "snip get default removes placeholder ($E2E_PHASE)" "out=$got" ;;
  *) e2e_pass "snip get default removes placeholder ($E2E_PHASE)" ;;
esac

got_set="$(e2e_mm snip get "$t_ssl" --set host=example.org 2>/dev/null || true)"
assert_contains "$got_set" "example.org" "snip get --set host ($E2E_PHASE)"
case "$got_set" in
  *example.com*) e2e_fail "snip get --set replaces default ($E2E_PHASE)" "out=$got_set" ;;
  *) e2e_pass "snip get --set replaces default ($E2E_PHASE)" ;;
esac

got_path="$(e2e_mm snip get "$t_path" 2>/dev/null || true)"
assert_contains "$got_path" "<path>" "snip get keeps nameless placeholder ($E2E_PHASE)"

# 8 / 9. default recall/search hide snippet; include flags show it
rec="$(e2e_mm recall "$tok" --limit 5 2>/dev/null || true)"
case "$rec" in
  *"$tok"*|*"title=$t_ssl"*) e2e_fail "recall hides snippet ($E2E_PHASE)" "out=$rec" ;;
  *) e2e_pass "recall hides snippet ($E2E_PHASE)" ;;
esac
sdef="$(e2e_mm search "$tok" 2>/dev/null || true)"
case "$sdef" in
  *"$tok"*|*"$t_ssl"*) e2e_fail "search hides snippet ($E2E_PHASE)" "out=$sdef" ;;
  *) e2e_pass "search hides snippet ($E2E_PHASE)" ;;
esac
sinc="$(e2e_mm search "$tok" --include-snippet 2>/dev/null || true)"
assert_contains "$sinc" "$t_ssl" "search --include-snippet ($E2E_PHASE)"
skind="$(e2e_mm search "$tok" --kind snippet 2>/dev/null || true)"
assert_contains "$skind" "$t_ssl" "search --kind snippet ($E2E_PHASE)"

# 10. health kind_snippet; not kind_other
hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "kind_snippet=" "health prints kind_snippet ($E2E_PHASE)"
snip_n="$(printf '%s\n' "$hout" | awk -F= '/^kind_snippet=/ { print $2; exit }')"
case "$snip_n" in
  ''|0) e2e_fail "health kind_snippet counts notes ($E2E_PHASE)" "kind_snippet=$snip_n" ;;
  *) e2e_pass "health kind_snippet counts notes ($E2E_PHASE)" ;;
esac
other_after="$(printf '%s\n' "$hout" | awk -F= '/^kind_other=/ { print $2; exit }')"
[ -n "$other_after" ] || other_after=0
if [ "$other_after" -le "$other_before" ]; then
  e2e_pass "snippet does not raise kind_other ($E2E_PHASE)"
else
  e2e_fail "snippet does not raise kind_other ($E2E_PHASE)" "before=$other_before after=$other_after"
fi

# 11. rm requires --yes
rm_rc=0
rm_out="$(e2e_mm snip rm "$t_path" 2>/dev/null)" || rm_rc=$?
if [ "$rm_rc" -eq 2 ]; then
  e2e_pass "snip rm without --yes exit 2 ($E2E_PHASE)"
else
  e2e_fail "snip rm without --yes exit 2 ($E2E_PHASE)" "rc=$rm_rc"
fi
assert_file "$E2E_VAULT/brain/snippets/${t_path}.md" "snip rm without --yes keeps file ($E2E_PHASE)"
e2e_mm snip rm "$t_path" --yes >/dev/null 2>&1 || true
if [ -f "$E2E_VAULT/brain/snippets/${t_path}.md" ]; then
  e2e_fail "snip rm --yes deletes file ($E2E_PHASE)" "still present"
else
  e2e_pass "snip rm --yes deletes file ($E2E_PHASE)"
fi
```

In `scripts/e2e/run.sh`, change the suite loop to:

```bash
  for s in 01-preflight 02-capture 03-retrieve 04-graph 05-organize 06-obs 07-acceptance 08-forward 09-upgrade 10-snip; do
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/e2e/run.sh`

Expected: `10-snip` FAIL (unknown subcommand `snip` and/or missing `scripts/lib/snip.sh`). Suites `01`–`09` should still pass.

- [ ] **Step 3: Commit** (skip unless the user asked)

```bash
git add scripts/e2e/suites/10-snip.sh scripts/e2e/run.sh
git commit -m "$(cat <<'EOF'
test: add failing e2e suite for CLI snippets

EOF
)"
```

---

### Task 2: Accept `kind: snippet` and hide it from default retrieval

**Files:**
- Modify: `scripts/lib/fs.sh` (`mmfs_new` kind case ~97–109, `mmfs_search_file_ok` ~354–386, `mmfs_search` ~404–420, `mmfs_kind_score` ~494–501, three `mmfs_search_file_ok` call sites in `mmfs_recall`)
- Modify: `scripts/lib/obs.sh` (kind switch ~314–321, `printf 'kind_skill=` ~613)

**Interfaces:**
- Consumes: existing `mmfs_search_file_ok` 6-arg calls (7th arg defaults to 0)
- Produces: `kind: snippet` is valid; default search/recall skip it; `--include-snippet` and `--kind snippet` include it; `kind_snippet=` on health

- [ ] **Step 1: Kind enum + default heat**

In `mmfs_new`, replace the kind case and heat default:

```bash
  if [ -n "$kind" ]; then
    case "$kind" in
      raw|atom|scenario|persona|skill|snippet) ;;
      *) mm_die "invalid kind: $kind (raw|atom|scenario|persona|skill|snippet)" ;;
    esac
  fi
  mmfs_ensure_vault
  mkdir -p "$MM_VAULT/brain/$domain"
  local file; file="$(mmfs_note_path "$domain" "$title")"
  [ -f "$file" ] && mm_die "note already exists: $title ($file). Use append instead."
  local today; today="$(mmfs_today)"
  local title_clean; title_clean="$(mmfs_sanitize_title "$title")"
  local heat="seedling"
  case "$kind" in
    skill|snippet) heat="growing" ;;
  esac
```

- [ ] **Step 2: Search/recall filter**

Replace `mmfs_search_file_ok` with a 7th argument `include_snippet` (default 0). When `want_kind` is `snippet`, treat include as 1:

```bash
# Return 0 if note file passes search filters.
# Args: file domain kind heat include_raw include_superseded [include_snippet]
mmfs_search_file_ok() {
  local file="$1" want_domain="$2" want_kind="$3" want_heat="$4" include_raw="$5"
  local include_superseded="${6:-0}"
  local include_snippet="${7:-0}"
  local rel prop
  rel="${file#"$MM_VAULT"/}"
  case "$rel" in
    daily/*|.memovault/*) return 1 ;;
  esac
  if [ "$want_kind" = snippet ]; then
    include_snippet=1
  fi
  if [ "$include_raw" != 1 ]; then
    prop="$(mmfs_get_prop "$file" kind)"
    [ "$prop" = raw ] && return 1
  fi
  if [ "$include_snippet" != 1 ]; then
    prop="$(mmfs_get_prop "$file" kind)"
    [ "$prop" = snippet ] && return 1
  fi
  if [ "$include_superseded" != 1 ]; then
    prop="$(mmfs_get_prop "$file" status)"
    [ "$prop" = superseded ] && return 1
  fi
  if [ -n "$want_domain" ]; then
    prop="$(mmfs_get_prop "$file" domain)"
    [ "$prop" = "$want_domain" ] || return 1
  fi
  if [ -n "$want_kind" ]; then
    prop="$(mmfs_get_prop "$file" kind)"
    [ "$prop" = "$want_kind" ] || return 1
  fi
  if [ -n "$want_heat" ]; then
    prop="$(mmfs_get_prop "$file" heat)"
    [ -n "$prop" ] || prop="seedling"
    [ "$prop" = "$want_heat" ] || return 1
  fi
  return 0
}
```

In `mmfs_search`: add `include_snippet=0`, parse `--include-snippet`, and pass the 7th arg. Update the usage string. Do **not** change `--kind raw` behavior.

```bash
  local limit="" domain="" kind="" heat="" include_raw=0 include_superseded=0 include_snippet=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="${2:-}"; shift 2 ;;
      --domain) domain="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
      --heat) heat="${2:-}"; shift 2 ;;
      --include-raw) include_raw=1; shift ;;
      --include-snippet) include_snippet=1; shift ;;
      --include-superseded) include_superseded=1; shift ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: search <query> [--limit N] [--domain D] [--kind K] [--heat H] [--include-raw] [--include-snippet] [--include-superseded]"
```

Change the `mmfs_search_file_ok` call inside `mmfs_search` to:

```bash
      if mmfs_search_file_ok "$abs" "$domain" "$kind" "$heat" "$include_raw" "$include_superseded" "$include_snippet"; then
```

Leave the three `mmfs_recall` calls as 6-arg (`include_snippet` defaults to 0) so recall always hides snippets.

Update `mmfs_kind_score`:

```bash
mmfs_kind_score() {
  case "$1" in
    persona|skill|scenario|atom) printf '2' ;;
    raw|snippet) printf '0' ;;
    *) printf '1' ;;
  esac
}
```

Update the comment above `mmfs_search` to mention default exclusion of `kind: snippet`.

- [ ] **Step 3: health `kind_snippet`**

In `mm_obs_health`, next to `kind_skill=0` add `kind_snippet=0`. In the kind case:

```bash
      case "$k" in
        atom) kind_atom=$((kind_atom + 1)) ;;
        raw) kind_raw=$((kind_raw + 1)) ;;
        scenario) kind_scenario=$((kind_scenario + 1)) ;;
        persona) kind_persona=$((kind_persona + 1)) ;;
        skill) kind_skill=$((kind_skill + 1)) ;;
        snippet) kind_snippet=$((kind_snippet + 1)) ;;
        *) kind_other=$((kind_other + 1)) ;;
      esac
```

After `printf 'kind_skill=%s\n' "$kind_skill"` insert:

```bash
  printf 'kind_snippet=%s\n' "$kind_snippet"
```

Do not add `kind_snippet` to the health-snap key list (spec: do not change existing efficacy formulas or snapshot schema).

- [ ] **Step 4: Run tests**

Run: `./scripts/e2e/run.sh`

Expected: `01`–`09` PASS. `10-snip` still FAIL on `snip` subcommands. A smoke check that kind plumbing works:

```bash
AGENT_MEMO_VAULT=/tmp/mm-snip-smoke mkdir -p /tmp/mm-snip-smoke
# use the repo helper against a temp vault; or rely on e2e after Task 3
```

Do not require 10-snip green yet.

- [ ] **Step 5: Commit** (skip unless the user asked)

```bash
git add scripts/lib/fs.sh scripts/lib/obs.sh
git commit -m "$(cat <<'EOF'
feat: accept kind snippet and exclude it from default recall

EOF
)"
```

---

### Task 3: Implement `snip` helper and dispatch

**Files:**
- Create: `scripts/lib/snip.sh`
- Modify: `scripts/memovault.sh` (source after `eval.sh`; `mm_usage`; `main` case)

**Interfaces:**
- Consumes: `mmfs_sanitize_title`, `mmfs_find_note`, `mmfs_locate`, `mmfs_note_path`, `mmfs_yaml_list`, `mmfs_get_prop`, `mmfs_ensure_vault`, `mmfs_today`, `mm_obs_log`, `mm_die`, `mm_log`, `$MM_VAULT`
- Produces: `mm_snip_main` for `snip` / `snippet`; stdout contracts from spec §5.1

- [ ] **Step 1: Write `scripts/lib/snip.sh`**

Create the file exactly as follows (English comments; no emoji; no `eval` / `sh -c` / `bash -c`):

```bash
#!/usr/bin/env bash
# lib/snip.sh - vault-local CLI snippet library (pet semantics, no exec).
# Sourced by memovault.sh. Bash 3.2. Never writes outside $MM_VAULT.

mm_snip_usage() {
  cat <<'USAGE'
snip - local CLI snippet library (kind: snippet).

  snip new "<description>" --command "..." [--tags a,b]
  snip list [--tag t] [--limit N]
  snip search "<query>" [--tag t] [--limit N]
  snip get "<description>" [--set name=value ...]
  snip rm "<description>" --yes

Default recall/search omit snippets. Helper never executes stored commands.
USAGE
}

mm_snip_trim() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  printf '%s' "$t"
}

# Extract command text from a snippet note (first fenced block, else body).
mm_snip_extract_command() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    BEGIN { fm = 0; in_fence = 0; got = 0; cmd = ""; fb = ""; stop_fb = 0 }
    /^---[[:space:]]*$/ {
      if (fm == 0) { fm = 1; next }
      if (fm == 1) { fm = 2; next }
    }
    fm < 2 { next }
    /^```/ {
      if (in_fence == 0 && got == 0) { in_fence = 1; next }
      if (in_fence == 1) { in_fence = 0; got = 1; next }
    }
    in_fence == 1 {
      if (cmd != "") cmd = cmd "\n"
      cmd = cmd $0
      next
    }
    got == 1 { next }
    /^#/ { next }
    /^Related:/ { stop_fb = 1; next }
    /^## / { stop_fb = 1; next }
    stop_fb == 1 { next }
    {
      if (fb != "") fb = fb "\n"
      fb = fb $0
    }
    END {
      out = (got == 1) ? cmd : fb
      while (out ~ /^\n/) out = substr(out, 2)
      while (out ~ /\n$/) out = substr(out, 1, length(out) - 1)
      printf "%s", out
    }
  ' "$file"
}

# Flatten command for list/search: newlines -> two chars \n, tabs -> space.
mm_snip_flatten() {
  printf '%s' "$1" | tr '\t' ' ' | awk '{
    if (NR > 1) printf "\\n"
    printf "%s", $0
  }'
}

# YAML tags line -> csv with no spaces: [ssl, openssl] -> ssl,openssl
mm_snip_tags_csv() {
  local file="$1" raw
  raw="$(mmfs_get_prop "$file" tags)"
  raw="$(printf '%s' "$raw" | tr -d '[]')"
  raw="$(printf '%s' "$raw" | tr -d ' ')"
  printf '%s' "$raw"
}

mm_snip_has_tag() {
  local csv="$1" want="$2" tok
  [ -n "$want" ] || return 0
  [ -n "$csv" ] || return 1
  oldifs="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  set -- $csv
  IFS="$oldifs"
  for tok in "$@"; do
    [ "$tok" = "$want" ] && return 0
  done
  return 1
}

# Expand <name> / <name=default>. sets_file: lines of name=value (last wins).
mm_snip_expand() {
  local src="$1" sets_file="$2"
  printf '%s' "$src" | awk -v sf="$sets_file" '
    BEGIN {
      while ((getline line < sf) > 0) {
        eq = index(line, "=")
        if (eq > 0) {
          k = substr(line, 1, eq - 1)
          v = substr(line, eq + 1)
          map[k] = v
        }
      }
      close(sf)
    }
    {
      s = $0
      result = ""
      while (match(s, /<[^>]*>/)) {
        result = result substr(s, 1, RSTART - 1)
        tok = substr(s, RSTART, RLENGTH)
        inner = substr(tok, 2, length(tok) - 2)
        eq = index(inner, "=")
        if (eq > 0) {
          name = substr(inner, 1, eq - 1)
          def = substr(inner, eq + 1)
        } else {
          name = inner
          def = ""
        }
        if (name in map) result = result map[name]
        else if (eq > 0) result = result def
        else result = result tok
        s = substr(s, RSTART + RLENGTH)
      }
      result = result s
      print result
    }
  '
}

mm_snip_is_snippet_file() {
  local file="$1" k
  [ -f "$file" ] || return 1
  k="$(mmfs_get_prop "$file" kind)"
  [ "$k" = snippet ]
}

mm_snip_is_listed() {
  local file="$1" st
  mm_snip_is_snippet_file "$file" || return 1
  st="$(mmfs_get_prop "$file" status)"
  [ "$st" = superseded ] && return 1
  return 0
}

mm_snip_emit_row() {
  local file="$1" title tags cmd
  title="$(mmfs_get_prop "$file" title)"
  [ -n "$title" ] || title="$(basename "$file" .md)"
  tags="$(mm_snip_tags_csv "$file")"
  cmd="$(mm_snip_extract_command "$file")"
  cmd="$(mm_snip_flatten "$cmd")"
  printf 'title=%s tags=%s command=%s\n' "$title" "$tags" "$cmd"
}

mm_snip_each_listed() {
  local f
  [ -d "$MM_VAULT/brain" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mm_snip_is_listed "$f" || continue
    printf '%s\n' "$f"
  done <<EOF
$(find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
EOF
}

mm_snip_new() {
  local desc="" cmd="" tags=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --command) cmd="${2-}"; shift 2 ;;
      --tags) tags="${2-}"; shift 2 ;;
      --*) mm_die "unknown flag: $1" ;;
      *)
        if [ -z "$desc" ]; then
          desc="$1"
          shift
        else
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  desc="$(mm_snip_trim "$desc")"
  cmd="$(mm_snip_trim "$cmd")"
  [ -n "$desc" ] || mm_die "usage: snip new \"<description>\" --command \"...\""
  [ -n "$cmd" ] || mm_die "snip new: --command is required and must be non-empty"
  case "$cmd" in
    *\`\`\`*) mm_die "snip new: command must not contain a markdown fence" ;;
  esac
  mmfs_ensure_vault
  local title_clean hit dest
  title_clean="$(mmfs_sanitize_title "$desc")"
  hit="$(mmfs_find_note "$title_clean")"
  if [ -n "$hit" ] && [ -f "$hit" ]; then
    mm_die "snippet already exists: $title_clean ($hit)"
  fi
  mkdir -p "$MM_VAULT/brain/snippets"
  dest="$(mmfs_note_path snippets "$title_clean")"
  local today
  today="$(mmfs_today)"
  {
    printf -- '---\n'
    printf 'title: %s\n' "$title_clean"
    printf 'domain: snippets\n'
    printf 'kind: snippet\n'
    printf 'tags: %s\n' "$(mmfs_yaml_list "$tags")"
    printf 'heat: growing\n'
    printf 'aliases: []\n'
    printf 'sources: []\n'
    printf 'created: %s\n' "$today"
    printf 'updated: %s\n' "$today"
    printf -- '---\n\n'
    printf '```bash\n'
    printf '%s\n' "$cmd"
    printf '```\n'
  } > "$dest"
  mm_obs_log "event=snip" "op=new" "title=$title_clean"
  printf 'path=%s title=%s\n' "${dest#"$MM_VAULT"/}" "$title_clean"
}

mm_snip_parse_list_flags() {
  SNIP_TAG=""
  SNIP_LIMIT=""
  SNIP_QUERY=""
  local saw_query=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tag) SNIP_TAG="${2-}"; shift 2 ;;
      --limit) SNIP_LIMIT="${2-}"; shift 2 ;;
      --*) mm_die "unknown flag: $1" ;;
      *)
        if [ "$saw_query" -eq 0 ]; then
          SNIP_QUERY="$1"
          saw_query=1
          shift
        else
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
}

mm_snip_list() {
  mm_snip_parse_list_flags "$@"
  mmfs_ensure_vault
  local f title kept=0 rows tmp
  tmp="$(mktemp)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mm_snip_has_tag "$(mm_snip_tags_csv "$f")" "$SNIP_TAG" || continue
    title="$(mmfs_get_prop "$f" title)"
    [ -n "$title" ] || title="$(basename "$f" .md)"
    printf '%s\t%s\n' "$title" "$f" >> "$tmp"
  done <<EOF
$(mm_snip_each_listed)
EOF
  while IFS='	' read -r title f; do
    [ -n "$f" ] || continue
    if [ -n "$SNIP_LIMIT" ]; then
      [ "$kept" -ge "$SNIP_LIMIT" ] && break
    fi
    mm_snip_emit_row "$f"
    kept=$((kept + 1))
  done <<EOF
$(LC_ALL=C sort -t '	' -k1,1 "$tmp")
EOF
  rm -f "$tmp"
}

mm_snip_search() {
  mm_snip_parse_list_flags "$@"
  [ -n "$SNIP_QUERY" ] || mm_die "usage: snip search \"<query>\" [--tag t] [--limit N]"
  mmfs_ensure_vault
  local f title tags body kept=0 hits=0 q_tok tmp
  tmp="$(mktemp)"
  q_tok="$(printf '%s' "$SNIP_QUERY" | tr ' ' '_')"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mm_snip_has_tag "$(mm_snip_tags_csv "$f")" "$SNIP_TAG" || continue
    title="$(mmfs_get_prop "$f" title)"
    [ -n "$title" ] || title="$(basename "$f" .md)"
    tags="$(mm_snip_tags_csv "$f")"
    body="$(mm_snip_extract_command "$f")"
    if printf '%s\n%s\n%s\n' "$title" "$tags" "$body" | grep -Fq -- "$SNIP_QUERY"; then
      printf '%s\t%s\n' "$title" "$f" >> "$tmp"
      hits=$((hits + 1))
    fi
  done <<EOF
$(mm_snip_each_listed)
EOF
  while IFS='	' read -r title f; do
    [ -n "$f" ] || continue
    if [ -n "$SNIP_LIMIT" ]; then
      [ "$kept" -ge "$SNIP_LIMIT" ] && break
    fi
    mm_snip_emit_row "$f"
    kept=$((kept + 1))
  done <<EOF
$(LC_ALL=C sort -t '	' -k1,1 "$tmp")
EOF
  rm -f "$tmp"
  mm_obs_log "event=snip" "op=search" "q=$q_tok" "hits=$hits"
}

mm_snip_get() {
  local desc="" sets
  sets="$(mktemp)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --set)
        [ -n "${2-}" ] || { rm -f "$sets"; mm_die "usage: snip get \"<description>\" [--set name=value]"; }
        printf '%s\n' "$2" >> "$sets"
        shift 2
        ;;
      --*) rm -f "$sets"; mm_die "unknown flag: $1" ;;
      *)
        if [ -z "$desc" ]; then
          desc="$1"
          shift
        else
          rm -f "$sets"
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  [ -n "$desc" ] || { rm -f "$sets"; mm_die "usage: snip get \"<description>\" [--set name=value]"; }
  local file k cmd expanded
  file="$(mmfs_locate "$desc")"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    rm -f "$sets"
    mm_die "snippet not found: $desc"
  fi
  k="$(mmfs_get_prop "$file" kind)"
  if [ "$k" != snippet ]; then
    rm -f "$sets"
    mm_die "not a snippet: $desc"
  fi
  cmd="$(mm_snip_extract_command "$file")"
  if [ -z "$cmd" ]; then
    rm -f "$sets"
    mm_die "snippet has empty command: $desc"
  fi
  expanded="$(mm_snip_expand "$cmd" "$sets")"
  rm -f "$sets"
  mm_obs_log "event=snip" "op=get" "title=$(mmfs_get_prop "$file" title)"
  printf '%s\n' "$expanded"
}

mm_snip_rm() {
  local desc="" yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) yes=1; shift ;;
      --*) mm_die "unknown flag: $1" ;;
      *)
        if [ -z "$desc" ]; then
          desc="$1"
          shift
        else
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  [ -n "$desc" ] || mm_die "usage: snip rm \"<description>\" --yes"
  local file k title rel
  file="$(mmfs_locate "$desc")"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    mm_die "snippet not found: $desc"
  fi
  k="$(mmfs_get_prop "$file" kind)"
  [ "$k" = snippet ] || mm_die "not a snippet: $desc"
  title="$(mmfs_get_prop "$file" title)"
  [ -n "$title" ] || title="$(basename "$file" .md)"
  rel="${file#"$MM_VAULT"/}"
  if [ "$yes" != 1 ]; then
    printf 'path=%s title=%s\n' "$rel" "$title"
    mm_log "snip rm: pass --yes after user confirmation"
    return 2
  fi
  rm -f "$file"
  mm_obs_log "event=snip" "op=rm" "title=$title"
  printf 'deleted=1 path=%s title=%s\n' "$rel" "$title"
}

mm_snip_main() {
  local sub="${1:-}"
  if [ -z "$sub" ]; then
    mm_snip_usage
    return 0
  fi
  shift
  case "$sub" in
    new) mm_snip_new "$@" ;;
    list) mm_snip_list "$@" ;;
    search) mm_snip_search "$@" ;;
    get) mm_snip_get "$@" ;;
    rm) mm_snip_rm "$@" ;;
    -h|--help|help) mm_snip_usage ;;
    *) mm_die "unknown snip subcommand: $sub (try: memovault snip)" ;;
  esac
}
```

Fix the fence check in `mm_snip_new`: the case glob in this plan used escaped backticks which may not match three backticks. Implement the check as:

```bash
  printf '%s' "$cmd" | grep -q '```' && mm_die "snip new: command must not contain a markdown fence"
```

(`grep` here is a content check on the incoming argument, not execution of the command.)

- [ ] **Step 2: Wire dispatch**

In `scripts/memovault.sh` after sourcing `eval.sh`:

```bash
# shellcheck source=lib/snip.sh
. "$MM_ROOT/lib/snip.sh"
```

In `mm_usage`, under Retrieve, add:

```
  snip new "<desc>" --command "..." [--tags a,b]
  snip list [--tag t] [--limit N]
  snip search "<query>" [--tag t] [--limit N]
  snip get "<desc>" [--set name=value]
  snip rm "<desc>" --yes
```

Also add `--include-snippet` to the `search` usage line.

In `main` `case`:

```bash
    snip|snippet) mm_snip_main "$@" ;;
```

- [ ] **Step 3: Run e2e**

Run: `./scripts/e2e/run.sh`

Expected: `pass` with `fail=0`, including `10-snip`. If `snip rm without --yes exit 2` fails because `mm_die` exits 1 instead of 2: `mm_snip_rm` must `return 2` (not `mm_die`) when `--yes` is missing; `mm_snip_main` must preserve that status (`return` / not wrap in a way that clobbers `$?`). `main` already calls the function as the case body, so `return 2` from `mm_snip_rm` becomes the script exit status.

If `read -r title f` breaks on titles with tabs, ignore (titles are sanitized). If `set -- $csv` breaks on empty csv, `mm_snip_has_tag` already returns 1 when csv is empty and want is set.

- [ ] **Step 4: Commit** (skip unless the user asked)

```bash
git add scripts/lib/snip.sh scripts/memovault.sh
git commit -m "$(cat <<'EOF'
feat: add snip helper for vault-local CLI snippets

EOF
)"
```

---

### Task 4: Docs, protocol, version 0.9.0

**Files:**
- Modify: `SKILL.md`, `install/adapters/_protocol.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/CLASSIFICATION.md`, `docs/DEVELOPMENT.md`, `README.md`, `README_CN.md`, `VERSION`, `CHANGELOG.md`, `docs/RIPER.md`

**Interfaces:**
- Consumes: behavior locked in Tasks 2–3 and spec §7–11
- Produces: agent-visible contract at 0.9.0; RIPER entry 24

- [ ] **Step 1: VERSION + SKILL frontmatter**

Set `VERSION` to `0.9.0`. Set `SKILL.md` YAML `version: 0.9.0`.

Hard rules kind line:

```
- Optional `kind` is exactly one of: `raw`, `atom`, `scenario`, `persona`, `skill`, `snippet`.
```

Add trigger phrases to the description (keep existing ones): `snip` / `snippet` / `记这个命令` / `存成 snippet` / `save this command`.

In Commands, add a **CLI snippets** block after Capture / edit with the five `snip` invocations. On the `search` line, add `--include-snippet`. Note that default `search` / `recall` exclude `kind: snippet`.

After **Skill capture (SOPs)** insert **CLI snippets (commands)** using spec §7 (English body, Chinese trigger phrases listed). Renumber is not required in SKILL.md (those headings are unnumbered). In `_protocol.md` insert as new section 5 and bump Classify to 6, Guardrails to 7. Update the kind bullet to include `snippet`. Mention default recall/search skip snippets.

- [ ] **Step 2: Charter and human docs**

`AGENTS.md`:
- layout tree: add `lib/snip.sh`
- full surface list: add `snip` (and `snippet` alias)
- kind mention: add `snippet`
- one sentence: `health` prints `kind_snippet=`

`docs/ARCHITECTURE.md`:
- layers box: add `scripts/lib/snip.sh`
- section 5 table: rows for `snip new|list|search|get|rm`
- search row: default also excludes `kind: snippet`; `--include-snippet` / `--kind snippet`
- non-goals: pet binary / gist sync not in this version

`docs/CLASSIFICATION.md` kind table, new row:

```
| `snippet` | Reusable CLI command (pet semantics) | `brain/snippets/` | growing |
```

Rule: default `recall` / `search` skip `snippet`; use `snip search`. SOP how-tos stay `skill`.

`docs/DEVELOPMENT.md` layout recap: mention `snip.sh`. Adding a subcommand: snippet I/O goes in `lib/snip.sh`.

`README.md` / `README_CN.md`: version `0.9.0`; optional kinds add `snippet`.

`CHANGELOG.md`: add `## [0.9.0] - 2026-09-04` (use Execute calendar date if different) **Added**: `snip` / `snippet`; `kind: snippet`; default recall/search exclusion; `--include-snippet`; `kind_snippet`. Keep existing `[Unreleased]` health-reports bullets where they are; do not fold them into 0.9.0 unless that work is part of this Execute.

`docs/RIPER.md` append:

```
## 24. Entry: CLI snippet library (2026-09-04)

### Research
- pet is an interactive TOML CLI snippet manager (fzf, exec, gist). Conflicts with vault-only writes, bash-only runtime, and non-interactive agents.

### Innovate
- A wrap pet. B bash-native pet semantics in vault (chosen). C reuse new/search only.

### Plan
- docs/superpowers/specs/2026-09-04-snippet-library-design.md
- docs/superpowers/plans/2026-09-04-snippet-library.md

### Execute
- (fill after implementation: files touched)

### Review
- (fill: ./scripts/e2e/run.sh pass/fail)
```

Fill Execute/Review during Task 5, not with placeholders left in the merged repo — the implementer writes the real lists after the run.

- [ ] **Step 3: Commit** (skip unless the user asked)

```bash
git add SKILL.md install/adapters/_protocol.md AGENTS.md docs/ARCHITECTURE.md docs/CLASSIFICATION.md docs/DEVELOPMENT.md README.md README_CN.md VERSION CHANGELOG.md docs/RIPER.md
git commit -m "$(cat <<'EOF'
docs: document snip CLI snippets and bump to 0.9.0

EOF
)"
```

---

### Task 5: Full e2e gate and RIPER Review

**Files:**
- Modify: `docs/RIPER.md` entry 24 Execute / Review only if the run output is known

**Interfaces:**
- Consumes: Tasks 1–4
- Produces: green official e2e gate

- [ ] **Step 1: Syntax + e2e**

```bash
bash -n scripts/memovault.sh scripts/lib/*.sh install/install.sh
./scripts/e2e/run.sh
```

Expected: no syntax errors; `=== e2e summary: pass=N fail=0 ===` with N higher than 0.8.0 (10-snip adds ~25 asserts). Confirm `10-snip` lines are PASS.

- [ ] **Step 2: Spec coverage check**

Walk spec §10 items 1–13 against `10-snip.sh`. Walk spec §8 file table against `git status`. Confirm `scripts/lib/snip.sh` still has no `eval ` / `sh -c` / `bash -c`.

- [ ] **Step 3: Write RIPER Execute/Review** with the real file list and e2e counts.

- [ ] **Step 4: Commit** (skip unless the user asked)

---

## Self-review (plan vs spec)

1. **Spec coverage:** §4 data model -> Task 3 write shape + Task 2 kind. §5 commands/stdout/rm exit 2 -> Task 3 + Task 1 asserts. §5.3 search flags -> Task 2. §6 health -> Task 2. §7 protocol -> Task 4. §8 files -> all tasks. §10 e2e -> Task 1/5. §11 version -> Task 4. Non-goals (pet/exec/gist/TOML/0.8.1) -> Global Constraints.
2. **Placeholders:** none left for implementers except RIPER Execute/Review which must be filled from the real run in Task 5.
3. **Names:** `mm_snip_main`, `kind_snippet`, `--include-snippet`, `event=snip`, `deleted=1 path=` match the spec.
