# Recall skip MOC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline; user asked 落地). Steps use checkbox (`- [ ]`) syntax for tracking. Do not git commit unless the user asked.

**Goal:** Default `recall` skips domain MOC notes so token-OR plus evergreen maps no longer crowd out the leaf note; close 0.8.0 merge-readiness gaps; redact the live-vault secret note.

**Architecture:** Add `mmfs_is_moc` in `scripts/lib/fs.sh`. Call it only inside `mmfs_recall` (FTS union loop and both graph-neighbor loops). Leave `mmfs_search_file_ok` unchanged so `search` still finds maps. Fold into unreleased 0.8.0.

**Tech Stack:** bash 3.2, e2e under `scripts/e2e/`, markdown docs.

## Global Constraints

- Skill name `memovault`; never write outside `$AGENT_MEMO_VAULT`; no emoji.
- `#!/usr/bin/env bash`, `set -uo pipefail`, no `set -e` in the helper.
- English comments and user-facing helper strings.
- Do not bump past `0.8.0`. Do not implement vector search.
- Do not commit unless the user explicitly asks.

---

### Task 1: Failing e2e — recall skips MOC, search keeps it

**Files:**
- Modify: `scripts/e2e/suites/03-retrieve.sh` (append after the token-OR block)

**Interfaces:**
- Consumes: existing `e2e_mm`, `E2E_STEM`, `E2E_PHASE`, `assert_contains`
- Produces: two asserts that fail until Task 2

- [ ] **Step 1: Write the failing test**

Append to `scripts/e2e/suites/03-retrieve.sh`:

```bash
# 0.8.0: recall skips domain MOC; search still finds it
moc_leaf="${E2E_STEM} KillMode Leaf"
e2e_mm new "$dom" "$moc_leaf" --kind atom --body "leaf only" >/dev/null 2>&1 || true
e2e_mm moc "$dom" >/dev/null 2>&1 || true
moc_rec="$(e2e_mm recall "KillMode" --limit 5 2>/dev/null || true)"
assert_contains "$moc_rec" "title=$moc_leaf" "recall KillMode hits leaf not crowded out ($E2E_PHASE)"
case "$moc_rec" in
  *_*-MOC.md*|*"title=$dom MOC"*)
    e2e_fail "recall omits domain MOC ($E2E_PHASE)" "out=$moc_rec"
    ;;
  *) e2e_pass "recall omits domain MOC ($E2E_PHASE)" ;;
esac
moc_search="$(e2e_mm search "KillMode" --limit 20 2>/dev/null || true)"
case "$moc_search" in
  *_*-MOC.md*|*${dom}-MOC*|"*"title=$dom MOC"*)
    e2e_pass "search still finds domain MOC ($E2E_PHASE)"
    ;;
  *)
    case "$moc_search" in
      *_${dom}-MOC.md*) e2e_pass "search still finds domain MOC ($E2E_PHASE)" ;;
      *) e2e_fail "search still finds domain MOC ($E2E_PHASE)" "out=$moc_search" ;;
    esac
    ;;
esac
```

Fix the nested quotes in the search case when writing the file: match `_e2e-MOC` via `*"_${dom}-MOC.md"*` and `"*"title=$dom MOC"*`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash -c 'cd /Users/seven/Workspace/MemoVault-SKILL && ./scripts/e2e/run.sh --suite 03'`
(or the project's equivalent filter if `--suite` is unsupported: `E2E_ONLY=03-retrieve ./scripts/e2e/run.sh`)

Expected: FAIL on `recall omits domain MOC` (MOC appears in recall output).

- [ ] **Step 3: Implement `mmfs_is_moc` + recall skips**

In `scripts/lib/fs.sh` after `mmfs_search_file_ok`:

```bash
# Return 0 if file is a domain MOC index (recall skips these; search does not).
mmfs_is_moc() {
  local file="$1" base tags
  [ -f "$file" ] || return 1
  base="$(basename "$file")"
  case "$base" in
    _*-MOC.md) return 0 ;;
  esac
  tags="$(mmfs_get_prop "$file" tags)"
  printf '%s' "$tags" | grep -Eq '(^|[[:space:]\[,])moc([,\][:space:]]|$)' || return 1
  return 0
}
```

In `mmfs_recall` FTS loop, after `mmfs_search_file_ok` succeeds:

```bash
mmfs_is_moc "$abs" && continue
```

In both graph neighbor loops, after `mmfs_search_file_ok` succeeds:

```bash
mmfs_is_moc "$nabs" && continue
```

- [ ] **Step 4: Re-run 03-retrieve; expect pass**

---

### Task 2: `wide_query` hint e2e + epoch=0 same-day overlap

**Files:**
- Modify: `scripts/e2e/suites/06-obs.sh` (before restoring `E2E_VAULT`)
- Modify: `scripts/lib/obs.sh` capture_after_miss overlap branch

- [ ] **Step 1: Failing health hint test**

In the iso2 block of `06-obs.sh`, after the title-overlap assert:

```bash
iso3="$E2E_ROOT/iso-wide-query"
mkdir -p "$iso3/.memovault" "$iso3/brain/iso"
E2E_VAULT="$iso3"
today="$(date -u +%Y-%m-%d)"
{
  i=1
  while [ "$i" -le 5 ]; do
    printf 'ts=%sT00:00:0%sZ event=recall q=a_b_c_d hits=0 top= token_n=4\n' "$today" "$i"
    i=$((i + 1))
  done
} > "$iso3/.memovault/ledger.log"
hwq="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hwq" "wide_query_7d=5" "wide_query_7d counts token_n>=4 ($E2E_PHASE)"
assert_contains "$hwq" "hint=wide_query" "hint=wide_query when recall_7d>=5 and wide_query_7d>=5 ($E2E_PHASE)"
```

Times `00:00:01` .. `00:00:05` so ISO stays valid (`00:00:01` not `00:00:0` + 10). Use `printf '%02d'`.

- [ ] **Step 2: Run 06-obs; expect FAIL on hint=wide_query or count (if health already counts, only hint might fail — then the test is still valid if currently missing)**

If `wide_query_7d` already works, this test may PASS immediately. That is acceptable for an existing untested feature; do not weaken the assert.

- [ ] **Step 3: Epoch=0 same-day guard**

In `scripts/lib/obs.sh`, replace the overlap count so that when `cap_ep` or `miss_ep` is 0:

```bash
          if mm_obs_tokens_overlap "$cap_title" "$miss_q"; then
            if [ "${cap_ep:-0}" -le 0 ] 2>/dev/null || [ "${miss_ep:-0}" -le 0 ] 2>/dev/null; then
              cap_day="$(printf '%s' "$cap_ts" | cut -c1-10)"
              miss_day="$(printf '%s' "$miss_ts" | cut -c1-10)"
              [ "$cap_day" = "$miss_day" ] || continue
            fi
            capture_after_miss_7d=$((capture_after_miss_7d + 1))
            break
          fi
```

No new e2e required if forging unparseable `ts=` drops the row from the 7d window; the spec still wants the guard in code.

---

### Task 3: Docs, CHANGELOG, VERSION newline, RIPER

**Files:**
- Modify: `SKILL.md`, `install/adapters/_protocol.md`, `docs/ARCHITECTURE.md`, `docs/INSTALL.md`, `CHANGELOG.md`, `VERSION`, `docs/RIPER.md`

- [ ] Recall docs: default recall excludes MOC indexes; use `search` or `moc <domain>` for the map.
- [ ] INSTALL upgrade notes: add bullet that **0.7.2 → 0.8.0 requires `upgrade`** so adapters pick up token-OR protocol (1–3 tokens). Until then installed agents still send phrase queries to the old helper.
- [ ] CHANGELOG `[0.8.0]` Changed: recall skips `_*-MOC.md`; INSTALL upgrade note.
- [ ] `VERSION` ends with a newline (`0.8.0\n`).
- [ ] RIPER entry 21 for this Execute.

---

### Task 4: Redact vault secret (not in git)

**Files:**
- Modify: `$AGENT_MEMO_VAULT/brain/crypto/openclaw-home 备份迁移内容.md`

- [ ] Rewrite the body to list key *names* and backup layout only. Delete values after `ZAI_API_KEY=` and any other credential-shaped substrings. Bump `updated: 2026-08-27`.
- [ ] Verify `rg 'ZAI_API_KEY=.'` on that file has no secret material.

---

### Task 5: Full e2e + live vault smoke

- [ ] `./scripts/e2e/run.sh` — expect fail=0
- [ ] Repo helper: `recall KillMode --limit 5` includes the KillMode leaf, excludes `engineering MOC`
- [ ] Repo helper: `recall PERC --limit 5` is not dominated by `*_MOC.md`

Do not run `git commit`. Optionally tell the user to `memovault upgrade` from this checkout.
